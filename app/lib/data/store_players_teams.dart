part of 'local_event_store.dart';

extension LocalEventStorePlayersTeams on LocalEventStore {
  // ── Teams & Players CRUD ──────────────────────────────────────────────────

  Future<List<TeamProfile>> listTeams() async {
    final db = await database;
    final teamRows = await db.query(
      'teams',
      orderBy: 'is_my_team DESC, created_at DESC',
    );
    final playerRows = await db.query(
      'players',
      where: 'archived = 0',
      orderBy: 'created_at ASC',
    );
    final playersByTeam = <String, List<PlayerProfile>>{};
    for (final row in playerRows) {
      final p = PlayerProfile.fromMap(row);
      playersByTeam.putIfAbsent(p.teamId, () => <PlayerProfile>[]).add(p);
    }
    return [
      for (final row in teamRows)
        TeamProfile.fromMap(
          row,
          squad: playersByTeam[row['id']! as String] ?? const [],
        ),
    ];
  }

  Future<TeamProfile?> getTeam(String teamId) async {
    final db = await database;
    final rows = await db.query(
      'teams',
      where: 'id = ?',
      whereArgs: [teamId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final squad = await listPlayersForTeam(teamId);
    return TeamProfile.fromMap(rows.first, squad: squad);
  }

  Future<List<PlayerProfile>> listPlayersForTeam(
    String teamId, {
    bool includeArchived = false,
  }) async {
    final db = await database;
    final rows = await db.query(
      'players',
      where: includeArchived ? 'team_id = ?' : 'team_id = ? AND archived = 0',
      whereArgs: [teamId],
      orderBy: 'created_at ASC',
    );
    return rows.map(PlayerProfile.fromMap).toList();
  }

  Future<void> saveTeam(TeamProfile team) async {
    final db = await database;
    await db.insert(
      'teams',
      team.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Persist any squad players passed on the TeamProfile
    for (final p in team.squad) {
      await db.insert(
        'players',
        p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await refreshDirectory();
  }

  Future<PlayerProfile> addPlayerToClub({
    required String teamId,
    required String displayName,
    String role = '',
    String? designation,
    String? userId,
    String memberRole = 'player',
  }) async {
    final db = await database;
    final now = DateTime.now();
    final uid = signedInUserId;
    final cleanName = displayName.trim();
    if (designation != null && designation.isNotEmpty) {
      await _clearDesignationForTeam(db, teamId, designation);
    }
    final player = PlayerProfile(
      id: LocalEventStore._uuid.v4(),
      teamId: teamId,
      ownerId: uid,
      userId: userId,
      displayName: cleanName,
      role: role,
      designation: designation,
      memberRole: memberRole,
      claimedAt: userId != null ? now : null,
      archived: false,
      synced: false,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert(
      'players',
      player.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await refreshDirectory();
    if (isSignedInAccount) {
      await syncPlayerToSupabase(player.id);
    }
    return player;
  }

  Future<void> savePlayer(PlayerProfile player) async {
    final db = await database;
    if (player.designation != null &&
        player.designation!.isNotEmpty &&
        !player.archived) {
      await _clearDesignationForTeam(
        db,
        player.teamId,
        player.designation!,
        exceptPlayerId: player.id,
      );
    }
    await db.insert(
      'players',
      player.copyWith(synced: false, updatedAt: DateTime.now()).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await refreshDirectory();
    if (isSignedInAccount) {
      await syncPlayerToSupabase(player.id);
    }
  }

  /// Renames an unlinked player in a single normalized row — automatically
  /// updates their name across every past scorecard, dismissal, and stat!
  Future<PlayerProfile?> renamePlayer(
    String playerId,
    String newDisplayName,
  ) async {
    final clean = newDisplayName.trim();
    if (clean.isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'players',
      where: 'id = ?',
      whereArgs: [playerId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final current = PlayerProfile.fromMap(rows.first);
    if (current.isLinked) return current;
    final updated = current.copyWith(
      displayName: clean,
      synced: false,
      updatedAt: DateTime.now(),
    );
    await db.update(
      'players',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [playerId],
    );
    await refreshDirectory();
    if (isSignedInAccount) {
      await syncPlayerToSupabase(playerId);
    }
    return updated;
  }

  /// Updates a player's cricket role and C / VC / WK designation (unique per team).
  Future<PlayerProfile?> updatePlayerRole(
    String playerId, {
    required String role,
    String? designation,
  }) async {
    final db = await database;
    final rows = await db.query(
      'players',
      where: 'id = ?',
      whereArgs: [playerId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final current = PlayerProfile.fromMap(rows.first);
    final cleanDes =
        (designation != null && designation.trim().isNotEmpty)
            ? designation.trim()
            : null;
    if (cleanDes != null) {
      await _clearDesignationForTeam(
        db,
        current.teamId,
        cleanDes,
        exceptPlayerId: playerId,
      );
    }
    final updated = current.copyWith(
      role: role,
      designation: cleanDes,
      clearDesignation: cleanDes == null,
      synced: false,
      updatedAt: DateTime.now(),
    );
    await db.update(
      'players',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [playerId],
    );
    await refreshDirectory();
    if (isSignedInAccount) {
      // Sync cleared players on this team in the background so local save
      // stays instant even on slow or offline ground networks.
      unawaited(
        syncTeamToSupabase(current.teamId).then((_) {}, onError: (_) {}),
      );
    }
    return updated;
  }

  /// Soft-archives a player from the active squad so past scorecards continue
  /// resolving their display name cleanly.
  Future<void> archivePlayer(String playerId) async {
    final db = await database;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'players',
      {
        'archived': 1,
        'designation': null,
        'synced': 0,
        'updated_at': nowMs,
      },
      where: 'id = ?',
      whereArgs: [playerId],
    );
    await refreshDirectory();
    if (isSignedInAccount) {
      await syncPlayerToSupabase(playerId);
    }
  }

  Future<void> _clearDesignationForTeam(
    Database db,
    String teamId,
    String designation, {
    String? exceptPlayerId,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (exceptPlayerId != null) {
      await db.update(
        'players',
        {'designation': null, 'synced': 0, 'updated_at': nowMs},
        where: 'team_id = ? AND designation = ? AND id != ? AND archived = 0',
        whereArgs: [teamId, designation, exceptPlayerId],
      );
    } else {
      await db.update(
        'players',
        {'designation': null, 'synced': 0, 'updated_at': nowMs},
        where: 'team_id = ? AND designation = ? AND archived = 0',
        whereArgs: [teamId, designation],
      );
    }
  }

  Future<void> deleteTeam(String teamId) async {
    final db = await database;
    await db.delete('players', where: 'team_id = ?', whereArgs: [teamId]);
    await db.delete('teams', where: 'id = ?', whereArgs: [teamId]);
    await refreshDirectory();
    try {
      final client = Supabase.instance.client;
      if (isSignedInAccount) {
        await client.from('teams').delete().eq('id', teamId);
      }
    } catch (_) {}
  }

  Future<void> leaveTeam(String teamId) async {
    final db = await database;
    final uid = signedInUserId;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    String? selfPlayerName;
    if (uid != null) {
      final claimedRows = await db.query(
        'players',
        columns: ['display_name'],
        where: 'team_id = ? AND user_id = ?',
        whereArgs: [teamId, uid],
        limit: 1,
      );
      if (claimedRows.isNotEmpty) {
        selfPlayerName = claimedRows.first['display_name'] as String?;
      }
    }

    if (isSignedInAccount && uid != null) {
      await Supabase.instance.client
          .from('players')
          .update({
            'user_id': null,
            'claimed_at': null,
            'avatar_url': null,
            'updated_at': nowMs,
          })
          .eq('team_id', teamId)
          .eq('user_id', uid);
    }

    await db.delete('players', where: 'team_id = ?', whereArgs: [teamId]);
    await db.delete('teams', where: 'id = ?', whereArgs: [teamId]);

    // Remove local matches that were only pulled via this team (not scored by
    // the user, no unsynced balls, and not tied to another saved team/tournament).
    final matchRows = await db.query(
      'matches',
      columns: ['id', 'team_a_id', 'team_b_id', 'tournament_id', 'synced'],
      where: '(team_a_id = ? OR team_b_id = ?) AND is_demo = 0',
      whereArgs: [teamId, teamId],
    );
    if (matchRows.isNotEmpty) {
      final remainingTeams = (await db.query('teams', columns: ['id']))
          .map((r) => r['id'] as String)
          .toSet();
      final localTournaments =
          (await db.query('tournaments', columns: ['id']))
              .map((r) => r['id'] as String)
              .toSet();

      final candidates = <String>[];
      for (final row in matchRows) {
        final mid = row['id'] as String;
        if ((row['synced'] as int? ?? 0) != 1) continue;
        final aId = row['team_a_id'] as String?;
        final bId = row['team_b_id'] as String?;
        if ((aId != null && remainingTeams.contains(aId)) ||
            (bId != null && remainingTeams.contains(bId))) {
          continue;
        }
        final tId = row['tournament_id'] as String?;
        if (tId != null && localTournaments.contains(tId)) continue;
        final unsyncedBalls = await db.query(
          'ball_events',
          columns: ['id'],
          where: 'match_id = ? AND synced = 0',
          whereArgs: [mid],
          limit: 1,
        );
        if (unsyncedBalls.isNotEmpty) continue;
        candidates.add(mid);
      }

      if (candidates.isNotEmpty) {
        final ownedByMe = <String>{};
        if (isSignedInAccount && uid != null) {
          try {
            final remote = await Supabase.instance.client
                .from('matches')
                .select('id, owner_id')
                .inFilter('id', candidates);
            for (final r in (remote as List)) {
              final map = r as Map;
              if (map['owner_id'] == uid && map['id'] is String) {
                ownedByMe.add(map['id'] as String);
              }
            }
          } catch (_) {
            // If check fails, keep matches rather than risking data loss.
            ownedByMe.addAll(candidates);
          }
        }
        for (final mid in candidates) {
          if (ownedByMe.contains(mid)) continue;
          await db.delete('ball_events', where: 'match_id = ?', whereArgs: [mid]);
          await db.delete('matches', where: 'id = ?', whereArgs: [mid]);
        }
      }
    }

    await refreshDirectory();

    if (selfPlayerName != null && selfPlayerName.trim().isNotEmpty) {
      final profile = await getUserProfile();
      if (profile.linkedPlayerName != null &&
          profile.linkedPlayerName!.trim().toLowerCase() ==
              selfPlayerName.trim().toLowerCase()) {
        await saveUserProfile(
          profile.copyWith(clearLinkedPlayer: true),
          syncToCloud: true,
        );
      }
    }
  }

  Future<void> syncTeamToSupabase(String teamId) async {
    try {
      final uid = signedInUserId;
      if (uid == null) return;
      final db = await database;
      final rows = await db.query(
        'teams',
        where: 'id = ?',
        whereArgs: [teamId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final team = TeamProfile.fromMap(rows.first);
      if (!team.isOwner) return;

      final client = Supabase.instance.client;
      final upserted = await client
          .from('teams')
          .upsert(
            {
              'id': team.id,
              'owner_id': uid,
              'name': team.name,
              'location': team.location,
              'logo_url': team.logoUrl,
              if (team.profileCode != null && team.profileCode!.isNotEmpty)
                'profile_code': team.profileCode,
              'is_my_team': team.isMyTeam,
              'created_at': team.createdAt.millisecondsSinceEpoch,
            },
            onConflict: 'id',
          )
          .select('profile_code')
          .maybeSingle();

      final assignedCode = (upserted?['profile_code'] as String?)?.trim();
      await db.update(
        'teams',
        {
          'synced': 1,
          if (assignedCode != null && assignedCode.isNotEmpty)
            'profile_code': assignedCode.toUpperCase(),
        },
        where: 'id = ?',
        whereArgs: [teamId],
      );

      // Sync all players for this team (cleared designations first to avoid unique conflict)
      final playerRows = await db.query(
        'players',
        where: 'team_id = ?',
        whereArgs: [teamId],
        orderBy: 'created_at ASC',
      );
      final players = playerRows.map(PlayerProfile.fromMap).toList();
      final clearedFirst = [
        ...players.where((p) => p.designation == null || p.archived),
        ...players.where((p) => p.designation != null && !p.archived),
      ];
      for (final p in clearedFirst) {
        await _upsertSinglePlayerToSupabase(client, db, uid, p);
      }
      await refreshDirectory();
    } catch (e) {
      if (kDebugMode) debugPrint('syncTeamToSupabase skipped: $e');
    }
  }

  Future<void> syncPlayerToSupabase(String playerId) async {
    try {
      final uid = signedInUserId;
      if (uid == null) return;
      final db = await database;
      final rows = await db.query(
        'players',
        where: 'id = ?',
        whereArgs: [playerId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final player = PlayerProfile.fromMap(rows.first);
      // Ensure parent team is synced first
      final teamRows = await db.query(
        'teams',
        where: 'id = ?',
        whereArgs: [player.teamId],
        limit: 1,
      );
      if (teamRows.isNotEmpty && ((teamRows.first['synced'] as num?) ?? 0) == 0) {
        await syncTeamToSupabase(player.teamId);
        return;
      }
      await _upsertSinglePlayerToSupabase(
        Supabase.instance.client,
        db,
        uid,
        player,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('syncPlayerToSupabase skipped: $e');
    }
  }

  Future<void> _upsertSinglePlayerToSupabase(
    SupabaseClient client,
    Database db,
    String uid,
    PlayerProfile p,
  ) async {
    await client.from('players').upsert(
      {
        'id': p.id,
        'team_id': p.teamId,
        'owner_id': p.ownerId ?? uid,
        'user_id': p.userId,
        'display_name': p.displayName,
        'role': p.role,
        'designation': p.archived ? null : p.designation,
        'member_role': p.memberRole,
        'avatar_url': p.avatarUrl,
        'claimed_at': p.claimedAt?.millisecondsSinceEpoch,
        'archived': p.archived,
        'created_at': p.createdAt.millisecondsSinceEpoch,
        'updated_at': p.updatedAt.millisecondsSinceEpoch,
      },
      onConflict: 'id',
    );
    await db.update(
      'players',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [p.id],
    );
  }

  // ── Team Invites & Player Claiming ────────────────────────────────────────

  Future<String> createTeamInviteCode(String teamId) async {
    requireSignedInUserId();
    await syncTeamToSupabase(teamId);
    final result = await Supabase.instance.client.rpc(
      'create_team_invite_code',
      params: {'p_team_id': teamId},
    );
    return result.toString();
  }

  Future<String> resetTeamInviteCode(String teamId) async {
    requireSignedInUserId();
    final result = await Supabase.instance.client.rpc(
      'reset_team_invite_code',
      params: {'p_team_id': teamId},
    );
    return result.toString();
  }

  Future<TeamInvitePreview> previewTeamByCode(String joinCode) async {
    requireSignedInUserId();
    final raw = await Supabase.instance.client.rpc(
      'preview_team_by_code',
      params: {'p_join_code': joinCode.trim()},
    );
    final map = Map<String, dynamic>.from(raw as Map);
    if (map['ok'] != true) {
      throw CreaseRpcException(
        (map['error'] as String?) ?? 'invalid_code',
        retryAfterSeconds: (map['retry_after_seconds'] as num?)?.toInt(),
      );
    }
    final teamId = map['team_id'] as String;
    final rawPlayers = (map['players'] as List?) ?? const [];
    final players = <PlayerProfile>[];
    for (final item in rawPlayers) {
      if (item is Map) {
        final pm = Map<String, Object?>.from(item);
        pm['team_id'] ??= teamId;
        players.add(PlayerProfile.fromMap(pm));
      }
    }
    return TeamInvitePreview(
      teamId: teamId,
      teamName: map['team_name'] as String,
      players: players,
      myClaimedPlayerId: map['my_claimed_player_id'] as String?,
    );
  }

  Future<({String teamId, String teamName, String playerId, String displayName})>
      claimTeamPlayer(
    String joinCode, {
    String? playerId,
    String? displayName,
  }) async {
    requireSignedInUserId();
    final raw = await Supabase.instance.client.rpc(
      'claim_team_player',
      params: {
        'p_join_code': joinCode.trim(),
        'p_player_id': playerId,
        'p_display_name': displayName?.trim(),
      },
    );
    final map = Map<String, dynamic>.from(raw as Map);
    if (map['ok'] != true) {
      throw CreaseRpcException(
        (map['error'] as String?) ?? 'unknown',
        retryAfterSeconds: (map['retry_after_seconds'] as num?)?.toInt(),
      );
    }
    final teamId = map['team_id'] as String;
    final teamName = map['team_name'] as String;
    final claimedId = map['player_id'] as String;
    final claimedName = map['display_name'] as String;

    // Fetch full team & squad locally so it appears in Teams tab immediately
    final teamProfile = await fetchPublicTeamProfile(teamId);
    if (teamProfile != null) {
      final uid = signedInUserId;
      final isOwner = teamProfile.squad.any((p) => p.ownerId == uid) ||
          teamProfile.isOwner;
      await saveTeam(
        teamProfile.copyWith(
          isMyTeam: true,
          isOwner: isOwner,
          synced: true,
        ),
      );
    }

    // Update user profile linked player name
    final profile = await getUserProfile();
    await saveUserProfile(
      profile.copyWith(
        displayName:
            profile.displayName.trim().isEmpty ? claimedName : profile.displayName,
        linkedPlayerName: claimedName,
      ),
      syncToCloud: true,
    );

    await pullMatchesForTeam(teamId, teamName: teamName);
    return (
      teamId: teamId,
      teamName: teamName,
      playerId: claimedId,
      displayName: claimedName,
    );
  }

  Future<void> unlinkTeamPlayer(String playerId) async {
    final db = await database;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.query(
      'players',
      columns: ['user_id', 'display_name'],
      where: 'id = ?',
      whereArgs: [playerId],
      limit: 1,
    );
    final prevUserId = rows.isNotEmpty ? rows.first['user_id'] as String? : null;
    final prevName =
        rows.isNotEmpty ? (rows.first['display_name'] as String?) ?? '' : '';
    final uid = signedInUserId;

    if (isSignedInAccount) {
      await Supabase.instance.client
          .from('players')
          .update({
            'user_id': null,
            'claimed_at': null,
            'avatar_url': null,
            'updated_at': nowMs,
          })
          .eq('id', playerId);
    }

    await db.update(
      'players',
      {
        'user_id': null,
        'claimed_at': null,
        'avatar_url': null,
        'synced': isSignedInAccount ? 1 : 0,
        'updated_at': nowMs,
      },
      where: 'id = ?',
      whereArgs: [playerId],
    );
    await refreshDirectory();

    // If the signed-in user just unlinked their own spot, clear matching linkedPlayerName
    if (uid != null && prevUserId == uid) {
      final profile = await getUserProfile();
      if (profile.linkedPlayerName != null &&
          profile.linkedPlayerName!.trim().toLowerCase() ==
              prevName.trim().toLowerCase()) {
        await saveUserProfile(
          profile.copyWith(clearLinkedPlayer: true),
          syncToCloud: true,
        );
      }
    }
  }

  /// Claims [targetPlayerId] for the current signed-in user (or unlinks all
  /// self-claimed spots when [targetPlayerId] is null), awaiting Supabase
  /// confirmation so shared ownership stays consistent with the server.
  Future<void> syncSelfPlayerLink(
    String? targetPlayerId, {
    String? avatarUrl,
  }) async {
    final uid = signedInUserId;
    if (uid == null) return;
    final db = await database;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    if (targetPlayerId != null && targetPlayerId.isNotEmpty) {
      final rows = await db.query(
        'players',
        columns: ['user_id'],
        where: 'id = ?',
        whereArgs: [targetPlayerId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final currentClaimer = rows.first['user_id'] as String?;
      if (currentClaimer != null &&
          currentClaimer.isNotEmpty &&
          currentClaimer != uid) {
        throw StateError('That player spot is already claimed by another account.');
      }

      final cleanAvatar = (avatarUrl != null && avatarUrl.trim().isNotEmpty)
          ? avatarUrl.trim()
          : null;

      if (isSignedInAccount) {
        if (!CreaseSecurity.isValidUuid(uid)) {
          throw StateError('Invalid user session.');
        }
        final updatedRows = await Supabase.instance.client
            .from('players')
            .update({
              'user_id': uid,
              'claimed_at': nowMs,
              'avatar_url': cleanAvatar,
              'updated_at': nowMs,
            })
            .eq('id', targetPlayerId)
            .or('user_id.is.null,user_id.eq.$uid')
            .select('id');
        if (updatedRows.isEmpty) {
          throw StateError(
            'That player spot is already claimed by another account.',
          );
        }
      }

      await db.update(
        'players',
        {
          'user_id': uid,
          'claimed_at': nowMs,
          'avatar_url': cleanAvatar,
          'synced': isSignedInAccount ? 1 : 0,
          'updated_at': nowMs,
        },
        where: 'id = ?',
        whereArgs: [targetPlayerId],
      );
    }

    final existing = await db.query(
      'players',
      columns: ['id'],
      where: 'user_id = ? AND archived = 0',
      whereArgs: [uid],
    );
    for (final row in existing) {
      final oldId = row['id'] as String?;
      if (oldId != null && oldId != targetPlayerId) {
        await unlinkTeamPlayer(oldId);
      }
    }

    await refreshDirectory();
  }

  // ── Public Discovery (Teams & Players) ────────────────────────────────────

  Future<
      ({
        String id,
        String name,
        String? location,
        String profileCode,
        String? logoUrl,
        List<PlayerProfile> squad,
      })?> lookupTeamByProfileCode(String code) async {
    final normalized = code.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (normalized.length < 4) return null;
    try {
      final rows = await Supabase.instance.client.rpc(
        'lookup_team_by_profile_code',
        params: {'p_code': code.trim()},
      );
      if (rows is! List || rows.isEmpty) return null;
      final map = rows.first as Map;
      final id = (map['id'] as String?) ?? '';
      final name = (map['name'] as String?)?.trim() ?? '';
      final profileCode = (map['profile_code'] as String?)?.trim() ?? '';
      if (id.isEmpty || name.isEmpty || profileCode.isEmpty) return null;
      final rawLoc = (map['location'] as String?)?.trim();
      final location = (rawLoc != null && rawLoc.isNotEmpty) ? rawLoc : null;
      final rawLogo = (map['logo_url'] as String?)?.trim();
      final logoUrl = (rawLogo != null && rawLogo.isNotEmpty) ? rawLogo : null;
      final squad = _decodeRpcPlayers(map['players'], teamId: id);
      return (
        id: id,
        name: name,
        location: location,
        profileCode: profileCode.toUpperCase(),
        logoUrl: logoUrl,
        squad: squad,
      );
    } catch (_) {
      return null;
    }
  }

  Future<
      List<
          ({
            String id,
            String name,
            String? location,
            String? profileCode,
            String? logoUrl,
            List<PlayerProfile> squad,
          })>> searchPublicTeams(
    String query, {
    int limit = 15,
    Set<String> excludeIds = const {},
    bool dedupeByName = true,
  }) async {
    final clean = query.trim();
    if (clean.length < 2) return const [];
    try {
      final rows = await Supabase.instance.client.rpc(
        'search_public_teams',
        params: {'p_query': clean, 'p_limit': limit},
      );
      final results = <({
        String id,
        String name,
        String? location,
        String? profileCode,
        String? logoUrl,
        List<PlayerProfile> squad,
      })>[];
      final seenLower = <String>{};
      for (final raw in (rows as List)) {
        final map = raw as Map;
        final id = (map['id'] as String?) ?? '';
        final name = (map['name'] as String?)?.trim() ?? '';
        if (id.isEmpty || name.isEmpty || excludeIds.contains(id)) continue;
        if (dedupeByName && !seenLower.add(name.toLowerCase())) continue;
        final rawLoc = (map['location'] as String?)?.trim();
        final rawCode = (map['profile_code'] as String?)?.trim();
        final rawLogo = (map['logo_url'] as String?)?.trim();
        results.add((
          id: id,
          name: name,
          location: (rawLoc != null && rawLoc.isNotEmpty) ? rawLoc : null,
          profileCode:
              (rawCode != null && rawCode.isNotEmpty) ? rawCode.toUpperCase() : null,
          logoUrl: (rawLogo != null && rawLogo.isNotEmpty) ? rawLogo : null,
          squad: _decodeRpcPlayers(map['players'], teamId: id),
        ));
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  Future<TeamProfile?> fetchPublicTeamProfile(String teamId) async {
    try {
      final client = Supabase.instance.client;
      final row = await client
          .from('teams')
          .select(LocalEventStore._teamSelectCols)
          .eq('id', teamId)
          .maybeSingle();
      if (row == null) return null;
      final playerRows = await client
          .from('players')
          .select(LocalEventStore._playerSelectCols)
          .eq('team_id', teamId)
          .eq('archived', false)
          .order('created_at', ascending: true);
      final squad = (playerRows as List)
          .map((r) => PlayerProfile.fromMap(Map<String, Object?>.from(r as Map)))
          .toList();
      final uid = signedInUserId;
      final map = Map<String, Object?>.from(row);
      map['is_owner'] = uid != null && map['owner_id'] == uid;
      return TeamProfile.fromMap(map, squad: squad);
    } catch (_) {
      return null;
    }
  }

  Future<
      List<
          ({
            String playerId,
            String playerName,
            String role,
            String? avatarUrl,
            String teamId,
            String teamName,
            String? teamLocation,
          })>> searchPublicPlayers(
    String query, {
    int limit = 12,
    Set<String> excludeTeamIds = const {},
  }) async {
    final clean = query.trim();
    if (clean.length < 2) return const [];
    try {
      final rows = await Supabase.instance.client.rpc(
        'search_public_players',
        params: {'p_query': clean, 'p_limit': limit},
      );
      final out = <({
        String playerId,
        String playerName,
        String role,
        String? avatarUrl,
        String teamId,
        String teamName,
        String? teamLocation,
      })>[];
      if (rows is List) {
        for (final raw in rows) {
          final m = raw as Map;
          final playerId = (m['player_id'] as String?) ?? '';
          final playerName = (m['display_name'] as String?)?.trim() ?? '';
          final teamId = (m['team_id'] as String?) ?? '';
          final teamName = (m['team_name'] as String?)?.trim() ?? '';
          if (playerId.isEmpty ||
              playerName.isEmpty ||
              teamId.isEmpty ||
              excludeTeamIds.contains(teamId)) {
            continue;
          }
          final rawLoc = (m['team_location'] as String?)?.trim();
          final rawAvatar = (m['avatar_url'] as String?)?.trim();
          out.add((
            playerId: playerId,
            playerName: playerName,
            role: (m['role'] as String?) ?? '',
            avatarUrl:
                (rawAvatar != null && rawAvatar.isNotEmpty) ? rawAvatar : null,
            teamId: teamId,
            teamName: teamName,
            teamLocation:
                (rawLoc != null && rawLoc.isNotEmpty) ? rawLoc : null,
          ));
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<String?> fetchPublicPlayerAvatar(String playerId) async {
    final local = directory.playersById[playerId]?.avatarUrl;
    if (local != null && local.isNotEmpty) return local;
    try {
      final row = await Supabase.instance.client
          .from('players')
          .select('avatar_url')
          .eq('id', playerId)
          .maybeSingle();
      final url = (row?['avatar_url'] as String?)?.trim();
      return (url != null && url.isNotEmpty) ? url : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, List<String>>> listKnownTeamRosters() async {
    final teams = await listTeams();
    return {
      for (final t in teams) t.name: t.players,
    };
  }

  List<PlayerProfile> _decodeRpcPlayers(
    Object? raw, {
    required String teamId,
  }) {
    if (raw is! List) return const [];
    final out = <PlayerProfile>[];
    for (final item in raw) {
      if (item is Map) {
        final pm = Map<String, Object?>.from(item);
        pm['team_id'] ??= teamId;
        final p = PlayerProfile.fromMap(pm);
        if (!isPlaceholderPlayerName(p.displayName)) {
          out.add(p);
        }
      }
    }
    return out;
  }
}
