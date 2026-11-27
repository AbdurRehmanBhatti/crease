import 'package:crease/domain/roster_sync_planner.dart';
import 'package:crease/domain/team_profile.dart';
import 'package:crease/features/profile/profile_screen.dart';
import 'package:crease/features/teams/teams_tab_view.dart';
import 'package:crease/theme/crease_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _teamA = '11111111-1111-4111-8111-111111111111';
const _teamB = '22222222-2222-4222-8222-222222222222';
const _deletedTeam = '33333333-3333-4333-8333-333333333333';
const _ownerUid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _teammateUid = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _p1 = '10000000-0000-4000-8000-000000000001';
const _p2 = '10000000-0000-4000-8000-000000000002';
const _p3 = '10000000-0000-4000-8000-000000000003';
const _p4 = '10000000-0000-4000-8000-000000000004';

PlayerProfile _player({
  required String id,
  String teamId = _teamA,
  String? ownerId = _ownerUid,
  String? userId,
  String displayName = 'Ali',
  String role = 'Batter',
  String? designation,
  String memberRole = 'player',
  String? avatarUrl,
  DateTime? claimedAt,
  bool archived = false,
  bool synced = true,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final ts = createdAt ?? DateTime.fromMillisecondsSinceEpoch(1700000000000);
  return PlayerProfile(
    id: id,
    teamId: teamId,
    ownerId: ownerId,
    userId: userId,
    displayName: displayName,
    role: role,
    designation: designation,
    memberRole: memberRole,
    avatarUrl: avatarUrl,
    claimedAt: claimedAt,
    archived: archived,
    synced: synced,
    createdAt: ts,
    updatedAt: updatedAt ?? ts,
  );
}

Map<String, Object?> _remoteRow(PlayerProfile p) => {
      'id': p.id,
      'team_id': p.teamId,
      'owner_id': p.ownerId,
      'user_id': p.userId,
      'display_name': p.displayName,
      'role': p.role,
      'designation': p.designation,
      'member_role': p.memberRole,
      'avatar_url': p.avatarUrl,
      'claimed_at': p.claimedAt?.millisecondsSinceEpoch,
      'archived': p.archived,
      'created_at': p.createdAt.millisecondsSinceEpoch,
      'updated_at': p.updatedAt.millisecondsSinceEpoch,
    };

void main() {
  group('PlayerProfile.fromMap Realtime JSON payload resilience', () {
    test('parses string-encoded bigint timestamps and string booleans', () {
      final profile = PlayerProfile.fromMap({
        'id': _p1,
        'team_id': _teamA,
        'owner_id': _ownerUid,
        'user_id': _teammateUid,
        'display_name': 'Hamza',
        'role': 'All-rounder',
        'designation': 'VC',
        'member_role': 'player',
        'avatar_url': 'https://ajwqkcblakfojsbyqjqt.supabase.co/storage/v1/object/public/avatars/a.jpg',
        'claimed_at': '1700000050000',
        'archived': 'false',
        'created_at': '1700000000000',
        'updated_at': '1700000060000',
      });

      expect(profile.id, _p1);
      expect(profile.userId, _teammateUid);
      expect(profile.isLinked, isTrue);
      expect(profile.claimedAt?.millisecondsSinceEpoch, 1700000050000);
      expect(profile.createdAt.millisecondsSinceEpoch, 1700000000000);
      expect(profile.updatedAt.millisecondsSinceEpoch, 1700000060000);
      expect(profile.archived, isFalse);

      final archivedStringTrue = PlayerProfile.fromMap({
        'id': _p2,
        'team_id': _teamA,
        'display_name': 'Old Player',
        'archived': 'true',
        'is_claimed': '1',
      });
      expect(archivedStringTrue.archived, isTrue);
      expect(archivedStringTrue.isLinked, isTrue);

      final archivedPgT = PlayerProfile.fromMap({
        'id': _p3,
        'team_id': _teamA,
        'display_name': 'Pg Bool',
        'archived': 't',
      });
      expect(archivedPgT.archived, isTrue);
    });

    test('normalizes whitespace-only user_id, avatar_url, and designation to null', () {
      final profile = PlayerProfile.fromMap({
        'id': _p1,
        'team_id': _teamA,
        'user_id': '   ',
        'display_name': 'Bilal',
        'designation': '  ',
        'avatar_url': '',
        'archived': 0,
      });

      expect(profile.userId, isNull);
      expect(profile.isLinked, isFalse);
      expect(profile.designation, isNull);
      expect(profile.avatarUrl, isNull);
    });
  });

  group('RosterSyncPlanner.buildOwnerUpdatePayload (stale cache safety)', () {
    test('omits user_id, claimed_at, and avatar_url when local player is unclaimed', () {
      final staleLocal = _player(
        id: _p1,
        displayName: 'Zain',
        role: 'Bowler',
        designation: 'C',
        userId: null,
        claimedAt: null,
        avatarUrl: null,
        synced: false,
      );

      final payload = RosterSyncPlanner.buildOwnerUpdatePayload(staleLocal);

      expect(payload.containsKey('user_id'), isFalse);
      expect(payload.containsKey('claimed_at'), isFalse);
      expect(payload.containsKey('avatar_url'), isFalse);
      expect(payload['display_name'], 'Zain');
      expect(payload['role'], 'Bowler');
      expect(payload['designation'], 'C');
      expect(payload['archived'], isFalse);
    });

    test('preserves claim fields when local player is claimed and omits empty avatar', () {
      final claimedAt = DateTime.fromMillisecondsSinceEpoch(1700000099000);
      final claimedLocal = _player(
        id: _p1,
        userId: _teammateUid,
        claimedAt: claimedAt,
        avatarUrl: '   ',
      );

      final payload = RosterSyncPlanner.buildOwnerUpdatePayload(claimedLocal);

      expect(payload['user_id'], _teammateUid);
      expect(payload['claimed_at'], 1700000099000);
      expect(payload.containsKey('avatar_url'), isFalse);
    });

    test('clears designation when player is archived', () {
      final archivedCaptain = _player(
        id: _p1,
        designation: 'C',
        archived: true,
      );

      final payload = RosterSyncPlanner.buildOwnerUpdatePayload(archivedCaptain);
      expect(payload['archived'], isTrue);
      expect(payload['designation'], isNull);
    });
  });

  group('RosterSyncPlanner.planMerge (pull & Realtime edge cases)', () {
    test('inserts a brand-new remote player who joined via invite code', () {
      final newRemote = _player(
        id: _p2,
        displayName: 'Usama',
        userId: _teammateUid,
        claimedAt: DateTime.fromMillisecondsSinceEpoch(1700000100000),
      );

      final actions = RosterSyncPlanner.planMerge(
        validTeamIds: {_teamA},
        localById: {_p1: _player(id: _p1)},
        remoteRows: [_remoteRow(newRemote)],
      );

      expect(actions, hasLength(1));
      expect(actions.single.kind, RosterMergeActionKind.insertOrReplace);
      expect(actions.single.remotePlayer.id, _p2);
      expect(actions.single.remotePlayer.isLinked, isTrue);
      expect(actions.single.remotePlayer.synced, isTrue);
    });

    test('updates synced local player when teammate links email remotely', () {
      final local = _player(id: _p1, displayName: 'Ali', userId: null, synced: true);
      final remoteClaimed = local.copyWith(
        userId: _teammateUid,
        claimedAt: DateTime.fromMillisecondsSinceEpoch(1700000200000),
        avatarUrl: 'https://ajwqkcblakfojsbyqjqt.supabase.co/storage/v1/object/public/avatars/u.jpg',
      );

      final actions = RosterSyncPlanner.planMerge(
        validTeamIds: {_teamA},
        localById: {_p1: local},
        remoteRows: [_remoteRow(remoteClaimed)],
      );

      expect(actions, hasLength(1));
      expect(actions.single.kind, RosterMergeActionKind.insertOrReplace);
      expect(actions.single.remotePlayer.userId, _teammateUid);
      expect(actions.single.remotePlayer.isLinked, isTrue);
    });

    test('updates synced local player when teammate unlinks remotely', () {
      final local = _player(
        id: _p1,
        userId: _teammateUid,
        claimedAt: DateTime.fromMillisecondsSinceEpoch(1700000200000),
        avatarUrl: 'https://ajwqkcblakfojsbyqjqt.supabase.co/storage/v1/object/public/avatars/u.jpg',
        synced: true,
      );
      final remoteUnlinked = local.copyWith(
        clearUserId: true,
        clearClaimedAt: true,
        clearAvatarUrl: true,
      );

      final actions = RosterSyncPlanner.planMerge(
        validTeamIds: {_teamA},
        localById: {_p1: local},
        remoteRows: [_remoteRow(remoteUnlinked)],
      );

      expect(actions, hasLength(1));
      expect(actions.single.kind, RosterMergeActionKind.insertOrReplace);
      expect(actions.single.remotePlayer.userId, isNull);
      expect(actions.single.remotePlayer.isLinked, isFalse);
    });

    test('returns empty actions when synced local player matches remote row (no churn)', () {
      final local = _player(
        id: _p1,
        userId: _teammateUid,
        claimedAt: DateTime.fromMillisecondsSinceEpoch(1700000200000),
        synced: true,
      );

      final actions = RosterSyncPlanner.planMerge(
        validTeamIds: {_teamA},
        localById: {_p1: local},
        remoteRows: [_remoteRow(local)],
      );

      expect(actions, isEmpty);
    });

    test('preserves local unsynced edits while still merging remote claim (patchClaimOnly)', () {
      // Owner edited role & designation offline (`synced: false`)
      final localUnsynced = _player(
        id: _p1,
        displayName: 'Ali',
        role: 'Bowler',
        designation: 'VC',
        userId: null,
        synced: false,
      );
      // Meanwhile teammate claimed the spot remotely (remote still has old role 'Batter')
      final remoteClaimed = _player(
        id: _p1,
        displayName: 'Ali',
        role: 'Batter',
        designation: null,
        userId: _teammateUid,
        claimedAt: DateTime.fromMillisecondsSinceEpoch(1700000300000),
        avatarUrl: 'https://ajwqkcblakfojsbyqjqt.supabase.co/storage/v1/object/public/avatars/ali.jpg',
      );

      final actions = RosterSyncPlanner.planMerge(
        validTeamIds: {_teamA},
        localById: {_p1: localUnsynced},
        remoteRows: [_remoteRow(remoteClaimed)],
      );

      expect(actions, hasLength(1));
      expect(actions.single.kind, RosterMergeActionKind.patchClaimOnly);
      expect(actions.single.remotePlayer.userId, _teammateUid);
      expect(actions.single.remotePlayer.avatarUrl, remoteClaimed.avatarUrl);
    });

    test('does nothing for unsynced local edit when remote claim fields did not change', () {
      final localUnsynced = _player(
        id: _p1,
        role: 'Wicket-keeper',
        designation: 'WK',
        userId: null,
        synced: false,
      );
      final remoteOlderRole = _player(
        id: _p1,
        role: 'Batter',
        designation: null,
        userId: null,
      );

      final actions = RosterSyncPlanner.planMerge(
        validTeamIds: {_teamA},
        localById: {_p1: localUnsynced},
        remoteRows: [_remoteRow(remoteOlderRole)],
      );

      expect(actions, isEmpty);
    });

    test('patches remote unlink onto unsynced local player without wiping local edits', () {
      final localUnsynced = _player(
        id: _p1,
        role: 'All-rounder',
        userId: _teammateUid,
        claimedAt: DateTime.fromMillisecondsSinceEpoch(1700000200000),
        synced: false,
      );
      final remoteUnlinked = _player(
        id: _p1,
        role: 'Batter',
        userId: null,
        claimedAt: null,
      );

      final actions = RosterSyncPlanner.planMerge(
        validTeamIds: {_teamA},
        localById: {_p1: localUnsynced},
        remoteRows: [_remoteRow(remoteUnlinked)],
      );

      expect(actions, hasLength(1));
      expect(actions.single.kind, RosterMergeActionKind.patchClaimOnly);
      expect(actions.single.remotePlayer.userId, isNull);
    });

    test('skips remote rows for deleted/unknown teams and rows with missing id', () {
      final orphan = _player(id: _p3, teamId: _deletedTeam, displayName: 'Ghost');

      final actions = RosterSyncPlanner.planMerge(
        validTeamIds: {_teamA},
        localById: const {},
        remoteRows: [
          _remoteRow(orphan),
          {'id': '', 'team_id': _teamA, 'display_name': 'Blank ID'},
          {'team_id': _teamA, 'display_name': 'Missing ID'},
        ],
      );

      expect(actions, isEmpty);
    });

    test('applies remote archive and handles batched multi-team merge', () {
      final teamAPlayer = _player(id: _p1, teamId: _teamA, synced: true);
      final teamBPlayer = _player(id: _p4, teamId: _teamB, displayName: 'Saad', synced: true);

      final remoteArchivedA = teamAPlayer.copyWith(archived: true, clearDesignation: true);
      final remoteClaimedB = teamBPlayer.copyWith(
        userId: _teammateUid,
        claimedAt: DateTime.fromMillisecondsSinceEpoch(1700000400000),
      );
      final orphan = _player(id: _p3, teamId: _deletedTeam);

      final actions = RosterSyncPlanner.planMerge(
        validTeamIds: {_teamA, _teamB},
        localById: {_p1: teamAPlayer, _p4: teamBPlayer},
        remoteRows: [
          _remoteRow(remoteArchivedA),
          _remoteRow(remoteClaimedB),
          _remoteRow(orphan),
        ],
      );

      expect(actions, hasLength(2));
      expect(actions.map((a) => a.remotePlayer.id), containsAll([_p1, _p4]));
      final aAction = actions.firstWhere((a) => a.remotePlayer.id == _p1);
      final bAction = actions.firstWhere((a) => a.remotePlayer.id == _p4);
      expect(aAction.remotePlayer.archived, isTrue);
      expect(bAction.remotePlayer.isLinked, isTrue);
    });
  });

  group('ResumeSyncThrottle (app-resume cooldown)', () {
    test('allows first sync, blocks within cooldown, and allows after cooldown elapses', () {
      final throttle = ResumeSyncThrottle(cooldown: const Duration(seconds: 5));
      final t0 = DateTime(2026, 11, 27, 12, 0, 0);

      expect(throttle.shouldSync(now: t0), isTrue);

      throttle.markSynced(now: t0);
      expect(throttle.shouldSync(now: t0.add(const Duration(seconds: 1))), isFalse);
      expect(throttle.shouldSync(now: t0.add(const Duration(seconds: 4, milliseconds: 999))), isFalse);
      expect(throttle.shouldSync(now: t0.add(const Duration(seconds: 5))), isTrue);
      expect(throttle.shouldSync(now: t0.add(const Duration(seconds: 12))), isTrue);
    });
  });

  group('TeamDetailScreen widget rendering', () {
    testWidgets('shows RefreshIndicator and renders Linked + verified badge for claimed players', (tester) async {
      final team = TeamProfile(
        id: _teamA,
        name: 'Lahore Lions',
        isMyTeam: true,
        isOwner: true,
        synced: true,
        createdAt: DateTime(2026, 11, 27),
        squad: [
          _player(
            id: _p1,
            displayName: 'Babar',
            role: 'Batter',
            designation: 'C',
            userId: _teammateUid,
            claimedAt: DateTime(2026, 11, 27),
          ),
          _player(
            id: _p2,
            displayName: 'Rizwan',
            role: 'Wicket-keeper',
            userId: null,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: CreaseTheme.light(),
          home: TeamDetailScreen(
            teamName: team.name,
            savedProfile: team,
            initialRoster: team.players,
            matches: const [],
            readOnlyPublic: true,
          ),
        ),
      );
      await tester.pump();

      // Overview tab has RefreshIndicator
      expect(find.byType(RefreshIndicator), findsOneWidget);

      // Switch to Players tab
      await tester.tap(find.text('Players'));
      await tester.pumpAndSettle();

      // Players tab also has RefreshIndicator
      expect(find.byType(RefreshIndicator), findsOneWidget);

      // Claimed player shows Linked subtitle & verified badge; unclaimed does not
      expect(find.text('Babar'), findsOneWidget);
      expect(find.text('Rizwan'), findsOneWidget);
      expect(find.text('Batter · Linked'), findsOneWidget);
      expect(find.text('Wicket-keeper'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    });
  });

  group('Multi-team player linking (RosterSyncTeamLinking + TeamSpotLinkerSection)', () {
    test('includes non-pinned teams, preserves distinct UUIDs for same names, and filters other-claimed/archived players', () {
      final teamA = TeamProfile(
        id: _teamA,
        name: 'Lahore Lions',
        isMyTeam: true,
        isOwner: true,
        createdAt: DateTime(2026, 11, 27),
        squad: [
          _player(id: _p1, teamId: _teamA, displayName: 'Abdur', userId: _ownerUid),
          _player(id: _p2, teamId: _teamA, displayName: 'Bilal', userId: _teammateUid), // claimed by someone else
        ],
      );
      final teamB = TeamProfile(
        id: _teamB,
        name: 'Sunday XI',
        isMyTeam: false, // non-pinned team must still appear!
        isOwner: true,
        createdAt: DateTime(2026, 11, 27),
        squad: [
          _player(id: _p3, teamId: _teamB, displayName: 'Abdur', userId: null), // same name, distinct UUID
          _player(id: _p4, teamId: _teamB, displayName: 'Archived Guy', archived: true),
        ],
      );

      final options = RosterSyncTeamLinking.buildTeamLinkOptions(
        teams: [teamB, teamA],
        currentUserId: _ownerUid,
      );

      expect(options, hasLength(2));
      // Pinned My Team sorts first
      expect(options[0].team.id, _teamA);
      expect(options[0].linkedPlayerId, _p1);
      expect(options[0].eligiblePlayers.map((p) => p.id), [_p1]); // Bilal filtered out

      expect(options[1].team.id, _teamB);
      expect(options[1].linkedPlayerId, isNull);
      expect(options[1].eligiblePlayers.map((p) => p.id), [_p3]); // distinct UUID kept, archived filtered out

      // Primary linked name prefers isMyTeam's linked player
      expect(
        RosterSyncTeamLinking.primaryLinkedPlayerName(
          options,
          {_teamA: _p1, _teamB: _p3},
        ),
        'Abdur',
      );
      expect(
        RosterSyncTeamLinking.primaryLinkedPlayerName(
          options,
          {_teamA: null, _teamB: null},
        ),
        isNull,
      );
    });

    testWidgets('TeamSpotLinkerSection renders compact single-team row for 1 team and grouped per-team list for 2+ teams', (tester) async {
      final teamA = TeamProfile(
        id: _teamA,
        name: 'Lahore Lions',
        isMyTeam: true,
        isOwner: true,
        createdAt: DateTime(2026, 11, 27),
        squad: [_player(id: _p1, teamId: _teamA, displayName: 'Abdur', userId: _ownerUid)],
      );
      final teamB = TeamProfile(
        id: _teamB,
        name: 'Sunday XI',
        isMyTeam: false,
        isOwner: false,
        createdAt: DateTime(2026, 11, 27),
        squad: [_player(id: _p3, teamId: _teamB, displayName: 'Abdur', userId: null)],
      );

      final singleOptions = RosterSyncTeamLinking.buildTeamLinkOptions(
        teams: [teamA],
        currentUserId: _ownerUid,
      );
      TeamLinkOption? tapped;

      await tester.pumpWidget(
        MaterialApp(
          theme: CreaseTheme.light(),
          home: Scaffold(
            body: TeamSpotLinkerSection(
              options: singleOptions,
              selectedPlayerByTeam: {_teamA: _p1},
              onSelectTeam: (opt) => tapped = opt,
            ),
          ),
        ),
      );

      expect(find.text('Link my scorecard name'), findsOneWidget);
      expect(find.text('Abdur'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);

      // Multi-team state
      final multiOptions = RosterSyncTeamLinking.buildTeamLinkOptions(
        teams: [teamA, teamB],
        currentUserId: _ownerUid,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: CreaseTheme.light(),
          home: Scaffold(
            body: TeamSpotLinkerSection(
              options: multiOptions,
              selectedPlayerByTeam: {_teamA: _p1, _teamB: null},
              onSelectTeam: (opt) => tapped = opt,
            ),
          ),
        ),
      );

      expect(find.text('Linked team spots'), findsOneWidget);
      expect(find.text('1 of 2 linked'), findsOneWidget);
      expect(find.text('Lahore Lions'), findsOneWidget);
      expect(find.text('Sunday XI'), findsOneWidget);
      expect(find.text('Abdur'), findsOneWidget);
      expect(find.text('Not linked'), findsOneWidget);

      await tester.tap(find.text('Sunday XI'));
      expect(tapped?.team.id, _teamB);
    });
  });
}
