import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';

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
      version: 2,
      onCreate: (db, version) async {
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
      },
    );
    return _db!;
  }

  Future<List<MatchConfig>> listMatches() async {
    final db = await database;
    final rows = await db.query('matches', orderBy: 'created_at DESC');
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

  /// Idempotent sync of unsynced ball events to Supabase when configured.
  /// Returns the number of events synced (0 if offline or Supabase not configured).
  Future<int> syncPendingToSupabase(String matchId) async {
    SupabaseClient? client;
    try {
      client = Supabase.instance.client;
    } catch (_) {
      return 0;
    }

    final db = await database;
    final unsyncedRows = await db.query(
      'ball_events',
      where: 'match_id = ? AND synced = 0',
      whereArgs: [matchId],
      orderBy: 'sequence_number ASC',
    );
    if (unsyncedRows.isEmpty) return 0;

    try {
      final payload = unsyncedRows.map((row) {
        final copy = Map<String, Object?>.from(row);
        copy.remove('synced');
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
      return unsyncedRows.length;
    } catch (_) {
      // Offline or remote table not yet provisioned; events stay safe locally.
      return 0;
    }
  }
}

