import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';
import '../domain/team_profile.dart';
import '../domain/tournament_engine.dart';

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
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE teams (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            is_my_team INTEGER NOT NULL DEFAULT 0,
            players TEXT NOT NULL DEFAULT '[]',
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
      },
    );
    return _db!;
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
      final match = await getMatch(matchId);
      if (match != null) {
        if (match.tournamentId != null) {
          await syncTournamentToSupabase(match.tournamentId!);
        }
        await client.from('matches').upsert(
          {
            'id': match.id,
            'owner_id': userId,
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
          },
          onConflict: 'id',
        );
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

