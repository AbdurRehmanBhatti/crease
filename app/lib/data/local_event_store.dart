import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';
import '../domain/team_profile.dart';
import '../domain/tournament_engine.dart';
import '../domain/user_profile.dart';

/// Offline-first SQLite event store for Crease.
/// Every ball is persisted locally first with a client-generated UUID so
/// scoring works with zero connectivity and syncs idempotently to Supabase.
class LocalEventStore {
  LocalEventStore._();
  static final LocalEventStore instance = LocalEventStore._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, 'crease_events.db');
    _db = await openDatabase(
      fullPath,
      version: 8,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE app_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE teams (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            is_my_team INTEGER NOT NULL DEFAULT 0,
            is_owner INTEGER NOT NULL DEFAULT 1,
            players TEXT NOT NULL DEFAULT '[]',
            player_meta TEXT NOT NULL DEFAULT '{}',
            synced INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE tournaments (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            overs_limit INTEGER NOT NULL,
            players_per_side INTEGER NOT NULL DEFAULT 11,
            format_label TEXT NOT NULL,
            team_rosters TEXT NOT NULL DEFAULT '{}',
            points_for_win INTEGER NOT NULL DEFAULT 2,
            points_for_tie INTEGER NOT NULL DEFAULT 1,
            synced INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE matches (
            id TEXT PRIMARY KEY,
            team_a TEXT NOT NULL,
            team_b TEXT NOT NULL,
            overs_limit INTEGER NOT NULL,
            players_per_side INTEGER NOT NULL,
            format_label TEXT NOT NULL,
            batting_first_team TEXT NOT NULL,
            opening_striker_1 TEXT NOT NULL,
            opening_non_striker_1 TEXT NOT NULL,
            opening_bowler_1 TEXT NOT NULL,
            opening_striker_2 TEXT NOT NULL,
            opening_non_striker_2 TEXT NOT NULL,
            opening_bowler_2 TEXT NOT NULL,
            team_a_players TEXT NOT NULL DEFAULT '[]',
            team_b_players TEXT NOT NULL DEFAULT '[]',
            tournament_id TEXT,
            is_test_match INTEGER NOT NULL DEFAULT 0,
            declared_innings TEXT NOT NULL DEFAULT '[]',
            follow_on_enforced INTEGER NOT NULL DEFAULT 0,
            first_innings_target_override INTEGER,
            is_demo INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE ball_events (
            id TEXT PRIMARY KEY,
            match_id TEXT NOT NULL,
            innings_number INTEGER NOT NULL,
            sequence_number INTEGER NOT NULL,
            striker TEXT NOT NULL,
            non_striker TEXT NOT NULL,
            bowler TEXT NOT NULL,
            runs_off_bat INTEGER NOT NULL DEFAULT 0,
            extra_type TEXT NOT NULL DEFAULT 'none',
            extra_runs INTEGER NOT NULL DEFAULT 0,
            is_wicket INTEGER NOT NULL DEFAULT 0,
            wicket_type TEXT,
            dismissed_batter TEXT,
            fielder TEXT,
            next_batter TEXT,
            synced INTEGER NOT NULL DEFAULT 0,
            voided INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            FOREIGN KEY (match_id) REFERENCES matches (id) ON DELETE CASCADE
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_ball_events_match ON ball_events (match_id, innings_number, sequence_number)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE matches ADD COLUMN team_a_players TEXT NOT NULL DEFAULT '[]'",
          );
          await db.execute(
            "ALTER TABLE matches ADD COLUMN team_b_players TEXT NOT NULL DEFAULT '[]'",
          );
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS tournaments (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              overs_limit INTEGER NOT NULL,
              players_per_side INTEGER NOT NULL DEFAULT 11,
              format_label TEXT NOT NULL,
              team_rosters TEXT NOT NULL DEFAULT '{}',
              points_for_win INTEGER NOT NULL DEFAULT 2,
              points_for_tie INTEGER NOT NULL DEFAULT 1,
              synced INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL
            )
          ''');
          await db.execute(
            'ALTER TABLE matches ADD COLUMN tournament_id TEXT',
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE matches ADD COLUMN is_test_match INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            "ALTER TABLE matches ADD COLUMN declared_innings TEXT NOT NULL DEFAULT '[]'",
          );
          await db.execute(
            'ALTER TABLE matches ADD COLUMN follow_on_enforced INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS teams (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              is_my_team INTEGER NOT NULL DEFAULT 0,
              players TEXT NOT NULL DEFAULT '[]',
              synced INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL
            )
          ''');
        }
        if (oldVersion < 6) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS app_settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 7) {
          await db.execute(
            "ALTER TABLE teams ADD COLUMN player_meta TEXT NOT NULL DEFAULT '{}'",
          );
        }
        if (oldVersion < 8) {
          await db.execute(
            'ALTER TABLE teams ADD COLUMN is_owner INTEGER NOT NULL DEFAULT 1',
          );
        }
      },
    );
    return _db!;
  }

  Future<UserProfile> getUserProfile() async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['user_profile'],
      limit: 1,
    );
    if (rows.isEmpty) return const UserProfile();
    return UserProfile.fromJson(rows.first['value']! as String);
  }

  Future<void> saveUserProfile(
    UserProfile profile, {
    bool syncCloud = true,
  }) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {'key': 'user_profile', 'value': profile.toJson()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (syncCloud) {
      try {
        final auth = Supabase.instance.client.auth;
        if (auth.currentUser != null) {
          await auth.updateUser(
            UserAttributes(
              data: {
                'display_name': profile.displayName,
                'role': profile.role,
                'linked_player_name': profile.linkedPlayerName,
                'custom_avatar_url': profile.avatarUrl ?? '',
              },
            ),
          );
        }
      } catch (_) {}
    }
  }

  /// Uploads a compressed JPEG profile photo to `avatars/<uid>/profile.jpg`
  /// and returns its cache-busted public URL.
  Future<String> uploadProfileAvatar(Uint8List bytes) async {
    final client = Supabase.instance.client;
    var uid = client.auth.currentUser?.id;
    uid ??= (await client.auth.signInAnonymously()).user?.id;
    if (uid == null) {
      throw StateError('Authentication required to upload photo.');
    }
    final path = '$uid/profile.jpg';
    await client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    final publicUrl = client.storage.from('avatars').getPublicUrl(path);
    return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Removes any legacy pre-seeded demo matches locally.
  Future<void> deleteDemoMatches() async {
    final db = await database;
    await db.delete(
      'ball_events',
      where: 'match_id IN (SELECT id FROM matches WHERE is_demo = 1)',
    );
    await db.delete('matches', where: 'is_demo = 1');
  }

  /// Clears user-specific local teams, tournaments, matches, and profile name
  /// on Sign Out (keeping only the user's theme preference).
  Future<void> clearLocalUserDataOnSignOut() async {
    final db = await database;
    final current = await getUserProfile();
    await db.delete('teams');
    await db.delete('tournaments');
    await db.delete('ball_events');
    await db.delete('matches');
    await saveUserProfile(
      UserProfile(themeMode: current.themeMode),
      syncCloud: false,
    );
  }

  Future<List<MatchConfig>> listMatches() async {
    final db = await database;
    final rows = await db.query('matches', orderBy: 'created_at DESC');
    return rows.map(MatchConfig.fromMap).toList();
  }

  Future<List<MatchConfig>> listMatchesForTournament(String tournamentId) async {
    final db = await database;
    final rows = await db.query(
      'matches',
      where: 'tournament_id = ?',
      whereArgs: [tournamentId],
      orderBy: 'created_at DESC',
    );
    return rows.map(MatchConfig.fromMap).toList();
  }

  Future<List<Tournament>> listTournaments() async {
    final db = await database;
    final rows = await db.query('tournaments', orderBy: 'created_at DESC');
    return rows.map(Tournament.fromMap).toList();
  }

  Future<List<TeamProfile>> listTeams() async {
    final db = await database;
    final rows = await db.query(
      'teams',
      orderBy: 'is_my_team DESC, name ASC',
    );
    return rows.map(TeamProfile.fromMap).toList();
  }

  Future<void> saveTeam(TeamProfile team) async {
    final db = await database;
    await db.insert(
      'teams',
      team.copyWith(synced: false).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> syncTeamToSupabase(String teamId) async {
    SupabaseClient? client;
    try {
      client = Supabase.instance.client;
    } catch (_) {
      return;
    }
    var userId = client.auth.currentUser?.id;
    if (userId == null) {
      try {
        userId = (await client.auth.signInAnonymously()).user?.id;
      } catch (_) {
        return;
      }
    }
    if (userId == null) return;
    final db = await database;
    final rows = await db.query('teams', where: 'id = ?', whereArgs: [teamId]);
    if (rows.isEmpty) return;
    final team = TeamProfile.fromMap(rows.first);
    try {
      await client.from('teams').upsert(
        {
          'id': team.id,
          'owner_id': userId,
          'name': team.name,
          'is_my_team': team.isMyTeam,
          'players': team.players,
          'player_meta': team.toJsonMetaMap(),
          'created_at': team.createdAt.millisecondsSinceEpoch,
        },
        onConflict: 'id',
      );
      await db.update(
        'teams',
        {'synced': 1},
        where: 'id = ?',
        whereArgs: [team.id],
      );
    } catch (e) {
      debugPrint('[Crease Sync] Team upsert failed: $e');
    }
  }

  /// Collects all unique team names and merged player rosters across all
  /// saved teams, tournaments, and matches so Quick Match can pick existing teams.
  Future<Map<String, List<String>>> listKnownTeamRosters() async {
    final rosters = <String, List<String>>{};

    void merge(String teamName, List<String> players) {
      final key = teamName.trim();
      if (key.isEmpty) return;
      final list = rosters.putIfAbsent(key, () => <String>[]);
      for (final p in players) {
        final trimmed = p.trim();
        if (trimmed.isEmpty) continue;
        if (!list.any((e) => e.toLowerCase() == trimmed.toLowerCase())) {
          list.add(trimmed);
        }
      }
    }

    final savedTeams = await listTeams();
    for (final t in savedTeams) {
      merge(t.name, t.players);
    }

    final tournaments = await listTournaments();
    for (final t in tournaments) {
      for (final entry in t.teamRosters.entries) {
        merge(entry.key, entry.value);
      }
    }

    final matches = await listMatches();
    for (final m in matches) {
      merge(m.teamA, m.teamAPlayers);
      merge(m.teamB, m.teamBPlayers);
    }

    return rosters;
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
    return Tournament.fromMap(rows.first);
  }

  Future<void> saveTournament(Tournament tournament) async {
    final db = await database;
    await db.insert(
      'tournaments',
      tournament.copyWith(synced: false).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> syncTournamentToSupabase(String tournamentId) async {
    SupabaseClient? client;
    try {
      client = Supabase.instance.client;
    } catch (_) {
      return;
    }
    var userId = client.auth.currentUser?.id;
    if (userId == null) {
      try {
        userId = (await client.auth.signInAnonymously()).user?.id;
      } catch (_) {
        return;
      }
    }
    if (userId == null) return;
    final t = await getTournament(tournamentId);
    if (t == null) return;
    try {
      await client.from('tournaments').upsert(
        {
          'id': t.id,
          'owner_id': userId,
          'name': t.name,
          'overs_limit': t.oversLimit,
          'players_per_side': t.playersPerSide,
          'format_label': t.formatLabel,
          'team_rosters': t.teamRosters,
          'points_for_win': t.pointsForWin,
          'points_for_tie': t.pointsForTie,
          'created_at': t.createdAt.millisecondsSinceEpoch,
        },
        onConflict: 'id',
      );
      final db = await database;
      await db.update(
        'tournaments',
        {'synced': 1},
        where: 'id = ?',
        whereArgs: [t.id],
      );
    } catch (e) {
      debugPrint('[Crease Sync] Tournament upsert failed: $e');
    }
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
    await db.insert(
      'matches',
      config.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Adds [playerName] to [teamName]'s roster on [matchId] if not already present.
  Future<MatchConfig?> addPlayerToTeam(
    String matchId,
    String teamName,
    String playerName,
  ) async {
    final trimmed = playerName.trim();
    if (trimmed.isEmpty) return null;
    final match = await getMatch(matchId);
    if (match == null) return null;
    final isTeamA = teamName == match.teamA;
    final current = List<String>.from(
      isTeamA ? match.teamAPlayers : match.teamBPlayers,
    );
    if (current.any((p) => p.toLowerCase() == trimmed.toLowerCase())) {
      return match;
    }
    current.add(trimmed);
    final updated = isTeamA
        ? match.copyWith(teamAPlayers: current)
        : match.copyWith(teamBPlayers: current);
    await saveMatch(updated);
    return updated;
  }

  Future<void> deleteMatch(String matchId) async {
    final db = await database;
    await db.delete('ball_events', where: 'match_id = ?', whereArgs: [matchId]);
    await db.delete('matches', where: 'id = ?', whereArgs: [matchId]);
    try {
      await Supabase.instance.client.from('matches').delete().eq('id', matchId);
    } catch (_) {}
  }

  Future<List<BallEvent>> getBallEvents(String matchId) async {
    final db = await database;
    final rows = await db.query(
      'ball_events',
      where: 'match_id = ?',
      whereArgs: [matchId],
      orderBy: 'sequence_number ASC',
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
    for (final event in events) {
      batch.insert(
        'ball_events',
        event.toMap(),
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

  /// Marks the most recent non-voided ball event in [matchId] as voided.
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

  /// Fetches a public/shared match and its ball events from the cloud when
  /// opened via a deep link on a device that does not store the match locally.
  Future<({MatchConfig config, List<BallEvent> events})?> fetchRemoteMatch(
    String matchId,
  ) async {
    SupabaseClient? client;
    try {
      client = Supabase.instance.client;
    } catch (_) {
      return null;
    }
    try {
      final matchRow = await client
          .from('matches')
          .select()
          .eq('id', matchId)
          .maybeSingle();
      if (matchRow == null) return null;

      final eventRows = await client
          .from('ball_events')
          .select()
          .eq('match_id', matchId)
          .order('sequence_number', ascending: true);

      final config = MatchConfig.fromMap(Map<String, Object?>.from(matchRow));
      final events = (eventRows as List)
          .map((r) => BallEvent.fromMap(Map<String, Object?>.from(r as Map)))
          .toList();
      return (config: config, events: events);
    } catch (e) {
      debugPrint('[Crease Sync] Remote fetch failed for match $matchId: $e');
      return null;
    }
  }

  /// Pulls a match and its ball events from the cloud into local SQLite
  /// (preserving any local unsynced events). Used during Scorer Handover.
  Future<bool> pullRemoteMatchToLocal(String matchId) async {
    final remote = await fetchRemoteMatch(matchId);
    if (remote == null) return false;
    final db = await database;
    await db.insert(
      'matches',
      remote.config.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final unsyncedRows = await db.query(
      'ball_events',
      columns: ['id'],
      where: 'match_id = ? AND synced = 0',
      whereArgs: [matchId],
    );
    final unsyncedIds = unsyncedRows.map((r) => r['id'] as String).toSet();

    final batch = db.batch();
    for (final ev in remote.events) {
      if (unsyncedIds.contains(ev.id)) continue;
      batch.insert(
        'ball_events',
        ev.copyWith(synced: true).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    return true;
  }

  /// Ensures a match row + all unsynced ball events are pushed to the cloud
  /// (even when 0 balls have been bowled yet).
  Future<void> ensureMatchSyncedToSupabase(String matchId) async {
    SupabaseClient? client;
    try {
      client = Supabase.instance.client;
    } catch (_) {
      throw StateError('Cloud sync is not configured.');
    }
    var userId = client.auth.currentUser?.id;
    if (userId == null) {
      final res = await client.auth.signInAnonymously();
      userId = res.user?.id;
    }
    if (userId == null) {
      throw StateError('Unable to sign in for cloud sync.');
    }

    final match = await getMatch(matchId);
    if (match == null) {
      throw StateError('Match not found locally.');
    }
    if (match.tournamentId != null) {
      await syncTournamentToSupabase(match.tournamentId!);
    }

    final existing = await client
        .from('matches')
        .select('id')
        .eq('id', match.id)
        .maybeSingle();

    if (existing == null) {
      await client.from('matches').insert({
        'id': match.id,
        'owner_id': userId,
        'active_scorer_id': userId,
        'team_a': match.teamA,
        'team_b': match.teamB,
        'overs_limit': match.oversLimit,
        'players_per_side': match.playersPerSide,
        'format_label': match.formatLabel,
        'batting_first_team': match.battingFirstTeam,
        'opening_striker_1': match.openingStrikerInnings1,
        'opening_non_striker_1': match.openingNonStrikerInnings1,
        'opening_bowler_1': match.openingBowlerInnings1,
        'opening_striker_2': match.openingStrikerInnings2,
        'opening_non_striker_2': match.openingNonStrikerInnings2,
        'opening_bowler_2': match.openingBowlerInnings2,
        'team_a_players': match.teamAPlayers,
        'team_b_players': match.teamBPlayers,
        'tournament_id': match.tournamentId,
        'is_test_match': match.isTestMatch,
        'declared_innings': match.declaredInnings,
        'follow_on_enforced': match.followOnEnforced,
        'first_innings_target_override': match.firstInningsTargetOverride,
        'is_demo': match.isDemo,
        'created_at': match.createdAt.millisecondsSinceEpoch,
      });
    } else {
      await client.from('matches').update({
        'overs_limit': match.oversLimit,
        'format_label': match.formatLabel,
        'first_innings_target_override': match.firstInningsTargetOverride,
        'team_a_players': match.teamAPlayers,
        'team_b_players': match.teamBPlayers,
        'declared_innings': match.declaredInnings,
        'follow_on_enforced': match.followOnEnforced,
      }).eq('id', match.id);
    }

    await syncPendingToSupabase(matchId);
  }

  /// Generates (or returns the existing) 6-digit handover code for [matchId].
  Future<String> createScorerHandoverCode(String matchId) async {
    await ensureMatchSyncedToSupabase(matchId);
    final client = Supabase.instance.client;
    final code = await client.rpc(
      'create_scorer_handover_code',
      params: {'p_match_id': matchId},
    );
    return code.toString();
  }

  /// Claims the active scorer baton using a 6-digit [joinCode], pulls the
  /// full match & ball log into local SQLite, and returns the `matchId`.
  Future<String> claimScorerBaton(String joinCode) async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) {
      await client.auth.signInAnonymously();
    }
    final matchId = (await client.rpc(
      'claim_scorer_baton',
      params: {'p_join_code': joinCode.trim()},
    ))
        .toString();

    final ok = await pullRemoteMatchToLocal(matchId);
    if (!ok) {
      throw StateError('Joined match, but could not download its scorecard.');
    }
    return matchId;
  }

  /// Reclaims the active scorer baton for an already-authorized scorer and
  /// pulls the latest remote balls so both devices stay in perfect sync.
  Future<void> reclaimScorerBaton(String matchId) async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) {
      await client.auth.signInAnonymously();
    }
    await client.rpc(
      'reclaim_scorer_baton',
      params: {'p_match_id': matchId},
    );
    await pullRemoteMatchToLocal(matchId);
  }

  /// Returns the cloud `active_scorer_id` for [matchId] only when another device
  /// has actually claimed the baton AND the current user is an authorized
  /// participant (owner or co-scorer) who can reclaim it.
  Future<String?> fetchActiveScorerId(String matchId) async {
    try {
      final client = Supabase.instance.client;
      final myUid = client.auth.currentUser?.id;
      if (myUid == null) return null;
      final row = await client
          .from('matches')
          .select('owner_id, active_scorer_id, scorer_join_code')
          .eq('id', matchId)
          .maybeSingle();
      if (row == null || row['scorer_join_code'] == null) return null;
      final activeId = row['active_scorer_id'] as String?;
      if (activeId == null || activeId == myUid) return null;

      final ownerId = row['owner_id'] as String?;
      final isParticipant = ownerId == myUid ||
          (await client
                  .from('match_scorers')
                  .select('user_id')
                  .eq('match_id', matchId)
                  .eq('user_id', myUid)
                  .maybeSingle()) !=
              null;
      if (!isParticipant) return null;
      return activeId;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Team Invite Codes, Player Claiming & Full Cloud Account Restore
  // ---------------------------------------------------------------------------

  Future<String> createTeamInviteCode(String teamId) async {
    await syncTeamToSupabase(teamId);
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) {
      await client.auth.signInAnonymously();
    }
    final code = await client.rpc(
      'create_team_invite_code',
      params: {'p_team_id': teamId},
    );
    return code.toString();
  }

  /// Rotates a team's 6-digit invite code, immediately invalidating any old link/code.
  Future<String> resetTeamInviteCode(String teamId) async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) {
      await client.auth.signInAnonymously();
    }
    final code = await client.rpc(
      'reset_team_invite_code',
      params: {'p_team_id': teamId},
    );
    return code.toString();
  }

  /// Pulls any newly scored cloud matches for all pinned `My Team` squads so
  /// teammates automatically receive fresh matches & career stats.
  Future<int> pullLatestForMyTeams() async {
    final teams = await listTeams();
    var pulled = 0;
    for (final t in teams.where((t) => t.isMyTeam)) {
      pulled += await pullMatchesForTeamName(t.name);
    }
    return pulled;
  }

  Future<TeamInvitePreview> previewTeamByCode(String joinCode) async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) {
      await client.auth.signInAnonymously();
    }
    final raw = await client.rpc(
      'preview_team_by_code',
      params: {'p_join_code': joinCode.trim()},
    );
    final map = Map<String, Object?>.from(raw as Map);
    final players = ((map['players'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
    final claimed = ((map['claimed_players'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
    return TeamInvitePreview(
      teamId: map['team_id']! as String,
      teamName: map['team_name']! as String,
      players: players,
      claimedPlayers: claimed,
      myClaimedPlayer: map['my_claimed_player'] as String?,
    );
  }

  /// Claims [playerName] inside the team identified by [joinCode], pins that
  /// team as `My Team` locally, links the user's Profile to [playerName], and
  /// pulls all of that team's cloud matches so their Career Stats appear immediately.
  Future<String> claimTeamPlayer(String joinCode, String playerName) async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) {
      await client.auth.signInAnonymously();
    }
    final raw = await client.rpc(
      'claim_team_player',
      params: {
        'p_join_code': joinCode.trim(),
        'p_player_name': playerName.trim(),
      },
    );
    final map = Map<String, Object?>.from(raw as Map);
    final teamId = map['team_id']! as String;
    final teamName = map['team_name']! as String;
    final claimedName = map['player_name']! as String;
    final players = ((map['players'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();

    final db = await database;
    await db.insert(
      'teams',
      TeamProfile(
        id: teamId,
        name: teamName,
        isMyTeam: true,
        isOwner: false,
        players: players,
        synced: true,
        createdAt: DateTime.now(),
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final currentProfile = await getUserProfile();
    await saveUserProfile(
      currentProfile.copyWith(
        displayName: currentProfile.displayName.trim().isEmpty
            ? claimedName
            : currentProfile.displayName,
        linkedPlayerName: claimedName,
      ),
    );

    await pullMatchesForTeamName(teamName);
    return teamName;
  }

  /// Fetches cloud matches where [teamName] played and stores them locally.
  /// Never overwrites a match that already exists locally and is owned by this user
  /// (so local rule revisions / declarations are never clobbered by a stale pull).
  Future<int> pullMatchesForTeamName(String teamName) async {
    try {
      final client = Supabase.instance.client;
      final myUid = client.auth.currentUser?.id;
      final rows = await client
          .from('matches')
          .select('id, owner_id')
          .or('team_a.ilike.$teamName,team_b.ilike.$teamName')
          .order('created_at', ascending: false)
          .limit(50);
      var pulled = 0;
      for (final r in (rows as List)) {
        final row = r as Map;
        final id = row['id'] as String?;
        final ownerId = row['owner_id'] as String?;
        if (id == null) continue;
        final localExists = (await getMatch(id)) != null;
        if (localExists && myUid != null && ownerId == myUid) {
          // Local copy is authoritative for the match owner; push local rules instead.
          try {
            await ensureMatchSyncedToSupabase(id);
          } catch (_) {}
          continue;
        }
        if (await pullRemoteMatchToLocal(id)) {
          pulled++;
        }
      }
      return pulled;
    } catch (e) {
      debugPrint('[Crease Sync] pullMatchesForTeamName failed: $e');
      return 0;
    }
  }

  /// Returns lowercase names of players who have claimed accounts on [teamId].
  Future<Set<String>> fetchClaimedPlayersForTeam(String teamId) async {
    try {
      final rows = await Supabase.instance.client
          .from('team_members')
          .select('player_name')
          .eq('team_id', teamId);
      return (rows as List)
          .map((r) => ((r as Map)['player_name'] as String).toLowerCase())
          .toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  /// Unlinks a claimed player from [teamId] (allowed for the player or team owner).
  Future<void> unlinkTeamPlayer(String teamId, String playerName) async {
    await Supabase.instance.client
        .from('team_members')
        .delete()
        .eq('team_id', teamId)
        .ilike('player_name', playerName.trim());
  }

  /// Restores all teams, tournaments, matches, and claimed memberships for the
  /// signed-in user into local SQLite (used when signing in on a new phone).
  Future<int> restoreAccountDataFromCloud() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return 0;

    final db = await database;
    var restoredMatches = 0;

    try {
      // 0. Restore cloud user profile metadata (display name, role, linked player, avatar)
      final meta = client.auth.currentUser?.userMetadata;
      if (meta != null) {
        final currentProfile = await getUserProfile();
        final cloudName =
            ((meta['display_name'] ?? meta['full_name'] ?? meta['name'])
                        as String?)
                    ?.trim() ??
                '';
        final cloudRole = (meta['role'] as String?)?.trim() ?? '';
        final cloudLinked = (meta['linked_player_name'] as String?)?.trim();
        final hasCustomKey = meta.containsKey('custom_avatar_url');
        final customAvatar = (meta['custom_avatar_url'] as String?)?.trim();
        final oauthAvatar =
            ((meta['avatar_url'] ?? meta['picture']) as String?)?.trim();
        final resolvedAvatar = hasCustomKey
            ? (customAvatar != null && customAvatar.isNotEmpty
                ? customAvatar
                : null)
            : (oauthAvatar != null && oauthAvatar.isNotEmpty
                ? oauthAvatar
                : null);
        await saveUserProfile(
          currentProfile.copyWith(
            displayName:
                cloudName.isNotEmpty ? cloudName : currentProfile.displayName,
            role: cloudRole.isNotEmpty ? cloudRole : currentProfile.role,
            linkedPlayerName: (cloudLinked != null && cloudLinked.isNotEmpty)
                ? cloudLinked
                : currentProfile.linkedPlayerName,
            avatarUrl: resolvedAvatar,
            clearAvatar: hasCustomKey && resolvedAvatar == null,
          ),
          syncCloud: false,
        );
      }

      // 1. Owned teams
      final ownedTeams =
          await client.from('teams').select().eq('owner_id', uid);
      final teamNamesToPull = <String>{};
      for (final row in (ownedTeams as List)) {
        final team = TeamProfile.fromMap(Map<String, Object?>.from(row as Map));
        await db.insert(
          'teams',
          team.copyWith(synced: true).toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        teamNamesToPull.add(team.name);
      }

      // 2. Claimed team memberships
      final memberships = await client
          .from('team_members')
          .select('team_id, player_name')
          .eq('user_id', uid);
      String? firstClaimedPlayer;
      for (final m in (memberships as List)) {
        final mMap = m as Map;
        final tid = mMap['team_id'] as String?;
        final pname = mMap['player_name'] as String?;
        firstClaimedPlayer ??= pname;
        if (tid != null) {
          final tRow = await client
              .from('teams')
              .select()
              .eq('id', tid)
              .maybeSingle();
          if (tRow != null) {
            final team = TeamProfile.fromMap(Map<String, Object?>.from(tRow));
            final ownsTeam = (tRow['owner_id'] as String?) == uid;
            await db.insert(
              'teams',
              team
                  .copyWith(isMyTeam: true, isOwner: ownsTeam, synced: true)
                  .toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            teamNamesToPull.add(team.name);
          }
        }
      }

      if (firstClaimedPlayer != null) {
        final currentProfile = await getUserProfile();
        if (currentProfile.linkedPlayerName == null) {
          await saveUserProfile(
            currentProfile.copyWith(
              displayName: currentProfile.displayName.trim().isEmpty
                  ? firstClaimedPlayer
                  : currentProfile.displayName,
              linkedPlayerName: firstClaimedPlayer,
            ),
          );
        }
      }

      // 3. Owned matches + co-scored matches
      final matchIds = <String>{};
      final ownedMatches =
          await client.from('matches').select('id').eq('owner_id', uid);
      for (final r in (ownedMatches as List)) {
        matchIds.add((r as Map)['id'] as String);
      }
      final coScored = await client
          .from('match_scorers')
          .select('match_id')
          .eq('user_id', uid);
      for (final r in (coScored as List)) {
        matchIds.add((r as Map)['match_id'] as String);
      }
      for (final id in matchIds) {
        if (await pullRemoteMatchToLocal(id)) {
          restoredMatches++;
        }
      }

      // 4. Matches played by any of the user's teams
      for (final name in teamNamesToPull) {
        restoredMatches += await pullMatchesForTeamName(name);
      }
    } catch (e) {
      debugPrint('[Crease Sync] restoreAccountDataFromCloud failed: $e');
    }
    return restoredMatches;
  }

  /// Syncs all teams, tournaments, and matches that have unsynced records to Supabase.
  Future<int> syncAllPendingToSupabase() async {
    final teams = await listTeams();
    for (final t in teams) {
      if (!t.synced) {
        await syncTeamToSupabase(t.id);
      }
    }
    final tournaments = await listTournaments();
    for (final t in tournaments) {
      if (!t.synced) {
        await syncTournamentToSupabase(t.id);
      }
    }
    final matches = await listMatches();
    var total = 0;
    for (final m in matches) {
      total += await syncPendingToSupabase(m.id);
    }
    return total;
  }

  /// Idempotent sync of unsynced ball events to Supabase when configured.
  /// Returns the number of events synced (0 if offline or Supabase not configured).
  Future<int> syncPendingToSupabase(String matchId) async {
    SupabaseClient? client;
    try {
      client = Supabase.instance.client;
    } catch (_) {
      return 0;
    }

    var userId = client.auth.currentUser?.id;
    if (userId == null) {
      try {
        final res = await client.auth.signInAnonymously();
        userId = res.user?.id;
      } catch (e) {
        debugPrint('[Crease Sync] Anonymous sign-in failed: $e');
        return 0;
      }
    }
    if (userId == null) return 0;

    final db = await database;
    final unsyncedRows = await db.query(
      'ball_events',
      where: 'match_id = ? AND synced = 0',
      whereArgs: [matchId],
      orderBy: 'sequence_number ASC',
    );
    if (unsyncedRows.isEmpty) return 0;

    try {
      // Ensure parent tournament & match rows exist before upserting ball events.
      // Never overwrite owner_id / active_scorer_id / scorer_join_code if the
      // match already exists on the server (so co-scorers preserve ownership).
      final match = await getMatch(matchId);
      if (match != null) {
        if (match.tournamentId != null) {
          await syncTournamentToSupabase(match.tournamentId!);
        }
        final existing = await client
            .from('matches')
            .select('id')
            .eq('id', match.id)
            .maybeSingle();
        if (existing == null) {
          await client.from('matches').insert({
            'id': match.id,
            'owner_id': userId,
            'active_scorer_id': userId,
            'team_a': match.teamA,
            'team_b': match.teamB,
            'overs_limit': match.oversLimit,
            'players_per_side': match.playersPerSide,
            'format_label': match.formatLabel,
            'batting_first_team': match.battingFirstTeam,
            'opening_striker_1': match.openingStrikerInnings1,
            'opening_non_striker_1': match.openingNonStrikerInnings1,
            'opening_bowler_1': match.openingBowlerInnings1,
            'opening_striker_2': match.openingStrikerInnings2,
            'opening_non_striker_2': match.openingNonStrikerInnings2,
            'opening_bowler_2': match.openingBowlerInnings2,
            'team_a_players': match.teamAPlayers,
            'team_b_players': match.teamBPlayers,
            'tournament_id': match.tournamentId,
            'is_test_match': match.isTestMatch,
            'declared_innings': match.declaredInnings,
            'follow_on_enforced': match.followOnEnforced,
            'first_innings_target_override': match.firstInningsTargetOverride,
            'is_demo': match.isDemo,
            'created_at': match.createdAt.millisecondsSinceEpoch,
          });
        } else {
          await client.from('matches').update({
            'team_a_players': match.teamAPlayers,
            'team_b_players': match.teamBPlayers,
            'declared_innings': match.declaredInnings,
            'follow_on_enforced': match.followOnEnforced,
          }).eq('id', match.id);
        }
      }

      final payload = unsyncedRows.map((row) {
        final copy = Map<String, Object?>.from(row);
        copy.remove('synced');
        copy['owner_id'] = userId;
        copy['is_wicket'] = (row['is_wicket'] as int?) == 1;
        copy['voided'] = (row['voided'] as int?) == 1;
        return copy;
      }).toList();

      await client.from('ball_events').upsert(payload, onConflict: 'id');

      final batch = db.batch();
      for (final row in unsyncedRows) {
        batch.update(
          'ball_events',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      await batch.commit(noResult: true);
      debugPrint('[Crease Sync] Synced ${unsyncedRows.length} ball events for match $matchId');
      return unsyncedRows.length;
    } catch (e) {
      debugPrint('[Crease Sync] Upsert failed for match $matchId: $e');
      return 0;
    }
  }
}

