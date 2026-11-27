import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/security_guards.dart';
import '../domain/cricket_engine.dart';
import '../domain/guest_merge.dart';
import '../domain/guest_sync_guards.dart';
import '../domain/models.dart' as models;
import '../domain/models.dart';
import '../domain/roster_sync_planner.dart';
import '../domain/stats_engine.dart';
import '../domain/team_profile.dart';
import '../domain/tournament_engine.dart';
import '../domain/user_profile.dart';

part 'store_players_teams.dart';
part 'store_matches_balls.dart';
part 'store_tournaments.dart';
part 'store_sync_auth.dart';

/// Offline-first SQLite v15 event store for Crease (Strict 3NF).
/// Every entity uses a client-generated UUIDv4 so offline Guest Mode works
/// with zero connectivity and syncs idempotently to Supabase.
class LocalEventStore {
  LocalEventStore._();
  static final LocalEventStore instance = LocalEventStore._();

  static const _uuid = Uuid();
  static const _pendingGuestClaimKey = 'pending_guest_claim_uid';

  static final ValueNotifier<int> accountDataVersion = ValueNotifier<int>(0);

  static void notifyAccountDataChanged() {
    accountDataVersion.value = accountDataVersion.value + 1;
  }

  static bool isPlaceholderPlayerName(String name) =>
      models.isPlaceholderPlayerName(name);

  static const String _teamSelectCols =
      'id, owner_id, name, location, profile_code, logo_url, is_my_team, created_at';
  static const String _playerSelectCols =
      'id, team_id, owner_id, user_id, display_name, role, designation, '
      'member_role, avatar_url, claimed_at, archived, created_at, updated_at';
  static const String _tournamentSelectCols =
      'id, owner_id, name, location, start_date, end_date, overs_limit, '
      'players_per_side, format_label, points_for_win, points_for_tie, '
      'structure, rounds_per_pair, knockout_qualifiers, created_at';
  static const String _tournamentTeamSelectCols =
      'id, tournament_id, team_id, ad_hoc_name, seed_order, created_at';

  Database? _db;

  /// Reactive in-memory directory of all known players & teams.
  /// Updated automatically on every local write or cloud sync.
  final ValueNotifier<PlayerDirectorySnapshot> directoryNotifier =
      ValueNotifier<PlayerDirectorySnapshot>(PlayerDirectorySnapshot.empty);

  PlayerDirectorySnapshot get directory => directoryNotifier.value;

