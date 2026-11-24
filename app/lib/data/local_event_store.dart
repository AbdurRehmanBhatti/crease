import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/cricket_engine.dart';
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
      version: 12,
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
            location TEXT,
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
            location TEXT,
            start_date INTEGER,
            end_date INTEGER,
            overs_limit INTEGER NOT NULL,
            players_per_side INTEGER NOT NULL DEFAULT 11,
            format_label TEXT NOT NULL,
            team_rosters TEXT NOT NULL DEFAULT '{}',
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
          CREATE TABLE matches (
            id TEXT PRIMARY KEY,
            team_a TEXT NOT NULL,
            team_b TEXT NOT NULL,
            team_a_id TEXT,
            team_b_id TEXT,
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
            tournament_stage TEXT,
            fixture_index INTEGER,
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
        await _createPerformanceIndexes(db);
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
        if (oldVersion < 9) {
          await db.execute(
            "ALTER TABLE tournaments ADD COLUMN structure TEXT NOT NULL DEFAULT 'open'",
          );
          await db.execute(
            'ALTER TABLE tournaments ADD COLUMN rounds_per_pair INTEGER NOT NULL DEFAULT 1',
          );
          await db.execute(
            'ALTER TABLE tournaments ADD COLUMN knockout_qualifiers INTEGER NOT NULL DEFAULT 2',
          );
          await db.execute(
            'ALTER TABLE matches ADD COLUMN tournament_stage TEXT',
          );
          await db.execute(
            'ALTER TABLE matches ADD COLUMN fixture_index INTEGER',
          );
        }
        if (oldVersion < 10) {
          await _createPerformanceIndexes(db);
        }
        if (oldVersion < 11) {
          await db.execute('ALTER TABLE teams ADD COLUMN location TEXT');
          await db.execute('ALTER TABLE tournaments ADD COLUMN location TEXT');
          await db.execute(
            'ALTER TABLE tournaments ADD COLUMN start_date INTEGER',
          );
          await db.execute(
            'ALTER TABLE tournaments ADD COLUMN end_date INTEGER',
          );
        }
        if (oldVersion < 12) {
          await db.execute('ALTER TABLE matches ADD COLUMN team_a_id TEXT');
          await db.execute('ALTER TABLE matches ADD COLUMN team_b_id TEXT');
        }
      },
    );
    return _db!;
  }

  Future<void> _createPerformanceIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_matches_created_at ON matches (created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_matches_tournament_fixture ON matches (tournament_id, fixture_index)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_matches_teams ON matches (team_a, team_b)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tournaments_created_at ON tournaments (created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_teams_my_created ON teams (is_my_team DESC, created_at DESC)',
    );
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
          try {
            await Supabase.instance.client
                .from('team_members')
                .update({'avatar_url': profile.avatarUrl})
                .eq('user_id', auth.currentUser!.id);
          } catch (_) {}
          await _syncOwnerTeamMemberships(profile);
        }
      } catch (_) {}
    }
  }

  /// Auto-links the signed-in team owner into `public.team_members` for any
  /// owned team whose roster includes [profile.linkedPlayerName], so the owner
  /// receives the verified Linked badge, publishes their avatar to teammates
  /// and public viewers, and reserves their name against invite-code claims.
  Future<void> _syncOwnerTeamMemberships(
    UserProfile profile, {
    TeamProfile? onlyTeam,
  }) async {
    final linked = profile.linkedPlayerName?.trim();
    if (linked == null || linked.isEmpty) return;
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;
      final teams = onlyTeam != null ? [onlyTeam] : await listTeams();
      final linkedLower = linked.toLowerCase();
      for (final team in teams) {
        if (!team.isOwner) continue;
        String? matchedPlayer;
        for (final p in team.players) {
          if (p.trim().toLowerCase() == linkedLower) {
            matchedPlayer = p.trim();
            break;
          }
        }
        if (matchedPlayer == null) continue;
        try {
          await client.from('team_members').upsert(
            {
              'team_id': team.id,
              'user_id': uid,
              'player_name': matchedPlayer,
              'role': 'captain',
              'avatar_url': profile.avatarUrl,
              'joined_at': DateTime.now().millisecondsSinceEpoch,
            },
            onConflict: 'team_id,user_id',
          );
        } catch (_) {}
      }
    } catch (_) {}
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

  /// Monotonically incremented whenever account-level local data is wiped or
  /// restored from cloud so screens like HomeScreen know when to do a full reload.
  int accountDataVersion = 0;

  /// Clears user-specific local teams, tournaments, matches, and profile name
  /// on Sign Out (keeping only the user's theme preference).
  Future<void> clearLocalUserDataOnSignOut() async {
    final db = await database;
    final current = await getUserProfile();
    await db.delete('teams');
    await db.delete('tournaments');
    await db.delete('ball_events');
    await db.delete('matches');
    await db.delete(
      'app_settings',
      where: 'key LIKE ?',
      whereArgs: ['tournament_ko_unlocked_%'],
    );
    await saveUserProfile(
      UserProfile(themeMode: current.themeMode),
      syncCloud: false,
    );
    accountDataVersion++;
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

  /// Deletes an owned saved team locally and from Supabase.
  /// Past matches, scorecards, and player career stats are preserved.
  Future<void> deleteTeam(String teamId) async {
    final db = await database;
    await db.delete('teams', where: 'id = ?', whereArgs: [teamId]);
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid != null) {
        await client
            .from('teams')
            .delete()
            .eq('id', teamId)
            .eq('owner_id', uid);
      }
    } catch (e) {
      debugPrint('[Crease Sync] Team delete failed: $e');
    }
  }

  /// Leaves a joined (non-owned) team locally and removes the user's
  /// membership row in Supabase without deleting the owner's team.
  Future<void> leaveTeam(String teamId) async {
    final db = await database;
    await db.delete('teams', where: 'id = ?', whereArgs: [teamId]);
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid != null) {
        await client
            .from('team_members')
            .delete()
            .eq('team_id', teamId)
            .eq('user_id', uid);
      }
    } catch (e) {
      debugPrint('[Crease Sync] Team leave failed: $e');
    }
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
          'location': team.location,
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
      if (team.isOwner) {
        await _syncOwnerTeamMemberships(
          await getUserProfile(),
          onlyTeam: team,
        );
      }
    } catch (e) {
      debugPrint('[Crease Sync] Team upsert failed: $e');
    }
  }

  static final _placeholderPlayerPattern =
      RegExp(r'^(batter|bowler|opener)\s*\d+$', caseSensitive: false);

  /// True for auto-generated placeholder names like "Batter 1", "Bowler 1", "Opener 2".
  static bool isPlaceholderPlayerName(String name) =>
      _placeholderPlayerPattern.hasMatch(name.trim());

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
        if (trimmed.isEmpty || isPlaceholderPlayerName(trimmed)) continue;
        if (!list.any((e) => e.toLowerCase() == trimmed.toLowerCase())) {
          list.add(trimmed);
        }
      }
    }

    final savedTeams = await listTeams();
    final savedNameById = <String, String>{};
    for (final t in savedTeams) {
      savedNameById[t.id] = t.name;
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
      // Skip remote/public club sides (non-null teamId not in savedTeams) so
      // disambiguated match labels like "Bhatti xi (2)" never appear as fake
      // local saved teams in Quick Match.
      if (m.teamAId == null) {
        if (!m.teamA.trim().endsWith('(2)')) {
          merge(m.teamA, m.teamAPlayers);
        }
      } else if (savedNameById.containsKey(m.teamAId)) {
        merge(savedNameById[m.teamAId]!, m.teamAPlayers);
      }
      if (m.teamBId == null) {
        if (!m.teamB.trim().endsWith('(2)')) {
          merge(m.teamB, m.teamBPlayers);
        }
      } else if (savedNameById.containsKey(m.teamBId)) {
        merge(savedNameById[m.teamBId]!, m.teamBPlayers);
      }
    }

    return rosters;
  }

  /// On-demand, column-only cloud search across public Crease teams.
  /// Returns an empty list when offline or when [query] is shorter than 2 chars.
  Future<List<({String id, String name, String? location, List<String> players})>>
      searchPublicTeams(
    String query, {
    int limit = 15,
    Set<String> excludeIds = const {},
    bool dedupeByName = true,
  }) async {
    final clean = query.trim();
    if (clean.length < 2) return const [];
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('teams')
          .select('id, name, location, players')
          .ilike('name', '%$clean%')
          .order('created_at', ascending: false)
          .limit(limit);
      final results =
          <({String id, String name, String? location, List<String> players})>[];
      final seenLower = <String>{};
      for (final raw in (rows as List)) {
        final map = raw as Map;
        final id = (map['id'] as String?) ?? '';
        final name = (map['name'] as String?)?.trim() ?? '';
        if (name.isEmpty || excludeIds.contains(id)) continue;
        if (dedupeByName && !seenLower.add(name.toLowerCase())) continue;
        final rawLoc = (map['location'] as String?)?.trim();
        final location = (rawLoc != null && rawLoc.isNotEmpty) ? rawLoc : null;
        final rawPlayers = map['players'];
        final players = <String>[];
        if (rawPlayers is List) {
          for (final p in rawPlayers) {
            final s = p.toString().trim();
            if (s.isNotEmpty && !isPlaceholderPlayerName(s)) {
              players.add(s);
            }
          }
        }
        results.add((id: id, name: name, location: location, players: players));
      }
      return results;
    } catch (_) {
      // Offline or Supabase unavailable — degrade silently to local teams.
      return const [];
    }
  }

  /// Fetches a single public team's full profile (including player roles/designations)
  /// for read-only viewing from the Crease directory.
  Future<TeamProfile?> fetchPublicTeamProfile(String teamId) async {
    try {
      final row = await Supabase.instance.client
          .from('teams')
          .select(_teamSelectCols)
          .eq('id', teamId)
          .maybeSingle();
      if (row == null) return null;
      return TeamProfile.fromMap(Map<String, Object?>.from(row));
    } catch (_) {
      return null;
    }
  }

  /// Searches public synced matches on Supabase by team name (case-insensitive).
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
      final client = Supabase.instance.client;
      final safe = clean.replaceAll(',', ' ');
      final rows = await client
          .from('matches')
          .select('id, team_a, team_b, format_label, created_at')
          .eq('is_demo', false)
          .or('team_a.ilike.%$safe%,team_b.ilike.%$safe%')
          .order('created_at', ascending: false)
          .limit(limit);
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

  /// Searches public synced tournaments on Supabase by name or venue (case-insensitive).
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
      final client = Supabase.instance.client;
      final safe = clean.replaceAll(',', ' ');
      final rows = await client
          .from('tournaments')
          .select(
            'id, name, location, start_date, end_date, format_label, team_rosters',
          )
          .or('name.ilike.%$safe%,location.ilike.%$safe%')
          .order('created_at', ascending: false)
          .limit(limit);
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
        final rosters = m['team_rosters'];
        final count = rosters is Map ? rosters.length : 0;
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

  /// Searches players across public Crease teams by player name (case-insensitive).
  Future<
      List<
          ({
            String playerName,
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
        String playerName,
        String teamId,
        String teamName,
        String? teamLocation,
      })>[];
      if (rows is List) {
        for (final raw in rows) {
          final m = raw as Map;
          final playerName = (m['player_name'] as String?)?.trim() ?? '';
          final teamId = (m['team_id'] as String?) ?? '';
          final teamName = (m['team_name'] as String?)?.trim() ?? '';
          if (playerName.isEmpty ||
              teamId.isEmpty ||
              excludeTeamIds.contains(teamId)) {
            continue;
          }
          final rawLoc = (m['team_location'] as String?)?.trim();
          out.add((
            playerName: playerName,
            teamId: teamId,
            teamName: teamName,
            teamLocation: (rawLoc != null && rawLoc.isNotEmpty) ? rawLoc : null,
          ));
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
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
          'location': t.location,
          'start_date': t.startDate?.millisecondsSinceEpoch,
          'end_date': t.endDate?.millisecondsSinceEpoch,
          'overs_limit': t.oversLimit,
          'players_per_side': t.playersPerSide,
          'format_label': t.formatLabel,
          'team_rosters': t.teamRosters,
          'points_for_win': t.pointsForWin,
          'points_for_tie': t.pointsForTie,
          'structure': t.structure.name,
          'rounds_per_pair': t.roundsPerPair,
          'knockout_qualifiers': t.knockoutQualifiers,
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

  /// Fetches a public tournament and all of its synced matches purely in memory
  /// (never writes another user's tournament or matches into local SQLite).
  Future<({Tournament tournament, List<DerivedMatchState> matches, bool isOwner})?>
      fetchPublicTournamentSnapshot(String tournamentId) async {
    try {
      final client = Supabase.instance.client;
      final tRow = await client
          .from('tournaments')
          .select('owner_id, $_tournamentSelectCols')
          .eq('id', tournamentId)
          .maybeSingle();
      if (tRow == null) return null;
      final uid = client.auth.currentUser?.id;
      final isOwner = uid != null && (tRow['owner_id'] as String?) == uid;
      final tournament =
          Tournament.fromMap(Map<String, Object?>.from(tRow));
      final matchRows = await client
          .from('matches')
          .select(_matchSelectCols)
          .eq('tournament_id', tournamentId)
          .order('created_at', ascending: false);
      final configs = (matchRows as List)
          .map((r) => MatchConfig.fromMap(Map<String, Object?>.from(r as Map)))
          .toList();
      final matchIds = configs.map((c) => c.id).toList();
      final eventsByMatch = <String, List<BallEvent>>{};
      if (matchIds.isNotEmpty) {
        final evRows = await client
            .from('ball_events')
            .select(_ballEventSelectCols)
            .inFilter('match_id', matchIds)
            .order('sequence_number', ascending: true);
        for (final r in (evRows as List)) {
          final ev = BallEvent.fromMap(Map<String, Object?>.from(r as Map));
          eventsByMatch.putIfAbsent(ev.matchId, () => <BallEvent>[]).add(ev);
        }
      }
      final derived = [
        for (final cfg in configs)
          CricketEngine.derive(cfg, eventsByMatch[cfg.id] ?? const []),
      ];
      return (tournament: tournament, matches: derived, isOwner: isOwner);
    } catch (e) {
      debugPrint('[Crease Sync] fetchPublicTournamentSnapshot failed: $e');
      return null;
    }
  }

  /// Pulls a public tournament and all of its synced matches from Supabase into
  /// local SQLite (used when opening a shared tournament link in the app).
  Future<bool> pullRemoteTournamentToLocal(String tournamentId) async {
    try {
      final client = Supabase.instance.client;
      final tRow = await client
          .from('tournaments')
          .select(_tournamentSelectCols)
          .eq('id', tournamentId)
          .maybeSingle();
      if (tRow == null) return false;
      final tournament =
          Tournament.fromMap(Map<String, Object?>.from(tRow));
      final db = await database;
      await db.insert(
        'tournaments',
        tournament.copyWith(synced: true).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final matchRows = await client
          .from('matches')
          .select('id')
          .eq('tournament_id', tournamentId);
      for (final r in (matchRows as List)) {
        final mid = (r as Map)['id'] as String?;
        if (mid != null && mid.isNotEmpty) {
          await pullRemoteMatchToLocal(mid);
        }
      }
      return true;
    } catch (e) {
      debugPrint('[Crease Sync] pullRemoteTournamentToLocal failed: $e');
      return false;
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
    if (trimmed.isEmpty || isPlaceholderPlayerName(trimmed)) return null;
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

  Future<bool> isTournamentKnockoutsUnlockedEarly(String tournamentId) async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['tournament_unlocked_early_$tournamentId'],
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['value'] == '1';
  }

  Future<void> setTournamentKnockoutsUnlockedEarly(
    String tournamentId,
    bool unlocked,
  ) async {
    final db = await database;
    final key = 'tournament_unlocked_early_$tournamentId';
    if (unlocked) {
      await db.insert(
        'app_settings',
        {'key': key, 'value': '1'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
    }
  }

  /// Deletes [tournamentId] locally and in Supabase while preserving played
  /// matches and career stats (mirrors Postgres ON DELETE SET NULL).
  Future<void> deleteTournament(String tournamentId) async {
    final db = await database;
    await db.update(
      'matches',
      {
        'tournament_id': null,
        'tournament_stage': null,
        'fixture_index': null,
      },
      where: 'tournament_id = ?',
      whereArgs: [tournamentId],
    );
    await db.delete(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['tournament_unlocked_early_$tournamentId'],
    );
    await db.delete('tournaments', where: 'id = ?', whereArgs: [tournamentId]);
    try {
      await Supabase.instance.client
          .from('tournaments')
          .delete()
          .eq('id', tournamentId);
    } catch (_) {}
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

  static const _teamSelectCols =
      'id, owner_id, name, location, is_my_team, players, player_meta, created_at';
  static const _tournamentSelectCols =
      'id, name, location, start_date, end_date, overs_limit, players_per_side, '
      'format_label, team_rosters, points_for_win, points_for_tie, structure, '
      'rounds_per_pair, knockout_qualifiers, created_at';
  static const _matchSelectCols =
      'id, team_a, team_b, team_a_id, team_b_id, overs_limit, players_per_side, format_label, '
      'batting_first_team, opening_striker_1, opening_non_striker_1, '
      'opening_bowler_1, opening_striker_2, opening_non_striker_2, '
      'opening_bowler_2, team_a_players, team_b_players, tournament_id, '
      'tournament_stage, fixture_index, is_test_match, declared_innings, '
      'follow_on_enforced, first_innings_target_override, is_demo, created_at';
  static const _ballEventSelectCols =
      'id, match_id, innings_number, sequence_number, striker, non_striker, '
      'bowler, runs_off_bat, extra_type, extra_runs, is_wicket, wicket_type, '
      'dismissed_batter, fielder, next_batter, voided, created_at';

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
          .select(_matchSelectCols)
          .eq('id', matchId)
          .maybeSingle();
      if (matchRow == null) return null;

      final eventRows = await client
          .from('ball_events')
          .select(_ballEventSelectCols)
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
        'team_a_id': match.teamAId,
        'team_b_id': match.teamBId,
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
        'tournament_stage': match.tournamentStage,
        'fixture_index': match.fixtureIndex,
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

  /// Returns lowercase player names mapped to their public avatar URL for [teamId].
  Future<Map<String, String>> fetchTeamMemberAvatars(String teamId) async {
    try {
      final rows = await Supabase.instance.client
          .from('team_members')
          .select('player_name, avatar_url')
          .eq('team_id', teamId);
      final out = <String, String>{};
      for (final raw in (rows as List)) {
        final m = raw as Map;
        final name = (m['player_name'] as String?)?.trim().toLowerCase() ?? '';
        final url = (m['avatar_url'] as String?)?.trim() ?? '';
        if (name.isNotEmpty && url.isNotEmpty) {
          out[name] = url;
        }
      }
      return out;
    } catch (_) {
      return const <String, String>{};
    }
  }

  /// Fetches a linked player's public avatar URL (if any) from `team_members`.
  Future<String?> fetchPublicPlayerAvatar(String playerName) async {
    final clean = playerName.trim();
    if (clean.isEmpty) return null;
    try {
      final rows = await Supabase.instance.client
          .from('team_members')
          .select('avatar_url')
          .ilike('player_name', clean)
          .not('avatar_url', 'is', null)
          .limit(1);
      if (rows.isNotEmpty) {
        final url = ((rows.first as Map)['avatar_url'] as String?)?.trim();
        if (url != null && url.isNotEmpty) return url;
      }
      return null;
    } catch (_) {
      return null;
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
      final ownedTeams = await client
          .from('teams')
          .select(_teamSelectCols)
          .eq('owner_id', uid);
      for (final row in (ownedTeams as List)) {
        final team = TeamProfile.fromMap(Map<String, Object?>.from(row as Map));
        await db.insert(
          'teams',
          team.copyWith(synced: true).toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
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
              .select(_teamSelectCols)
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
          }
        }
      }

      // 2b. Owned tournaments
      final restoredTournamentIds = <String>{};
      final ownedTournaments = await client
          .from('tournaments')
          .select(_tournamentSelectCols)
          .eq('owner_id', uid);
      for (final row in (ownedTournaments as List)) {
        final tournament =
            Tournament.fromMap(Map<String, Object?>.from(row as Map));
        await db.insert(
          'tournaments',
          tournament.copyWith(synced: true).toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        restoredTournamentIds.add(tournament.id);
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

      await _syncOwnerTeamMemberships(await getUserProfile());

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

      // 4. Restore any tournaments referenced by restored matches (e.g. co-scored)
      final localTournamentRefRows = await db.rawQuery(
        'SELECT DISTINCT tournament_id FROM matches WHERE tournament_id IS NOT NULL',
      );
      for (final r in localTournamentRefRows) {
        final tid = r['tournament_id'] as String?;
        if (tid == null ||
            tid.isEmpty ||
            restoredTournamentIds.contains(tid)) {
          continue;
        }
        final tRow = await client
            .from('tournaments')
            .select(_tournamentSelectCols)
            .eq('id', tid)
            .maybeSingle();
        if (tRow != null) {
          final tournament =
              Tournament.fromMap(Map<String, Object?>.from(tRow));
          await db.insert(
            'tournaments',
            tournament.copyWith(synced: true).toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          restoredTournamentIds.add(tid);
        }
      }
    } catch (e) {
      debugPrint('[Crease Sync] restoreAccountDataFromCloud failed: $e');
    }
    accountDataVersion++;
    return restoredMatches;
  }

  /// Transfers ownership of any local anonymous-guest matches, teams, and
  /// tournaments on this device to the currently signed-in account, smart-merges
  /// any guest team that shares a name with an existing owned team, and uploads
  /// any offline-only guest records.
  Future<({int matchesSaved, int teamsSaved, int tournamentsSaved})>
      claimGuestDataForSignedInUser({String? previousGuestUid}) async {
    var matchesSaved = 0;
    var teamsSaved = 0;
    var tournamentsSaved = 0;

    final matches = (await listMatches()).where((m) => !m.isDemo).toList();
    final teams = await listTeams();
    final tournaments = await listTournaments();

    if (matches.isEmpty && teams.isEmpty && tournaments.isEmpty) {
      return (matchesSaved: 0, teamsSaved: 0, tournamentsSaved: 0);
    }

    final db = await database;
    final removedLocalTeamIds = <String>{};

    try {
      final client = Supabase.instance.client;
      final newUid = client.auth.currentUser?.id;
      if (newUid != null &&
          previousGuestUid != null &&
          previousGuestUid.isNotEmpty &&
          previousGuestUid != newUid) {
        final res = await client.rpc(
          'claim_guest_data',
          params: {
            'p_guest_id': previousGuestUid,
            'p_match_ids': matches.map((m) => m.id).toList(),
            'p_team_ids': teams.map((t) => t.id).toList(),
            'p_tournament_ids': tournaments.map((t) => t.id).toList(),
          },
        );
        if (res is Map) {
          matchesSaved = (res['matches_claimed'] as num?)?.toInt() ?? 0;
          teamsSaved = (res['teams_claimed'] as num?)?.toInt() ?? 0;
          tournamentsSaved = (res['tournaments_claimed'] as num?)?.toInt() ?? 0;
          final mergedIds = res['merged_team_ids'];
          if (mergedIds is List) {
            for (final rawId in mergedIds) {
              final id = rawId.toString();
              if (id.isNotEmpty) {
                await client
                    .from('teams')
                    .delete()
                    .eq('id', id)
                    .eq('owner_id', newUid);
                await db.delete('teams', where: 'id = ?', whereArgs: [id]);
                removedLocalTeamIds.add(id);
              }
            }
          }
        }
      }

      // Handle offline-only guest teams whose name collides with an already-owned cloud team.
      final remainingUnsyncedTeams = teams
          .where((t) => !t.synced && !removedLocalTeamIds.contains(t.id))
          .toList();
      if (newUid != null && remainingUnsyncedTeams.isNotEmpty) {
        final ownedCloudRows = await client
            .from('teams')
            .select('id, name, players')
            .eq('owner_id', newUid);
        final ownedByLower = <String, ({String id, List<String> players})>{};
        for (final row in (ownedCloudRows as List)) {
          final m = Map<String, Object?>.from(row as Map);
          final name = (m['name'] as String? ?? '').trim();
          final id = m['id'] as String? ?? '';
          if (name.isEmpty || id.isEmpty) continue;
          final rawPlayers = m['players'];
          final players = rawPlayers is List
              ? rawPlayers.map((e) => e.toString()).toList()
              : <String>[];
          ownedByLower[name.toLowerCase()] = (id: id, players: players);
        }

        for (final guestTeam in remainingUnsyncedTeams) {
          final existing = ownedByLower[guestTeam.name.trim().toLowerCase()];
          if (existing == null || existing.id == guestTeam.id) continue;
          final merged = List<String>.from(existing.players);
          final seen = merged.map((p) => p.trim().toLowerCase()).toSet();
          var changed = false;
          for (final p in guestTeam.players) {
            final clean = p.trim();
            if (clean.isEmpty || seen.contains(clean.toLowerCase())) continue;
            merged.add(clean);
            seen.add(clean.toLowerCase());
            changed = true;
          }
          if (changed) {
            await client
                .from('teams')
                .update({'players': merged})
                .eq('id', existing.id)
                .eq('owner_id', newUid);
          }
          await db.delete('teams', where: 'id = ?', whereArgs: [guestTeam.id]);
          removedLocalTeamIds.add(guestTeam.id);
        }
      }
    } catch (e) {
      debugPrint('[Crease Sync] claim_guest_data RPC failed: $e');
    }

    // Also upload any non-colliding offline-only guest teams, tournaments, and matches.
    final offlineSyncedEvents = await syncAllPendingToSupabase();
    if (offlineSyncedEvents > 0 && matchesSaved == 0) {
      matchesSaved = matches.length;
    }

    return (
      matchesSaved: matchesSaved,
      teamsSaved: teamsSaved,
      tournamentsSaved: tournamentsSaved,
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
            'team_a_id': match.teamAId,
            'team_b_id': match.teamBId,
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
            'tournament_stage': match.tournamentStage,
            'fixture_index': match.fixtureIndex,
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

