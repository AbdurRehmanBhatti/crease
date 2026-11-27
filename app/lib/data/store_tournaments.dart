part of 'local_event_store.dart';

extension LocalEventStoreTournaments on LocalEventStore {
  Future<List<Tournament>> listTournaments() async {
    final db = await database;
    final tRows = await db.query('tournaments', orderBy: 'created_at DESC');
    if (tRows.isEmpty) return const [];
    final entryRows = await db.query(
      'tournament_teams',
      orderBy: 'seed_order ASC, created_at ASC',
    );
    final teamNames = directory.teamNamesById;
    final byTournament = <String, List<TournamentTeamEntry>>{};
    for (final row in entryRows) {
      final entry = TournamentTeamEntry.fromMap(
        row,
        teamNamesById: teamNames,
      );
      byTournament
          .putIfAbsent(entry.tournamentId, () => <TournamentTeamEntry>[])
          .add(entry);
    }
    return [
      for (final row in tRows)
        Tournament.fromMap(
          row,
          entries: byTournament[row['id']! as String] ?? const [],
        ),
    ];
  }

  Future<Tournament?> getTournament(String tournamentId) async {
    final db = await database;
    final rows = await db.query(
      'tournaments',
      where: 'id = ?',
      whereArgs: [tournamentId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final entryRows = await db.query(
      'tournament_teams',
      where: 'tournament_id = ?',
      whereArgs: [tournamentId],
      orderBy: 'seed_order ASC, created_at ASC',
    );
    final entries = entryRows
        .map(
          (r) => TournamentTeamEntry.fromMap(
            r,
            teamNamesById: directory.teamNamesById,
          ),
        )
        .toList();
    return Tournament.fromMap(rows.first, entries: entries);
  }

  Future<void> saveTournament(Tournament tournament) async {
    final db = await database;
    await db.insert(
      'tournaments',
      tournament.copyWith(synced: false).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.delete(
      'tournament_teams',
      where: 'tournament_id = ?',
      whereArgs: [tournament.id],
    );
    final batch = db.batch();
    for (var i = 0; i < tournament.entries.length; i++) {
      final entry = tournament.entries[i].copyWith(seedOrder: i);
      batch.insert(
        'tournament_teams',
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> syncTournamentToSupabase(String tournamentId) async {
    try {
      final uid = signedInUserId;
      if (uid == null) return;
      final t = await getTournament(tournamentId);
      if (t == null) return;

      final client = Supabase.instance.client;
      await client.from('tournaments').upsert(
        {
          'id': t.id,
          'owner_id': uid,
          'name': t.name,
          'location': t.location,
          'start_date': t.startDate?.millisecondsSinceEpoch,
          'end_date': t.endDate?.millisecondsSinceEpoch,
          'overs_limit': t.oversLimit,
          'players_per_side': t.playersPerSide,
          'last_man_stands': t.lastManStands,
          'max_overs_per_bowler': t.maxOversPerBowler,
          'format_label': t.formatLabel,
          'points_for_win': t.pointsForWin,
          'points_for_tie': t.pointsForTie,
          'structure': t.structure.name,
          'rounds_per_pair': t.roundsPerPair,
          'knockout_qualifiers': t.knockoutQualifiers,
          'visibility': t.visibility.name,
          'created_at': t.createdAt.millisecondsSinceEpoch,
        },
        onConflict: 'id',
      );

      // Sync referenced teams first so FK never fails
      for (final e in t.entries) {
        if (e.teamId != null && e.teamId!.isNotEmpty) {
          await syncTeamToSupabase(e.teamId!);
        }
      }

      await client
          .from('tournament_teams')
          .delete()
          .eq('tournament_id', t.id);
      if (t.entries.isNotEmpty) {
        await client.from('tournament_teams').insert([
          for (var i = 0; i < t.entries.length; i++)
            {
              'id': t.entries[i].id,
              'tournament_id': t.id,
              'team_id': t.entries[i].teamId,
              'ad_hoc_name': t.entries[i].adHocName,
              'seed_order': i,
              'created_at': t.entries[i].createdAt.millisecondsSinceEpoch,
            },
        ]);
      }

      final db = await database;
      await db.update(
        'tournaments',
        {'synced': 1},
        where: 'id = ?',
        whereArgs: [tournamentId],
      );
    } catch (e) {
      if (kDebugMode) debugPrint('syncTournamentToSupabase skipped: $e');
    }
  }

  Future<
      ({
        Tournament tournament,
        List<DerivedMatchState> matches,
        bool isOwner,
      })?> fetchRemoteTournament(String tournamentId) async {
    try {
      final client = Supabase.instance.client;
      final tRow = await client
          .from('tournaments')
          .select(LocalEventStore._tournamentSelectCols)
          .eq('id', tournamentId)
          .maybeSingle();
      if (tRow == null) return null;

      final ttRows = await client
          .from('tournament_teams')
          .select(LocalEventStore._tournamentTeamSelectCols)
          .eq('tournament_id', tournamentId)
          .order('seed_order', ascending: true);

      final teamIds = <String>{
        for (final r in (ttRows as List))
          if ((r as Map)['team_id'] != null) r['team_id'].toString(),
      };
      final teamNames = Map<String, String>.from(directory.teamNamesById);
      if (teamIds.isNotEmpty) {
        final tNamesRows = await client
            .from('teams')
            .select('id, name')
            .inFilter('id', teamIds.toList());
        for (final r in (tNamesRows as List)) {
          final m = r as Map;
          teamNames[m['id'].toString()] = m['name'].toString();
        }
      }

      final entries = ttRows
          .map(
            (r) => TournamentTeamEntry.fromMap(
              Map<String, Object?>.from(r as Map),
              teamNamesById: teamNames,
            ),
          )
          .toList();

      final tournament = Tournament.fromMap(
        Map<String, Object?>.from(tRow),
        entries: entries,
      );

      final mRows = await client
          .from('matches')
          .select('id')
          .eq('tournament_id', tournamentId)
          .order('created_at', ascending: true);

      final derived = <DerivedMatchState>[];
      for (final raw in (mRows as List)) {
        final mid = (raw as Map)['id'] as String?;
        if (mid == null) continue;
        final bundle = await fetchRemoteMatch(mid);
        if (bundle != null) {
          derived.add(
            CricketEngine.derive(
              bundle.config,
              bundle.events,
              playerNamesById: bundle.playerNamesById,
              teamNamesById: {...teamNames, ...bundle.teamNamesById},
            ),
          );
        }
      }

      final uid = signedInUserId;
      final isOwner = uid != null && tRow['owner_id'] == uid;
      return (tournament: tournament, matches: derived, isOwner: isOwner);
    } catch (_) {
      return null;
    }
  }

  Future<bool> pullRemoteTournamentToLocal(String tournamentId) async {
    try {
      final fetched = await fetchRemoteTournament(tournamentId);
      if (fetched == null) return false;
      final db = await database;
      await db.insert(
        'tournaments',
        fetched.tournament.copyWith(synced: true).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await db.delete(
        'tournament_teams',
        where: 'tournament_id = ?',
        whereArgs: [tournamentId],
      );
      final batch = db.batch();
      for (final e in fetched.tournament.entries) {
        batch.insert(
          'tournament_teams',
          e.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      for (final m in fetched.matches) {
        await pullRemoteMatchToLocal(m.config.id);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isTournamentKnockoutsUnlockedEarly(String tournamentId) async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['ko_unlock_$tournamentId'],
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['value'] == '1';
  }

  Future<void> setTournamentKnockoutsUnlockedEarly(
    String tournamentId,
    bool unlocked,
  ) async {
    final db = await database;
    if (unlocked) {
      await db.insert(
        'app_settings',
        {'key': 'ko_unlock_$tournamentId', 'value': '1'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await db.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['ko_unlock_$tournamentId'],
      );
    }
  }

  Future<void> deleteTournament(String tournamentId) async {
    final db = await database;
    await db.update(
      'matches',
      {'tournament_id': null},
      where: 'tournament_id = ?',
      whereArgs: [tournamentId],
    );
    await db.delete(
      'tournament_teams',
      where: 'tournament_id = ?',
      whereArgs: [tournamentId],
    );
    await db.delete(
      'tournaments',
      where: 'id = ?',
      whereArgs: [tournamentId],
    );
    try {
      if (isSignedInAccount) {
        await Supabase.instance.client
            .from('tournaments')
            .delete()
            .eq('id', tournamentId);
      }
    } catch (_) {}
  }

  Future<
      List<
          ({
            String id,
            String name,
            String? location,
            String formatLabel,
            int teamCount,
            String? dateRangeLabel,
          })>> searchPublicTournaments(
    String query, {
    int limit = 10,
    Set<String> excludeIds = const {},
  }) async {
    final clean = query.trim();
    if (clean.length < 2) return const [];
    try {
      final rows = await Supabase.instance.client.rpc(
        'search_public_tournaments',
        params: {'p_query': clean, 'p_limit': limit},
      );
      final out = <({
        String id,
        String name,
        String? location,
        String formatLabel,
        int teamCount,
        String? dateRangeLabel,
      })>[];
      for (final raw in (rows as List)) {
        final m = Map<String, Object?>.from(raw as Map);
        final id = (m['id'] as String?) ?? '';
        final name = (m['name'] as String?)?.trim() ?? '';
        if (id.isEmpty || name.isEmpty || excludeIds.contains(id)) continue;
        final rawLoc = (m['location'] as String?)?.trim();
        final loc = (rawLoc != null && rawLoc.isNotEmpty) ? rawLoc : null;
        final rawStart = m['start_date'] as num?;
        final rawEnd = m['end_date'] as num?;
        final start = rawStart != null
            ? DateTime.fromMillisecondsSinceEpoch(rawStart.toInt())
            : null;
        final end = rawEnd != null
            ? DateTime.fromMillisecondsSinceEpoch(rawEnd.toInt())
            : null;
        String? dateLabel;
        if (start != null && end != null) {
          dateLabel = (start.year == end.year &&
                  start.month == end.month &&
                  start.day == end.day)
              ? Tournament.formatShortDate(start)
              : '${Tournament.formatShortDate(start)} – ${Tournament.formatShortDate(end)}';
        } else if (start != null) {
          dateLabel = 'Starts ${Tournament.formatShortDate(start)}';
        } else if (end != null) {
          dateLabel = 'Ends ${Tournament.formatShortDate(end)}';
        }
        final teamsList = m['teams'];
        final count = teamsList is List ? teamsList.length : 0;
        out.add((
          id: id,
          name: name,
          location: loc,
          formatLabel: (m['format_label'] as String?) ?? '',
          teamCount: count,
          dateRangeLabel: dateLabel,
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}