  /// Returns the current Supabase user ID ONLY when signed into a real
  /// (non-anonymous) Crease account. Returns `null` for local-only guests.
  String? get signedInUserId {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null || user.isAnonymous) return null;
      final email = user.email?.trim() ?? '';
      return email.isNotEmpty ? user.id : null;
    } catch (_) {
      return null;
    }
  }

  bool get isSignedInAccount => signedInUserId != null;

  String requireSignedInUserId() {
    final uid = signedInUserId;
    if (uid == null) {
      throw StateError('Sign in required for this action.');
    }
    return uid;
  }

  Future<void> _setPendingGuestClaimUid(Database db, String? guestUid) async {
    final clean = guestUid?.trim();
    if (clean == null || clean.isEmpty) {
      await db.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: [_pendingGuestClaimKey],
      );
      return;
    }
    await db.insert(
      'app_settings',
      {'key': _pendingGuestClaimKey, 'value': clean},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, 'crease_events.db');
    _db = await openDatabase(
      fullPath,
      version: 16,
      onCreate: (db, version) async => _createV15Schema(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 15) {
          // Clean v2 Strict-3NF reset (all tables start fresh with UUID schema).
          await db.execute('DROP TABLE IF EXISTS ball_events');
          await db.execute('DROP TABLE IF EXISTS matches');
          await db.execute('DROP TABLE IF EXISTS tournament_teams');
          await db.execute('DROP TABLE IF EXISTS tournaments');
          await db.execute('DROP TABLE IF EXISTS players');
          await db.execute('DROP TABLE IF EXISTS teams');
          await _createV15Schema(db, keepSettings: true);
        } else if (oldVersion < 16) {
          await db.execute('ALTER TABLE teams ADD COLUMN logo_url TEXT');
        }
      },
    );
    return _db!;
  }

  Future<void> _createV15Schema(
    Database db, {
    bool keepSettings = false,
  }) async {
    if (!keepSettings) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }

    await db.execute('''
      CREATE TABLE teams (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        location TEXT,
        profile_code TEXT,
        logo_url TEXT,
        is_my_team INTEGER NOT NULL DEFAULT 0,
        is_owner INTEGER NOT NULL DEFAULT 1,
        synced INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE players (
        id TEXT PRIMARY KEY,
        team_id TEXT NOT NULL,
        owner_id TEXT,
        user_id TEXT,
        display_name TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT '',
        designation TEXT,
        member_role TEXT NOT NULL DEFAULT 'player',
        avatar_url TEXT,
        claimed_at INTEGER,
        archived INTEGER NOT NULL DEFAULT 0,
        synced INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (team_id) REFERENCES teams (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE tournaments (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        location TEXT,
        start_date INTEGER,
        end_date INTEGER,
        overs_limit INTEGER NOT NULL,
        players_per_side INTEGER NOT NULL DEFAULT 11,
        format_label TEXT NOT NULL,
        points_for_win INTEGER NOT NULL DEFAULT 2,
        points_for_tie INTEGER NOT NULL DEFAULT 1,
        structure TEXT NOT NULL DEFAULT 'open',
        rounds_per_pair INTEGER NOT NULL DEFAULT 1,
        knockout_qualifiers INTEGER NOT NULL DEFAULT 2,
        synced INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE tournament_teams (
        id TEXT PRIMARY KEY,
        tournament_id TEXT NOT NULL,
        team_id TEXT,
        ad_hoc_name TEXT,
        seed_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (tournament_id) REFERENCES tournaments (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE matches (
        id TEXT PRIMARY KEY,
        team_a TEXT NOT NULL,
        team_b TEXT NOT NULL,
        team_a_id TEXT,
        team_b_id TEXT,
        batting_first_side TEXT NOT NULL DEFAULT 'a',
        overs_limit INTEGER NOT NULL,
        players_per_side INTEGER NOT NULL,
        format_label TEXT NOT NULL,
        opening_striker_1_id TEXT,
        opening_non_striker_1_id TEXT,
        opening_bowler_1_id TEXT,
        opening_striker_2_id TEXT,
        opening_non_striker_2_id TEXT,
        opening_bowler_2_id TEXT,
        team_a_player_ids TEXT NOT NULL DEFAULT '[]',
        team_b_player_ids TEXT NOT NULL DEFAULT '[]',
        ad_hoc_players TEXT NOT NULL DEFAULT '{}',
        tournament_id TEXT,
        tournament_stage TEXT,
        fixture_index INTEGER,
        is_test_match INTEGER NOT NULL DEFAULT 0,
        declared_innings TEXT NOT NULL DEFAULT '[]',
        follow_on_enforced INTEGER NOT NULL DEFAULT 0,
        first_innings_target_override INTEGER,
        is_demo INTEGER NOT NULL DEFAULT 0,
        synced INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ball_events (
        id TEXT PRIMARY KEY,
        match_id TEXT NOT NULL,
        innings_number INTEGER NOT NULL,
        sequence_number INTEGER NOT NULL,
        striker_id TEXT NOT NULL,
        non_striker_id TEXT NOT NULL,
        bowler_id TEXT NOT NULL,
        runs_off_bat INTEGER NOT NULL DEFAULT 0,
        extra_type TEXT NOT NULL DEFAULT 'none',
        extra_runs INTEGER NOT NULL DEFAULT 0,
        is_wicket INTEGER NOT NULL DEFAULT 0,
        wicket_type TEXT,
        dismissed_batter_id TEXT,
        fielder_id TEXT,
        next_batter_id TEXT,
        synced INTEGER NOT NULL DEFAULT 0,
        voided INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (match_id) REFERENCES matches (id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_players_team_active ON players (team_id, archived)',
    );
    await db.execute(
      'CREATE INDEX idx_players_user_id ON players (user_id)',
    );
    await db.execute(
      'CREATE INDEX idx_tournament_teams_tid ON tournament_teams (tournament_id, seed_order)',
    );
    await db.execute(
      'CREATE INDEX idx_matches_created_at ON matches (created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_matches_tournament_id ON matches (tournament_id)',
    );
    await db.execute(
      'CREATE INDEX idx_matches_team_ids ON matches (team_a_id, team_b_id)',
    );
    await db.execute(
      'CREATE INDEX idx_ball_events_match ON ball_events (match_id, innings_number, sequence_number)',
    );
    await db.execute(
      'CREATE INDEX idx_ball_events_unsynced ON ball_events (synced) WHERE synced = 0',
    );
  }

  /// Refreshes [directoryNotifier] from local SQLite so all screens have O(1)
  /// access to current player names, linked user IDs, and club names.
  Future<PlayerDirectorySnapshot> refreshDirectory() async {
    final db = await database;
    final teamRows = await db.query('teams', orderBy: 'created_at DESC');
    final playerRows = await db.query('players', orderBy: 'created_at ASC');
    final players = playerRows.map(PlayerProfile.fromMap).toList();
    final teams = teamRows.map((r) => TeamProfile.fromMap(r)).toList();
    final snapshot = PlayerDirectorySnapshot.fromLists(
      players: players,
      teams: teams,
    );
    directoryNotifier.value = snapshot;
    return snapshot;
  }

  /// Derives a [DerivedMatchState] using the current [PlayerDirectorySnapshot].
  DerivedMatchState deriveMatch(
    MatchConfig config,
    List<BallEvent> events, {
    int? forcedInnings,
    String? manualStrikerIdOverride,
    String? manualNonStrikerIdOverride,
    String? manualBowlerIdOverride,
  }) {
    final dir = directory;
    return CricketEngine.derive(
      config,
      events,
      playerNamesById: dir.playerNamesById,
      teamNamesById: dir.teamNamesById,
      forcedInnings: forcedInnings,
      manualStrikerIdOverride: manualStrikerIdOverride,
      manualNonStrikerIdOverride: manualNonStrikerIdOverride,
      manualBowlerIdOverride: manualBowlerIdOverride,
    );
  }

  /// Derives career stats using the current [PlayerDirectorySnapshot].
  List<PlayerCareerStats> deriveStats(
    List<DerivedMatchState> matches, {
    String? tournamentId,
    String? teamId,
    String? teamName,
    bool excludeDemo = false,
    bool excludePlaceholders = true,
  }) {
    final dir = directory;
    return StatsEngine.derive(
      matches,
      tournamentId: tournamentId,
      teamId: teamId,
      teamName: teamName,
      excludeDemo: excludeDemo,
      excludePlaceholders: excludePlaceholders,
      playerNamesById: dir.playerNamesById,
      playerUserIdsById: dir.playerUserIdsById,
    );
  }

  // ── User Profile & Local Settings ─────────────────────────────────────────

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
    bool syncToCloud = true,
  }) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {'key': 'user_profile', 'value': profile.toJson()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final uid = signedInUserId;
    if (uid != null) {
      final avatar = profile.avatarUrl?.trim();
      final displayName = profile.displayName.trim();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await db.update(
        'players',
        {
          'avatar_url': (avatar != null && avatar.isNotEmpty) ? avatar : null,
          'updated_at': nowMs,
          if (displayName.isNotEmpty) 'display_name': displayName,
        },
        where: 'user_id = ?',
        whereArgs: [uid],
      );
      await refreshDirectory();
    }
    if (syncToCloud && uid != null) {
      await db.insert(
        'app_settings',
        {'key': 'user_profile_dirty', 'value': '1'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      unawaited(syncPendingUserProfile());
    }
  }

  /// Syncs any locally saved `UserProfile` changes to Supabase Auth & `players`
  /// in the background, clearing `user_profile_dirty` on success.
  Future<void> syncPendingUserProfile() async {
    if (!isSignedInAccount) return;
    final uid = signedInUserId;
    if (uid == null) return;
    final db = await database;
    final dirty = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['user_profile_dirty'],
      limit: 1,
    );
    if (dirty.isEmpty || dirty.first['value'] != '1') return;

    try {
      final profile = await getUserProfile();
      final client = Supabase.instance.client;
      final avatar = profile.avatarUrl?.trim();
      final displayName = profile.displayName.trim();
      await client.auth.updateUser(
        UserAttributes(
          data: {
            'full_name': displayName,
            'role': profile.role,
            'linked_player_name': profile.linkedPlayerName,
            'avatar_url': avatar,
          },
        ),
      );
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final updatePayload = <String, dynamic>{
        'avatar_url': (avatar != null && avatar.isNotEmpty) ? avatar : null,
        'updated_at': nowMs,
        if (displayName.isNotEmpty) 'display_name': displayName,
      };
      await client.from('players').update(updatePayload).eq('user_id', uid);
      await db.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['user_profile_dirty'],
      );
    } catch (e) {
      if (kDebugMode) debugPrint('syncPendingUserProfile deferred: $e');
    }
  }

  Future<String> uploadProfileAvatar(Uint8List bytes) async {
    final client = Supabase.instance.client;
    final uid = requireSignedInUserId();
    if (!CreaseSecurity.isValidUuid(uid)) {
      throw StateError('Invalid user session.');
    }
    final path = '$uid/avatar.jpg';
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

  Future<String> uploadTeamLogo(String teamId, Uint8List bytes) async {
    if (!CreaseSecurity.isValidUuid(teamId)) {
      throw ArgumentError('Invalid team ID.');
    }
    final client = Supabase.instance.client;
    final uid = requireSignedInUserId();
    if (!CreaseSecurity.isValidUuid(uid)) {
      throw StateError('Invalid user session.');
    }
    final path = '$uid/team_$teamId.jpg';
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

  Future<void> deleteDemoMatches() async {
    final db = await database;
    await db.delete(
      'ball_events',
      where: 'match_id IN (SELECT id FROM matches WHERE is_demo = 1)',
    );
    await db.delete('matches', where: 'is_demo = 1');
  }

  Future<void> clearLocalUserDataOnSignOut() async {
    final db = await database;
    await db.delete('ball_events');
    await db.delete('matches');
    await db.delete('tournament_teams');
    await db.delete('tournaments');
    await db.delete('players');
    await db.delete('teams');
    await _setPendingGuestClaimUid(db, null);

    final current = await getUserProfile();
    await db.insert(
      'app_settings',
      {
        'key': 'user_profile',
        'value': UserProfile(themeMode: current.themeMode).toJson(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    directoryNotifier.value = PlayerDirectorySnapshot.empty;
  }
}
