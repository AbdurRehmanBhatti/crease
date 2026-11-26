part of 'local_event_store.dart';

extension LocalEventStoreSyncAuth on LocalEventStore {
  // ── Public Match Search ───────────────────────────────────────────────────

  Future<
      List<
          ({
            String id,
            String teamA,
            String teamB,
            String formatLabel,
            DateTime createdAt,
          })>> searchPublicMatches(
    String query, {
    int limit = 10,
    Set<String> excludeIds = const {},
  }) async {
    final clean = query.trim();
    if (clean.length < 2) return const [];
    try {
      final rows = await Supabase.instance.client.rpc(
        'search_public_matches',
        params: {'p_query': clean, 'p_limit': limit},
      );
      final out = <({
        String id,
        String teamA,
        String teamB,
        String formatLabel,
        DateTime createdAt,
      })>[];
      for (final raw in (rows as List)) {
        final m = raw as Map;
        final id = (m['id'] as String?) ?? '';
        if (id.isEmpty || excludeIds.contains(id)) continue;
        out.add((
          id: id,
          teamA: (m['team_a'] as String?) ?? '',
          teamB: (m['team_b'] as String?) ?? '',
          formatLabel: (m['format_label'] as String?) ?? '',
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            ((m['created_at'] as num?) ?? 0).toInt(),
          ),
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  // ── Cloud Restore & Guest Claim ───────────────────────────────────────────

  Future<int> restoreAccountDataFromCloud() async {
    final uid = signedInUserId;
    if (uid == null) return 0;
    final client = Supabase.instance.client;
    final db = await database;
    var restored = 0;

    try {
      // 1. Restore owned teams + teams where user has claimed a player slot
      final ownedTeams = await client
          .from('teams')
          .select(LocalEventStore._teamSelectCols)
          .eq('owner_id', uid)
          .order('created_at', ascending: false);

      final claimedPlayerRows = await client
          .from('players')
          .select('team_id')
          .eq('user_id', uid);

      final teamIdSet = <String>{
        for (final r in (ownedTeams as List)) (r as Map)['id'].toString(),
        for (final r in (claimedPlayerRows as List))
          (r as Map)['team_id'].toString(),
      };

      if (teamIdSet.isNotEmpty) {
        final allTeams = await client
            .from('teams')
            .select(LocalEventStore._teamSelectCols)
            .inFilter('id', teamIdSet.toList());

        final batch = db.batch();
        for (final raw in (allTeams as List)) {
          final map = Map<String, Object?>.from(raw as Map);
          map['is_owner'] = map['owner_id'] == uid ? 1 : 0;
          map['synced'] = 1;
          final team = TeamProfile.fromMap(map);
          batch.insert(
            'teams',
            team.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          restored++;
        }

        final allPlayers = await client
            .from('players')
            .select(LocalEventStore._playerSelectCols)
            .inFilter('team_id', teamIdSet.toList());
        for (final raw in (allPlayers as List)) {
          final p = PlayerProfile.fromMap(
            Map<String, Object?>.from(raw as Map),
          ).copyWith(synced: true);
          batch.insert(
            'players',
            p.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      // 2. Restore tournaments & tournament_teams
      final tRows = await client
          .from('tournaments')
          .select(LocalEventStore._tournamentSelectCols)
          .eq('owner_id', uid)
          .order('created_at', ascending: false);

      for (final raw in (tRows as List)) {
        final tMap = Map<String, Object?>.from(raw as Map);
        final t = Tournament.fromMap(tMap).copyWith(synced: true);
        await db.insert(
          'tournaments',
          t.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        final ttRows = await client
            .from('tournament_teams')
            .select(LocalEventStore._tournamentTeamSelectCols)
            .eq('tournament_id', t.id);
        await db.delete(
          'tournament_teams',
          where: 'tournament_id = ?',
          whereArgs: [t.id],
        );
        final ttBatch = db.batch();
        for (final tt in (ttRows as List)) {
          final entry = TournamentTeamEntry.fromMap(
            Map<String, Object?>.from(tt as Map),
          );
          ttBatch.insert(
            'tournament_teams',
            entry.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await ttBatch.commit(noResult: true);
        restored++;
      }

      // 3. Restore matches (owned + co-scored + involving user's teams)
      final matchIds = <String>{};
      final ownedMatches = await client
          .from('matches')
          .select('id')
          .eq('owner_id', uid)
          .order('created_at', ascending: false)
          .limit(60);
      for (final r in (ownedMatches as List)) {
        matchIds.add((r as Map)['id'].toString());
      }
      final coScored = await client
          .from('match_scorers')
          .select('match_id')
          .eq('user_id', uid);
      for (final r in (coScored as List)) {
        matchIds.add((r as Map)['match_id'].toString());
      }
      for (final tid in teamIdSet) {
        final tmRows = await client
            .from('matches')
            .select('id')
            .or('team_a_id.eq.$tid,team_b_id.eq.$tid')
            .order('created_at', ascending: false)
            .limit(30);
        for (final r in (tmRows as List)) {
          matchIds.add((r as Map)['id'].toString());
        }
      }

      for (final mid in matchIds) {
        if (await pullRemoteMatchToLocal(mid)) {
          restored++;
        }
      }

      // 4. Restore user profile metadata from auth user
      final user = client.auth.currentUser;
      if (user != null) {
        final meta = user.userMetadata ?? const <String, dynamic>{};
        final localProfile = await getUserProfile();
        final merged = localProfile.copyWith(
          displayName: (meta['full_name'] as String?)?.trim().isNotEmpty == true
              ? (meta['full_name'] as String).trim()
              : localProfile.displayName,
          role: (meta['role'] as String?)?.trim().isNotEmpty == true
              ? (meta['role'] as String).trim()
              : localProfile.role,
          linkedPlayerName: (meta['linked_player_name'] as String?) ??
              localProfile.linkedPlayerName,
          avatarUrl:
              (meta['avatar_url'] as String?) ?? localProfile.avatarUrl,
        );
        await saveUserProfile(merged, syncToCloud: false);
      }

      await refreshDirectory();
    } catch (e) {
      debugPrint('restoreAccountDataFromCloud error: $e');
    }
    return restored;
  }

  Future<({int matchesSaved, int teamsSaved, int tournamentsSaved})>
      saveGuestDataToCurrentAccount() async {
    final uid = signedInUserId;
    if (uid == null) {
      return (matchesSaved: 0, teamsSaved: 0, tournamentsSaved: 0);
    }

    final db = await database;
    final client = Supabase.instance.client;

    // 1. Merge offline guest teams that match an existing cloud team by name
    final localTeams = await listTeams();
    final unsyncedTeams = localTeams.where((t) => !t.synced && t.isOwner).toList();
    if (unsyncedTeams.isNotEmpty) {
      try {
        final cloudRows = await client
            .from('teams')
            .select(LocalEventStore._teamSelectCols)
            .eq('owner_id', uid);
        final cloudTeamIds = (cloudRows as List)
            .map((r) => (r as Map)['id'].toString())
            .toList();
        final cloudPlayersByTeam = <String, List<PlayerProfile>>{};
        if (cloudTeamIds.isNotEmpty) {
          final cpRows = await client
              .from('players')
              .select(LocalEventStore._playerSelectCols)
              .inFilter('team_id', cloudTeamIds);
          for (final raw in (cpRows as List)) {
            final p = PlayerProfile.fromMap(Map<String, Object?>.from(raw as Map));
            cloudPlayersByTeam.putIfAbsent(p.teamId, () => []).add(p);
          }
        }
        final ownedCloudTeams = [
          for (final raw in cloudRows)
            CloudOwnedTeam(
              id: (raw as Map)['id'].toString(),
              name: raw['name'].toString(),
              location: raw['location'] as String?,
              squad: cloudPlayersByTeam[raw['id'].toString()] ?? const [],
            ),
        ];
        final merges = GuestTeamMergePlanner.planOfflineMerges(
          unsyncedGuestTeams: unsyncedTeams,
          ownedCloudTeams: ownedCloudTeams,
        );
        for (final action in merges) {
          // Repoint local matches & tournament_teams to surviving team ID
          await db.update(
            'matches',
            {'team_a_id': action.survivingTeamId, 'synced': 0},
            where: 'team_a_id = ?',
            whereArgs: [action.guestTeamId],
          );
          await db.update(
            'matches',
            {'team_b_id': action.survivingTeamId, 'synced': 0},
            where: 'team_b_id = ?',
            whereArgs: [action.guestTeamId],
          );
          await db.update(
            'tournament_teams',
            {'team_id': action.survivingTeamId},
            where: 'team_id = ?',
            whereArgs: [action.guestTeamId],
          );
          for (final p in action.playersToReparent) {
            await db.insert(
              'players',
              p.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          await db.delete(
            'teams',
            where: 'id = ?',
            whereArgs: [action.guestTeamId],
          );
          if (action.needsCloudTeamUpdate && action.mergedLocation != null) {
            await client
                .from('teams')
                .update({'location': action.mergedLocation})
                .eq('id', action.survivingTeamId);
          }
        }
      } catch (e) {
        debugPrint('Guest team merge check skipped: $e');
      }
    }

    // 2. Sync all local unsynced teams, players, tournaments, and matches
    var teamsSaved = 0;
    final refreshedTeams = await listTeams();
    for (final t in refreshedTeams.where((t) => t.isOwner)) {
      final wasUnsynced = !t.synced || t.squad.any((p) => !p.synced);
      if (wasUnsynced) {
        await syncTeamToSupabase(t.id);
        teamsSaved++;
      }
    }

    var tournamentsSaved = 0;
    final tournaments = await listTournaments();
    for (final tr in tournaments.where((t) => !t.synced)) {
      await syncTournamentToSupabase(tr.id);
      tournamentsSaved++;
    }

    var matchesSaved = 0;
    final matches = await listMatches();
    for (final m in matches.where((m) => !m.isDemo)) {
      final pushed = await syncPendingToSupabase(m.id);
      if (pushed > 0) matchesSaved++;
    }

    await refreshDirectory();
    return (
      matchesSaved: matchesSaved,
      teamsSaved: teamsSaved,
      tournamentsSaved: tournamentsSaved,
    );
  }

  Future<({int matchesSaved, int teamsSaved, int tournamentsSaved})>
      claimGuestDataForSignedInUser({String? previousGuestUid}) async {
    final res = await saveGuestDataToCurrentAccount();
    LocalEventStore.notifyAccountDataChanged();
    return res;
  }

  Future<UnsyncedLocalCounts> countUnsyncedLocalData() async {
    final db = await database;
    final unsyncedBalls = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM ball_events b '
            'JOIN matches m ON m.id = b.match_id '
            'WHERE b.synced = 0 AND m.is_demo = 0',
          ),
        ) ??
        0;
    final unsyncedMatches = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM matches WHERE synced = 0 AND is_demo = 0',
          ),
        ) ??
        0;
    final unsyncedTeams = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM teams WHERE synced = 0 AND is_owner = 1',
          ),
        ) ??
        0;
    final unsyncedTournaments = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM tournaments WHERE synced = 0',
          ),
        ) ??
        0;
    return UnsyncedLocalCounts(
      ballEvents: unsyncedBalls,
      matches: unsyncedMatches,
      teams: unsyncedTeams,
      tournaments: unsyncedTournaments,
    );
  }

  Future<void> syncAllPendingBeforeSignOut() async {
    if (!isSignedInAccount) return;
    await syncAllPendingToSupabase(retryPendingClaim: false);
  }

  Future<int> syncAllPendingToSupabase({bool retryPendingClaim = true}) async {
    if (!isSignedInAccount) return 0;
    var total = 0;

    final teams = await listTeams();
    for (final t in teams.where((t) => t.isOwner)) {
      if (!t.synced || t.squad.any((p) => !p.synced)) {
        await syncTeamToSupabase(t.id);
        total++;
      }
    }

    final tournaments = await listTournaments();
    for (final tr in tournaments.where((t) => !t.synced)) {
      await syncTournamentToSupabase(tr.id);
      total++;
    }

    final matches = await listMatches();
    for (final m in matches.where((m) => !m.isDemo)) {
      total += await syncPendingToSupabase(m.id);
    }

    return total;
  }
}
