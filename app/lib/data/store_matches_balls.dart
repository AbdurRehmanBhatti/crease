part of 'local_event_store.dart';

extension LocalEventStoreMatchesBalls on LocalEventStore {
  // ── Matches & Ball Events CRUD ────────────────────────────────────────────

  Future<List<MatchConfig>> listMatches() async {
    final db = await database;
    final rows = await db.query('matches', orderBy: 'created_at DESC');
    return rows.map(MatchConfig.fromMap).toList();
  }

  Future<List<MatchConfig>> listMatchesForTournament(
    String tournamentId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'matches',
      where: 'tournament_id = ?',
      whereArgs: [tournamentId],
      orderBy: 'created_at ASC',
    );
    return rows.map(MatchConfig.fromMap).toList();
  }

  Future<MatchConfig?> getMatch(String matchId) async {
    final db = await database;
    final rows = await db.query(
      'matches',
      where: 'id = ?',
      whereArgs: [matchId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MatchConfig.fromMap(rows.first);
  }

  Future<void> saveMatch(MatchConfig config) async {
    final db = await database;
    final map = Map<String, Object?>.from(config.toMap());
    map['synced'] = 0;
    await db.insert(
      'matches',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Adds a new player mid-match.
  /// - If [addToOwnedSquad] is true and the team is owned locally, creates a
  ///   real `players` row and attaches its UUID to the match roster.
  /// - Otherwise (e.g. opposition sub or quick ad-hoc match), adds a UUID to
  ///   `match.adHocPlayers` without mutating any club's `public.players`.
  Future<({MatchConfig config, String playerId})?> addPlayerToMatchSide(
    String matchId, {
    required MatchSide side,
    required String playerName,
    bool addToOwnedSquad = false,
  }) async {
    final clean = playerName.trim();
    if (clean.isEmpty) return null;
    final existing = await getMatch(matchId);
    if (existing == null) return null;

    final teamId = existing.teamIdForSide(side);
    String? resolvedId;

    if (teamId != null && teamId.isNotEmpty) {
      final team = await getTeam(teamId);
      final existingPlayer = team?.playerByName(clean);
      if (existingPlayer != null) {
        resolvedId = existingPlayer.id;
      } else if (addToOwnedSquad && team != null && team.isOwner) {
        final created = await addPlayerToClub(
          teamId: team.id,
          displayName: clean,
        );
        resolvedId = created.id;
      }
    }

    MatchConfig updated;
    if (resolvedId != null) {
      final nextA = side == MatchSide.a &&
              !existing.teamAPlayerIds.contains(resolvedId)
          ? [...existing.teamAPlayerIds, resolvedId]
          : existing.teamAPlayerIds;
      final nextB = side == MatchSide.b &&
              !existing.teamBPlayerIds.contains(resolvedId)
          ? [...existing.teamBPlayerIds, resolvedId]
          : existing.teamBPlayerIds;
      updated = existing.copyWith(
        teamAPlayerIds: nextA,
        teamBPlayerIds: nextB,
      );
    } else {
      final res = existing.ensureAdHocPlayer(
        clean,
        LocalEventStore._uuid.v4,
        addToSide: side,
      );
      updated = res.config;
      resolvedId = res.playerId;
    }

    await saveMatch(updated);
    return (config: updated, playerId: resolvedId);
  }

  Future<void> deleteMatch(String matchId) async {
    final db = await database;
    await db.delete('ball_events', where: 'match_id = ?', whereArgs: [matchId]);
    await db.delete('matches', where: 'id = ?', whereArgs: [matchId]);
    try {
      if (isSignedInAccount) {
        await Supabase.instance.client
            .from('matches')
            .delete()
            .eq('id', matchId);
      }
    } catch (_) {}
  }

  Future<List<BallEvent>> getBallEvents(String matchId) async {
    final db = await database;
    final rows = await db.query(
      'ball_events',
      where: 'match_id = ?',
      whereArgs: [matchId],
      orderBy: 'innings_number ASC, sequence_number ASC',
    );
    return rows.map(BallEvent.fromMap).toList();
  }

  Future<void> appendBallEvent(BallEvent event) async {
    final db = await database;
    await db.insert(
      'ball_events',
      event.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> appendBallEventsBatch(List<BallEvent> events) async {
    final db = await database;
    final batch = db.batch();
    for (final e in events) {
      batch.insert(
        'ball_events',
        e.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateBallEvent(BallEvent event) async {
    final db = await database;
    await db.update(
      'ball_events',
      event.copyWith(synced: false).toMap(),
      where: 'id = ?',
      whereArgs: [event.id],
    );
  }

  Future<BallEvent?> undoLastBall(String matchId, int inningsNumber) async {
    final db = await database;
    final rows = await db.query(
      'ball_events',
      where: 'match_id = ? AND innings_number = ? AND voided = 0',
      whereArgs: [matchId, inningsNumber],
      orderBy: 'sequence_number DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final last = BallEvent.fromMap(rows.first);
    await db.update(
      'ball_events',
      {'voided': 1, 'synced': 0},
      where: 'id = ?',
      whereArgs: [last.id],
    );
    return last;
  }

  Future<void> voidBallById(String ballId) async {
    final db = await database;
    await db.update(
      'ball_events',
      {'voided': 1, 'synced': 0},
      where: 'id = ?',
      whereArgs: [ballId],
    );
  }

  // ── Remote Match Bundle (Single Round-Trip RPC) & Sync ────────────────────

  Future<
      ({
        MatchConfig config,
        List<BallEvent> events,
        Map<String, String> playerNamesById,
        Map<String, String> teamNamesById,
      })?> fetchRemoteMatch(String matchId) async {
    try {
      final raw = await Supabase.instance.client.rpc(
        'get_live_match_bundle',
        params: {'p_match_id': matchId},
      );
      if (raw == null || raw is! Map) return null;
      final bundle = Map<String, dynamic>.from(raw);
      final matchRaw = bundle['match'];
      if (matchRaw is! Map) return null;

      final config = MatchConfig.fromMap(Map<String, Object?>.from(matchRaw));
      final rawTeams = (bundle['teams'] as List?) ?? const [];
      final teamNames = <String, String>{};
      for (final t in rawTeams) {
        if (t is Map) {
          final id = (t['id'] as String?) ?? '';
          final name = (t['name'] as String?) ?? '';
          if (id.isNotEmpty && name.isNotEmpty) teamNames[id] = name;
        }
      }

      final rawPlayers = (bundle['players'] as List?) ?? const [];
      final playerNames = <String, String>{...config.adHocPlayers};
      for (final p in rawPlayers) {
        if (p is Map) {
          final id = (p['id'] as String?) ?? '';
          final name = (p['display_name'] as String?) ?? '';
          if (id.isNotEmpty && name.isNotEmpty) playerNames[id] = name;
        }
      }

      final rawEvents = (bundle['events'] as List?) ?? const [];
      final events = rawEvents
          .whereType<Map>()
          .map(
            (r) => BallEvent.fromMap(Map<String, Object?>.from(r))
                .copyWith(synced: true),
          )
          .toList();

      return (
        config: config,
        events: events,
        playerNamesById: playerNames,
        teamNamesById: teamNames,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('fetchRemoteMatch error: $e');
      return null;
    }
  }

  /// Merges a remote `matches` row into a [MatchConfig], preserving local
  /// `visibility` and `venue` if an older server payload omits those keys.
  static MatchConfig mergeRemoteMatchConfig(
    Map<String, Object?> matchRawMap, {
    MatchConfig? existingLocal,
  }) {
    var config = MatchConfig.fromMap(matchRawMap);
    if (existingLocal != null) {
      if (!matchRawMap.containsKey('visibility')) {
        config = config.copyWith(visibility: existingLocal.visibility);
      }
      if (!matchRawMap.containsKey('venue') && existingLocal.venue != null) {
        config = config.copyWith(venue: existingLocal.venue);
      }
    }
    return config;
  }

  Future<bool> pullRemoteMatchToLocal(String matchId) async {
    try {
      final raw = await Supabase.instance.client.rpc(
        'get_live_match_bundle',
        params: {'p_match_id': matchId},
      );
      if (raw == null || raw is! Map) return false;
      final bundle = Map<String, dynamic>.from(raw);
      final matchRaw = bundle['match'];
      if (matchRaw is! Map) return false;

      final db = await database;
      final existingLocal = await getMatch(matchId);
      final config = mergeRemoteMatchConfig(
        Map<String, Object?>.from(matchRaw),
        existingLocal: existingLocal,
      );
      final matchMap = Map<String, Object?>.from(config.toMap());
      matchMap['synced'] = 1;
      await db.insert(
        'matches',
        matchMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Cache remote players locally so scorecards resolve names offline too
      final rawPlayers = (bundle['players'] as List?) ?? const [];
      final batch = db.batch();
      for (final p in rawPlayers) {
        if (p is Map) {
          final pm = Map<String, Object?>.from(p);
          final prof = PlayerProfile.fromMap(pm).copyWith(synced: true);
          // Only insert player if its parent team exists locally (avoid FK violation)
          final hasTeam = (await db.query(
            'teams',
            columns: ['id'],
            where: 'id = ?',
            whereArgs: [prof.teamId],
            limit: 1,
          ))
              .isNotEmpty;
          if (hasTeam) {
            batch.insert(
              'players',
              prof.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }

      final rawEvents = (bundle['events'] as List?) ?? const [];
      for (final r in rawEvents) {
        if (r is Map) {
          final ev = BallEvent.fromMap(Map<String, Object?>.from(r))
              .copyWith(synced: true);
          batch.insert(
            'ball_events',
            ev.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await batch.commit(noResult: true);
      await refreshDirectory();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureMatchSyncedToSupabase(String matchId) async {
    final uid = signedInUserId;
    if (uid == null) return;
    final match = await getMatch(matchId);
    if (match == null || match.isDemo) return;

    final client = Supabase.instance.client;
    if (match.tournamentId != null && match.tournamentId!.isNotEmpty) {
      await syncTournamentToSupabase(match.tournamentId!);
    }
    if (match.teamAId != null && match.teamAId!.isNotEmpty) {
      await syncTeamToSupabase(match.teamAId!);
    }
    if (match.teamBId != null && match.teamBId!.isNotEmpty) {
      await syncTeamToSupabase(match.teamBId!);
    }

    final existingMatch = await client
        .from('matches')
        .select('id, owner_id')
        .eq('id', match.id)
        .maybeSingle();

    final sharedFields = <String, Object?>{
      'team_a_id': match.teamAId,
      'team_b_id': match.teamBId,
      'team_a': match.teamA,
      'team_b': match.teamB,
      'batting_first_side': match.battingFirstSide.name,
      'overs_limit': match.oversLimit,
      'players_per_side': match.playersPerSide,
      'format_label': match.formatLabel,
      'opening_striker_1_id': match.openingStriker1Id,
      'opening_non_striker_1_id': match.openingNonStriker1Id,
      'opening_bowler_1_id': match.openingBowler1Id,
      'opening_striker_2_id': match.openingStriker2Id,
      'opening_non_striker_2_id': match.openingNonStriker2Id,
      'opening_bowler_2_id': match.openingBowler2Id,
      'team_a_player_ids': match.teamAPlayerIds,
      'team_b_player_ids': match.teamBPlayerIds,
      'ad_hoc_players': match.adHocPlayers,
      'tournament_stage': match.tournamentStage,
      'fixture_index': match.fixtureIndex,
      'is_test_match': match.isTestMatch,
      'declared_innings': match.declaredInnings,
      'follow_on_enforced': match.followOnEnforced,
      'first_innings_target_override': match.firstInningsTargetOverride,
      'visibility': match.visibility.name,
      'venue': match.venue,
    };

    if (existingMatch == null) {
      await client.from('matches').insert({
        'id': match.id,
        'owner_id': uid,
        'tournament_id': match.tournamentId,
        'is_demo': match.isDemo,
        'created_at': match.createdAt.millisecondsSinceEpoch,
        ...sharedFields,
      });
    } else {
      final isOwner = existingMatch['owner_id'] == uid;
      await client.from('matches').update({
        ...sharedFields,
        if (isOwner) 'tournament_id': match.tournamentId,
        if (isOwner) 'is_demo': match.isDemo,
      }).eq('id', match.id);
    }

    final db = await database;
    await db.update(
      'matches',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [matchId],
    );
    await syncMatchLiveSummary(matchId, config: match);
  }

  Future<int> syncPendingToSupabase(String matchId) async {
    try {
      final uid = signedInUserId;
      if (uid == null) return 0;
      final match = await getMatch(matchId);
      if (match == null || match.isDemo) return 0;

      await ensureMatchSyncedToSupabase(matchId);

      final db = await database;
      final unsyncedRows = await db.query(
        'ball_events',
        where: 'match_id = ? AND synced = 0',
        whereArgs: [matchId],
        orderBy: 'innings_number ASC, sequence_number ASC',
      );
      if (unsyncedRows.isEmpty) return 0;

      final events = unsyncedRows.map(BallEvent.fromMap).toList();
      final client = Supabase.instance.client;
      final existingRows = await client
          .from('ball_events')
          .select('id')
          .inFilter('id', [for (final e in events) e.id]);
      final existingIds = <String>{
        for (final r in (existingRows as List)) (r as Map)['id'].toString(),
      };

      final toInsert = <Map<String, Object?>>[];
      final toUpdate = <BallEvent>[];
      for (final e in events) {
        if (existingIds.contains(e.id)) {
          toUpdate.add(e);
        } else {
          toInsert.add({
            'id': e.id,
            'match_id': e.matchId,
            'owner_id': uid,
            'innings_number': e.inningsNumber,
            'sequence_number': e.sequenceNumber,
            'striker_id': e.strikerId,
            'non_striker_id': e.nonStrikerId,
            'bowler_id': e.bowlerId,
            'runs_off_bat': e.runsOffBat,
            'extra_type': e.extraType.name,
            'extra_runs': e.extraRuns,
            'is_wicket': e.isWicket,
            'wicket_type': e.wicketType?.name,
            'dismissed_batter_id': e.dismissedBatterId,
            'fielder_id': e.fielderId,
            'next_batter_id': e.nextBatterId,
            'voided': e.voided,
            'created_at': e.createdAt.millisecondsSinceEpoch,
          });
        }
      }

      if (toInsert.isNotEmpty) {
        await client.from('ball_events').insert(toInsert);
      }
      for (final e in toUpdate) {
        await client.from('ball_events').update({
          'innings_number': e.inningsNumber,
          'sequence_number': e.sequenceNumber,
          'striker_id': e.strikerId,
          'non_striker_id': e.nonStrikerId,
          'bowler_id': e.bowlerId,
          'runs_off_bat': e.runsOffBat,
          'extra_type': e.extraType.name,
          'extra_runs': e.extraRuns,
          'is_wicket': e.isWicket,
          'wicket_type': e.wicketType?.name,
          'dismissed_batter_id': e.dismissedBatterId,
          'fielder_id': e.fielderId,
          'next_batter_id': e.nextBatterId,
          'voided': e.voided,
        }).eq('id', e.id);
      }

      final batch = db.batch();
      for (final e in events) {
        batch.update(
          'ball_events',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [e.id],
        );
      }
      await batch.commit(noResult: true);
      await syncMatchLiveSummary(matchId, config: match);
      return events.length;
    } catch (e) {
      if (kDebugMode) debugPrint('syncPendingToSupabase skipped: $e');
      return 0;
    }
  }

  // ── Scorer Handover ───────────────────────────────────────────────────────

  Future<String> createScorerHandoverCode(String matchId) async {
    requireSignedInUserId();
    await ensureMatchSyncedToSupabase(matchId);
    final result = await Supabase.instance.client.rpc(
      'create_scorer_handover_code',
      params: {'p_match_id': matchId},
    );
    return result.toString();
  }

  Future<String> claimScorerBaton(String joinCode) async {
    requireSignedInUserId();
    final raw = await Supabase.instance.client.rpc(
      'claim_scorer_baton',
      params: {'p_join_code': joinCode.trim()},
    );
    final map = Map<String, dynamic>.from(raw as Map);
    if (map['ok'] != true) {
      throw CreaseRpcException(
        (map['error'] as String?) ?? 'invalid_code',
        retryAfterSeconds: (map['retry_after_seconds'] as num?)?.toInt(),
      );
    }
    final matchId = map['match_id'] as String;
    await pullRemoteMatchToLocal(matchId);
    return matchId;
  }

  Future<void> reclaimScorerBaton(String matchId) async {
    requireSignedInUserId();
    await Supabase.instance.client.rpc(
      'reclaim_scorer_baton',
      params: {'p_match_id': matchId},
    );
    await pullRemoteMatchToLocal(matchId);
  }

  Future<String?> fetchActiveScorerId(String matchId) async {
    try {
      final row = await Supabase.instance.client
          .from('matches')
          .select('active_scorer_id')
          .eq('id', matchId)
          .maybeSingle();
      return row?['active_scorer_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<int> pullMatchesForTeam(String teamId, {String? teamName}) async {
    if (!CreaseSecurity.isValidUuid(teamId)) return 0;
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('matches')
          .select('id')
          .or('team_a_id.eq.$teamId,team_b_id.eq.$teamId')
          .order('created_at', ascending: false)
          .limit(30);
      var pulled = 0;
      for (final raw in (rows as List)) {
        final mid = (raw as Map)['id'] as String?;
        if (mid != null && await pullRemoteMatchToLocal(mid)) {
          pulled++;
        }
      }
      return pulled;
    } catch (_) {
      return 0;
    }
  }

  Future<int> pullLatestForMyTeams() async {
    if (!isSignedInAccount) return 0;
    await pullRostersForLocalTeams();
    final teams = await listTeams();
    var total = 0;
    for (final t in teams.where((t) => t.isMyTeam)) {
      total += await pullMatchesForTeam(t.id, teamName: t.name);
    }
    return total;
  }
}
