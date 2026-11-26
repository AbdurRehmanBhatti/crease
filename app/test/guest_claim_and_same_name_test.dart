import 'dart:async';

import 'package:crease/domain/cricket_engine.dart';
import 'package:crease/domain/guest_merge.dart';
import 'package:crease/domain/guest_sync_guards.dart';
import 'package:crease/domain/models.dart';
import 'package:crease/domain/stats_engine.dart';
import 'package:crease/domain/team_profile.dart';
import 'package:crease/features/scorecard/match_summary_poster.dart';
import 'package:crease/features/scoring/widgets/live_crease_card.dart';
import 'package:crease/features/scoring/widgets/scoring_keypad_sheet.dart';
import 'package:crease/theme/crease_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _derbyPlayers = {
  'sheran': 'Sheran',
  'abdur': 'Abdur',
  'hamza': 'Hamza',
  'zain': 'Zain',
  'bilal': 'Bilal',
  'usama': 'Usama',
  'a1': 'A1',
  'a2': 'A2',
  'b1': 'B1',
  'b2': 'B2',
};

PlayerProfile _player(
  String id,
  String teamId,
  String name, {
  String role = '',
  String? designation,
}) {
  final now = DateTime(2026, 11, 25);
  return PlayerProfile(
    id: id,
    teamId: teamId,
    displayName: name,
    role: role,
    designation: designation,
    createdAt: now,
    updatedAt: now,
  );
}

BallEvent _ball({
  required String id,
  required String matchId,
  required int innings,
  required int seq,
  required String strikerId,
  required String nonStrikerId,
  required String bowlerId,
  int runsOffBat = 0,
  bool isWicket = false,
  WicketType? wicketType,
  String? dismissedBatterId,
  String? nextBatterId,
  bool voided = false,
}) =>
    BallEvent(
      id: id,
      matchId: matchId,
      inningsNumber: innings,
      sequenceNumber: seq,
      strikerId: strikerId,
      nonStrikerId: nonStrikerId,
      bowlerId: bowlerId,
      runsOffBat: runsOffBat,
      isWicket: isWicket,
      wicketType: wicketType,
      dismissedBatterId: dismissedBatterId,
      nextBatterId: nextBatterId,
      voided: voided,
      createdAt: DateTime(2026, 11, 25, 19, 0, seq),
    );

void main() {
  group('Same-name derbies (MatchSide + CricketEngine + StatsEngine)', () {
    test('keeps team names clean, tracks winnerSide, and isolates career stats by teamId', () {
      final config = MatchConfig(
        id: 'derby-1',
        teamA: 'Bhatti XI',
        teamB: 'Bhatti xi',
        teamAId: 'club-a',
        teamBId: 'club-b',
        oversLimit: 1,
        playersPerSide: 3,
        formatLabel: '1OV',
        battingFirstSide: MatchSide.a,
        openingStriker1Id: 'sheran',
        openingNonStriker1Id: 'abdur',
        openingBowler1Id: 'usama',
        openingStriker2Id: 'zain',
        openingNonStriker2Id: 'bilal',
        openingBowler2Id: 'hamza',
        teamAPlayerIds: const ['sheran', 'abdur', 'hamza'],
        teamBPlayerIds: const ['zain', 'bilal', 'usama'],
        adHocPlayers: _derbyPlayers,
        createdAt: DateTime(2026, 11, 25),
      );

      expect(config.hasSameTeamNames, isTrue);
      expect(config.sideForTeam(teamId: 'club-a', teamName: 'Bhatti XI'), MatchSide.a);
      expect(config.sideForTeam(teamId: 'club-b', teamName: 'Bhatti xi'), MatchSide.b);
      expect(config.rosterIdsForSide(MatchSide.a), ['sheran', 'abdur', 'hamza']);
      expect(config.rosterIdsForSide(MatchSide.b), ['zain', 'bilal', 'usama']);

      final events = [
        _ball(id: 'e1', matchId: 'derby-1', innings: 1, seq: 1, strikerId: 'sheran', nonStrikerId: 'abdur', bowlerId: 'usama', runsOffBat: 6),
        _ball(id: 'e2', matchId: 'derby-1', innings: 1, seq: 2, strikerId: 'sheran', nonStrikerId: 'abdur', bowlerId: 'usama', runsOffBat: 1),
        _ball(id: 'e3', matchId: 'derby-1', innings: 1, seq: 3, strikerId: 'abdur', nonStrikerId: 'sheran', bowlerId: 'usama', runsOffBat: 4),
        _ball(id: 'e4', matchId: 'derby-1', innings: 1, seq: 4, strikerId: 'abdur', nonStrikerId: 'sheran', bowlerId: 'usama', runsOffBat: 0),
        _ball(id: 'e5', matchId: 'derby-1', innings: 1, seq: 5, strikerId: 'abdur', nonStrikerId: 'sheran', bowlerId: 'usama', runsOffBat: 0),
        _ball(id: 'e6', matchId: 'derby-1', innings: 1, seq: 6, strikerId: 'abdur', nonStrikerId: 'sheran', bowlerId: 'usama', runsOffBat: 0),
        _ball(id: 'e7', matchId: 'derby-1', innings: 2, seq: 1, strikerId: 'zain', nonStrikerId: 'bilal', bowlerId: 'hamza', runsOffBat: 6),
        _ball(id: 'e8', matchId: 'derby-1', innings: 2, seq: 2, strikerId: 'zain', nonStrikerId: 'bilal', bowlerId: 'hamza', runsOffBat: 6),
      ];

      final derived = CricketEngine.derive(config, events);
      expect(derived.status, MatchStatus.completed);
      expect(derived.innings1.battingSide, MatchSide.a);
      expect(derived.innings1.bowlingSide, MatchSide.b);
      expect(derived.innings2!.battingSide, MatchSide.b);
      expect(derived.innings2!.bowlingSide, MatchSide.a);
      expect(derived.winnerSide, MatchSide.b);
      expect(derived.resultSummary, 'Bhatti xi (B) won by 2 wickets');
      expect(derived.config.teamA, 'Bhatti XI');
      expect(derived.config.teamB, 'Bhatti xi');

      final clubAStats = StatsEngine.derive([derived], teamId: 'club-a', teamName: 'Bhatti XI');
      final clubANames = clubAStats.map((s) => s.name).toSet();
      expect(clubANames, containsAll(['Sheran', 'Abdur', 'Hamza']));
      expect(clubANames, isNot(contains('Zain')));
      expect(clubANames, isNot(contains('Usama')));

      final clubBStats = StatsEngine.derive([derived], teamId: 'club-b', teamName: 'Bhatti xi');
      final clubBNames = clubBStats.map((s) => s.name).toSet();
      expect(clubBNames, containsAll(['Zain', 'Usama']));
      expect(clubBNames, isNot(contains('Sheran')));
      expect(clubBNames, isNot(contains('Hamza')));
    });

    test('4-innings Test match with follow-on keeps sides distinct when both teams have identical names', () {
      final config = MatchConfig(
        id: 'derby-test',
        teamA: 'Bhatti XI',
        teamB: 'Bhatti XI',
        teamAId: 'club-a',
        teamBId: 'club-b',
        oversLimit: 0,
        playersPerSide: 2,
        formatLabel: 'TEST',
        battingFirstSide: MatchSide.a,
        openingStriker1Id: 'a1',
        openingNonStriker1Id: 'a2',
        openingBowler1Id: 'b1',
        openingStriker2Id: 'b1',
        openingNonStriker2Id: 'b2',
        openingBowler2Id: 'a1',
        teamAPlayerIds: const ['a1', 'a2'],
        teamBPlayerIds: const ['b1', 'b2'],
        adHocPlayers: _derbyPlayers,
        isTestMatch: true,
        followOnEnforced: true,
        createdAt: DateTime(2026, 11, 25),
      );

      final events = [
        _ball(id: 't1', matchId: 'derby-test', innings: 1, seq: 1, strikerId: 'a1', nonStrikerId: 'a2', bowlerId: 'b1', runsOffBat: 6),
        _ball(id: 't2', matchId: 'derby-test', innings: 1, seq: 2, strikerId: 'a1', nonStrikerId: 'a2', bowlerId: 'b1', isWicket: true, wicketType: WicketType.bowled, dismissedBatterId: 'a1'),
        _ball(id: 't3', matchId: 'derby-test', innings: 2, seq: 1, strikerId: 'b1', nonStrikerId: 'b2', bowlerId: 'a1', runsOffBat: 2),
        _ball(id: 't4', matchId: 'derby-test', innings: 2, seq: 2, strikerId: 'b1', nonStrikerId: 'b2', bowlerId: 'a1', isWicket: true, wicketType: WicketType.bowled, dismissedBatterId: 'b1'),
        _ball(id: 't5', matchId: 'derby-test', innings: 3, seq: 1, strikerId: 'b1', nonStrikerId: 'b2', bowlerId: 'a1', runsOffBat: 1),
        _ball(id: 't6', matchId: 'derby-test', innings: 3, seq: 2, strikerId: 'b1', nonStrikerId: 'b2', bowlerId: 'a1', isWicket: true, wicketType: WicketType.bowled, dismissedBatterId: 'b1'),
      ];

      final derived = CricketEngine.derive(config, events);
      expect(derived.status, MatchStatus.completed);
      expect(derived.innings3!.battingSide, MatchSide.b);
      expect(derived.innings3!.bowlingSide, MatchSide.a);
      expect(derived.winnerSide, MatchSide.a);
      expect(derived.resultSummary, 'Bhatti XI (A) won by an innings and 3 runs');
    });
  });

  group('Guest-to-account merge & match team-ID rewrite', () {
    test('guest creates team with same name as registered team -> reparents players, clears conflicting designations, merges location & rewrites match IDs', () {
      final cloudTeams = [
        CloudOwnedTeam(
          id: 'reg-team-1',
          name: 'Bhatti XI',
          squad: [
            _player('p-c1', 'reg-team-1', 'Sheran', role: 'Batter', designation: 'C'),
            _player('p-c2', 'reg-team-1', 'Abdur'),
          ],
          location: null,
        ),
      ];

      final guestTeams = [
        TeamProfile(
          id: 'guest-team-1',
          name: '  bhatti xi ',
          location: 'Dhamial',
          squad: [
            _player('p-g1', 'guest-team-1', 'Usama', role: 'Bowler', designation: 'C'), // conflicts with existing C
            _player('p-g2', 'guest-team-1', 'Hamza', role: 'Bowler', designation: 'VC'), // preserved
          ],
          synced: false,
          createdAt: DateTime(2026, 11, 25),
        ),
      ];

      final actions = GuestTeamMergePlanner.planOfflineMerges(
        unsyncedGuestTeams: guestTeams,
        ownedCloudTeams: cloudTeams,
      );

      expect(actions, hasLength(1));
      final a = actions.first;
      expect(a.guestTeamId, 'guest-team-1');
      expect(a.survivingTeamId, 'reg-team-1');
      expect(a.playersToReparent.length, 2);
      expect(a.playersToReparent[0].teamId, 'reg-team-1');
      expect(a.playersToReparent[0].designation, isNull);
      expect(a.playersToReparent[1].designation, 'VC');
      expect(a.mergedLocation, 'Dhamial');
      expect(a.needsCloudTeamUpdate, isTrue);

      final guestMatches = [
        MatchConfig(
          id: 'm-1',
          teamA: 'bhatti xi',
          teamB: 'Celoks',
          teamAId: 'guest-team-1',
          teamBId: 'public-celoks',
          oversLimit: 6,
          formatLabel: '6OV',
          battingFirstSide: MatchSide.a,
          createdAt: DateTime(2026, 11, 25),
        ),
        MatchConfig(
          id: 'm-2',
          teamA: 'Celoks',
          teamB: 'bhatti xi',
          teamAId: 'public-celoks',
          teamBId: 'guest-team-1',
          oversLimit: 6,
          formatLabel: '6OV',
          battingFirstSide: MatchSide.a,
          createdAt: DateTime(2026, 11, 25),
        ),
      ];

      final rewritten = GuestTeamMergePlanner.rewriteMatchTeamIds(
        guestMatches,
        {a.guestTeamId: a.survivingTeamId},
      );
      expect(rewritten[0].teamAId, 'reg-team-1');
      expect(rewritten[0].teamBId, 'public-celoks');
      expect(rewritten[1].teamAId, 'public-celoks');
      expect(rewritten[1].teamBId, 'reg-team-1');
    });

    test('guest picks existing public teams (no local guest teams) -> zero merges and match team IDs stay untouched', () {
      final actions = GuestTeamMergePlanner.planOfflineMerges(
        unsyncedGuestTeams: const [],
        ownedCloudTeams: [
          CloudOwnedTeam(
            id: 'reg-team-1',
            name: 'Bhatti XI',
            squad: [_player('p-1', 'reg-team-1', 'Sheran')],
          ),
        ],
      );
      expect(actions, isEmpty);

      final match = MatchConfig(
        id: 'm-public',
        teamA: 'Bhatti XI',
        teamB: 'Celoks',
        teamAId: 'public-bhatti',
        teamBId: 'public-celoks',
        oversLimit: 6,
        formatLabel: '6OV',
        battingFirstSide: MatchSide.a,
        createdAt: DateTime(2026, 11, 25),
      );

      final rewritten = GuestTeamMergePlanner.rewriteMatchTeamIds([match], {});
      expect(rewritten.first.teamAId, 'public-bhatti');
      expect(rewritten.first.teamBId, 'public-celoks');
    });

    test('guest creates unique team + colliding team playing a same-name derby against a public club -> only guest duplicate ID is rewritten', () {
      final cloudTeams = [
        CloudOwnedTeam(
          id: 'reg-bhatti',
          name: 'Bhatti XI',
          squad: [_player('p-1', 'reg-bhatti', 'Sheran')],
          location: 'Rawalpindi',
        ),
      ];
      final guestTeams = [
        TeamProfile(
          id: 'guest-bhatti',
          name: 'Bhatti XI',
          location: 'Dhamial',
          squad: [_player('p-2', 'guest-bhatti', 'New Guy')],
          synced: false,
          createdAt: DateTime(2026, 11, 25),
        ),
        TeamProfile(
          id: 'guest-lions',
          name: 'Guest Lions',
          squad: [_player('p-3', 'guest-lions', 'Ali')],
          synced: false,
          createdAt: DateTime(2026, 11, 25),
        ),
      ];

      final actions = GuestTeamMergePlanner.planOfflineMerges(
        unsyncedGuestTeams: guestTeams,
        ownedCloudTeams: cloudTeams,
      );
      expect(actions, hasLength(1));
      expect(actions.first.guestTeamId, 'guest-bhatti');
      expect(actions.first.survivingTeamId, 'reg-bhatti');
      expect(actions.first.mergedLocation, 'Rawalpindi');

      final derbyMatch = MatchConfig(
        id: 'm-derby-guest',
        teamA: 'Bhatti XI',
        teamB: 'Bhatti xi',
        teamAId: 'guest-bhatti',
        teamBId: 'other-public-bhatti',
        oversLimit: 5,
        formatLabel: '5OV',
        battingFirstSide: MatchSide.a,
        createdAt: DateTime(2026, 11, 25),
      );

      final rewritten = GuestTeamMergePlanner.rewriteMatchTeamIds(
        [derbyMatch],
        {for (final a in actions) a.guestTeamId: a.survivingTeamId},
      );
      expect(rewritten.first.teamAId, 'reg-bhatti');
      expect(rewritten.first.teamBId, 'other-public-bhatti');
    });
  });

  group('SafeSignOutCoordinator (#3 offline sign-out protection)', () {
    test('does NOT clear local SQLite or sign out if offline backup fails', () async {
      final calls = <String>[];
      await expectLater(
        SafeSignOutCoordinator.execute(
          backupPending: () async {
            calls.add('backup');
            throw StateError('offline');
          },
          signOutGoogle: () async => calls.add('google'),
          signOutCloud: () async => calls.add('cloud'),
          clearLocalData: () async => calls.add('clear'),
          ensureFreshAnonymousSession: () async => calls.add('anon'),
        ),
        throwsStateError,
      );
      expect(calls, ['backup']);
    });

    test('does NOT clear local SQLite if cloud signOut throws after backup', () async {
      final calls = <String>[];
      await expectLater(
        SafeSignOutCoordinator.execute(
          backupPending: () async => calls.add('backup'),
          signOutGoogle: () async => calls.add('google'),
          signOutCloud: () async {
            calls.add('cloud');
            throw StateError('signOut failed');
          },
          clearLocalData: () async => calls.add('clear'),
          ensureFreshAnonymousSession: () async => calls.add('anon'),
        ),
        throwsStateError,
      );
      expect(calls, ['backup', 'google', 'cloud']);
    });

    test('executes strict order and tolerates post-sign-out anon failure', () async {
      final calls = <String>[];
      await SafeSignOutCoordinator.execute(
        backupPending: () async => calls.add('backup'),
        signOutGoogle: () async => calls.add('google'),
        signOutCloud: () async => calls.add('cloud'),
        clearLocalData: () async => calls.add('clear'),
        ensureFreshAnonymousSession: () async {
          calls.add('anon');
          throw StateError('brief drop');
        },
      );
      expect(calls, ['backup', 'google', 'cloud', 'clear', 'anon']);
    });
  });

  group('PendingGuestClaimCoordinator (#4 retryable guest claim)', () {
    test('retains pending guest UID on RPC failure and clears it after retry succeeds', () async {
      String? storedPending;
      var rpcAttempts = 0;

      await expectLater(
        PendingGuestClaimCoordinator.run(
          passedGuestUid: 'guest-uid-1',
          currentUserId: 'reg-uid-1',
          hasLocalData: true,
          readPendingGuestUid: () async => storedPending,
          writePendingGuestUid: (uid) async => storedPending = uid,
          runClaimRpc: (guest, reg) async {
            rpcAttempts++;
            throw StateError('network drop');
          },
        ),
        throwsStateError,
      );
      expect(rpcAttempts, 1);
      expect(storedPending, 'guest-uid-1');

      final claimed = await PendingGuestClaimCoordinator.run(
        passedGuestUid: null,
        currentUserId: 'reg-uid-1',
        hasLocalData: true,
        readPendingGuestUid: () async => storedPending,
        writePendingGuestUid: (uid) async => storedPending = uid,
        runClaimRpc: (guest, reg) async {
          rpcAttempts++;
          expect(guest, 'guest-uid-1');
          expect(reg, 'reg-uid-1');
        },
      );
      expect(claimed, isTrue);
      expect(rpcAttempts, 2);
      expect(storedPending, isNull);
    });

    test('clears pending UID without calling RPC when there is no local data or same UID', () async {
      String? storedPending = 'guest-uid-old';
      var rpcCalled = false;

      final ran = await PendingGuestClaimCoordinator.run(
        passedGuestUid: null,
        currentUserId: 'reg-uid-1',
        hasLocalData: false,
        readPendingGuestUid: () async => storedPending,
        writePendingGuestUid: (uid) async => storedPending = uid,
        runClaimRpc: (_, _) async => rpcCalled = true,
      );
      expect(ran, isFalse);
      expect(rpcCalled, isFalse);
      expect(storedPending, isNull);
    });
  });

  group('SingleFlight (#5 serialized anonymous sign-in)', () {
    test('deduplicates concurrent callers into 1 execution and resets after failure', () async {
      final flight = SingleFlight<String>();
      var calls = 0;
      final completer = Completer<String>();

      final results = await Future.wait([
        flight.run(() {
          calls++;
          return completer.future;
        }),
        flight.run(() {
          calls++;
          return completer.future;
        }),
        flight.run(() {
          calls++;
          return completer.future;
        }),
        Future(() {
          completer.complete('anon-uid-123');
          return 'anon-uid-123';
        }),
      ]);

      expect(calls, 1);
      expect(results.every((r) => r == 'anon-uid-123'), isTrue);

      await expectLater(
        flight.run(() async {
          calls++;
          throw StateError('offline');
        }),
        throwsStateError,
      );
      final retryUid = await flight.run(() async {
        calls++;
        return 'anon-uid-456';
      });
      expect(retryUid, 'anon-uid-456');
      expect(calls, 3);
    });
  });

  group('UnsyncedLocalCounts (#6 0-ball offline matches)', () {
    test('flags unsynced 0-ball match as having unsynced local data', () {
      const counts = UnsyncedLocalCounts(
        teams: 0,
        tournaments: 0,
        matches: 1,
        ballEvents: 0,
      );
      expect(counts.hasAny, isTrue);

      const clean = UnsyncedLocalCounts(
        teams: 0,
        tournaments: 0,
        matches: 0,
        ballEvents: 0,
      );
      expect(clean.hasAny, isFalse);
    });
  });

  group('MatchCompleteSheet guest backup nudge (#8)', () {
    DerivedMatchState completedMatch() {
      final cfg = MatchConfig(
        id: 'm-widget',
        teamA: 'Bhatti XI',
        teamB: 'Celoks',
        oversLimit: 1,
        playersPerSide: 2,
        formatLabel: '1OV',
        battingFirstSide: MatchSide.a,
        openingStriker1Id: 'a1',
        openingNonStriker1Id: 'a2',
        openingBowler1Id: 'b1',
        openingStriker2Id: 'b1',
        openingNonStriker2Id: 'b2',
        openingBowler2Id: 'a1',
        adHocPlayers: _derbyPlayers,
        createdAt: DateTime(2026, 11, 25),
      );
      return CricketEngine.derive(cfg, [
        _ball(id: 'w1', matchId: 'm-widget', innings: 1, seq: 1, strikerId: 'a1', nonStrikerId: 'a2', bowlerId: 'b1', runsOffBat: 4),
        _ball(id: 'w2', matchId: 'm-widget', innings: 1, seq: 2, strikerId: 'a1', nonStrikerId: 'a2', bowlerId: 'b1', isWicket: true, wicketType: WicketType.bowled, dismissedBatterId: 'a1'),
        _ball(id: 'w3', matchId: 'm-widget', innings: 2, seq: 1, strikerId: 'b1', nonStrikerId: 'b2', bowlerId: 'a1', runsOffBat: 6),
      ]);
    }

    testWidgets('shows subtle backup nudge for guests and fires callback on tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: CreaseTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MatchCompleteSheet(
                state: completedMatch(),
                onShare: () {},
                onViewScorecard: () {},
                onUndoLastBall: () {},
                onDone: () {},
                onSignInToBackup: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Saved on this device only'), findsOneWidget);
      expect(find.text('Sign in to back up'), findsOneWidget);
      await tester.tap(find.text('Sign in to back up'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('hides backup nudge for signed-in accounts', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: CreaseTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MatchCompleteSheet(
                state: completedMatch(),
                onShare: () {},
                onViewScorecard: () {},
                onUndoLastBall: () {},
                onDone: () {},
                onSignInToBackup: null,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Saved on this device only'), findsNothing);
      expect(find.text('Sign in to back up'), findsNothing);
    });
  });

  group('TeamProfile profileCode & guest poster sharing', () {
    test('TeamProfile round-trips profileCode uppercase through toMap/fromMap', () {
      final team = TeamProfile(
        id: 't-code-1',
        name: 'Bhatti XI',
        location: 'Dhamial',
        profileCode: 'bx-4k9m',
        createdAt: DateTime(2026, 11, 25),
      );

      final map = team.toMap();
      expect(map['profile_code'], 'BX-4K9M');

      final restored = TeamProfile.fromMap(map);
      expect(restored.profileCode, 'BX-4K9M');

      final guestTeam = TeamProfile(
        id: 't-guest-1',
        name: 'Street XI',
        createdAt: DateTime(2026, 11, 25),
      );
      expect(guestTeam.toMap()['profile_code'], isNull);
      expect(TeamProfile.fromMap(guestTeam.toMap()).profileCode, isNull);
    });

    test('MatchSummaryPoster omits live web URL for guests and includes it for signed-in accounts', () {
      final cfg = MatchConfig(
        id: 'm-share-1',
        teamA: 'Bhatti XI',
        teamB: 'Celoks',
        oversLimit: 1,
        playersPerSide: 2,
        formatLabel: '1OV',
        battingFirstSide: MatchSide.a,
        openingStriker1Id: 'a1',
        openingNonStriker1Id: 'a2',
        openingBowler1Id: 'b1',
        openingStriker2Id: 'b1',
        openingNonStriker2Id: 'b2',
        openingBowler2Id: 'a1',
        adHocPlayers: _derbyPlayers,
        createdAt: DateTime(2026, 11, 25),
      );
      final derived = CricketEngine.derive(cfg, [
        _ball(id: 's1', matchId: 'm-share-1', innings: 1, seq: 1, strikerId: 'a1', nonStrikerId: 'a2', bowlerId: 'b1', runsOffBat: 4),
        _ball(id: 's2', matchId: 'm-share-1', innings: 1, seq: 2, strikerId: 'a1', nonStrikerId: 'a2', bowlerId: 'b1', isWicket: true, wicketType: WicketType.bowled, dismissedBatterId: 'a1'),
        _ball(id: 's3', matchId: 'm-share-1', innings: 2, seq: 1, strikerId: 'b1', nonStrikerId: 'b2', bowlerId: 'a1', runsOffBat: 6),
      ]);

      final guestCaption = MatchSummaryPoster.buildShareCaption(
        derived,
        includeLiveLink: false,
      );
      expect(guestCaption, contains('Bhatti XI vs Celoks'));
      expect(guestCaption, contains('Celoks won by 1 wicket'));
      expect(guestCaption, isNot(contains('http')));

      final signedInCaption = MatchSummaryPoster.buildShareCaption(
        derived,
        includeLiveLink: true,
      );
      expect(signedInCaption, contains('Bhatti XI vs Celoks'));
      expect(signedInCaption, contains('https://'));
      expect(signedInCaption, contains('m-share-1'));
    });
  });

  group('Blank opening players on scoring pad', () {
    test('CricketEngine leaves batters/bowlers empty when opening players are blank', () {
      final cfg = MatchConfig(
        id: 'm-blank-openers',
        teamA: 'Bhatti XI',
        teamB: 'Abu G',
        oversLimit: 5,
        formatLabel: '5OV',
        battingFirstSide: MatchSide.a,
        createdAt: DateTime(2026, 11, 25),
      );

      final derived = CricketEngine.derive(cfg, const []);
      expect(derived.innings1.striker, isEmpty);
      expect(derived.innings1.nonStriker, isEmpty);
      expect(derived.innings1.currentBowler, isEmpty);
      expect(derived.innings1.needsNextBatter, isTrue);
      expect(derived.innings1.batters, isEmpty);
      expect(derived.innings1.bowlers, isEmpty);
    });

    testWidgets('LiveCreaseCard shows tappable Select striker, Select non-striker, and Select opening bowler rows', (tester) async {
      var strikerTapped = false;
      var nonStrikerTapped = false;
      var bowlerTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: CreaseTheme.dark(),
          home: Scaffold(
            body: LiveCreaseCard(
              strikerEmpty: true,
              nonStrikerEmpty: true,
              striker: const BatterLine(
                playerId: '',
                name: '',
                runs: 0,
                balls: 0,
                fours: 0,
                sixes: 0,
                isOut: false,
              ),
              nonStriker: const BatterLine(
                playerId: '',
                name: '',
                runs: 0,
                balls: 0,
                fours: 0,
                sixes: 0,
                isOut: false,
              ),
              bowler: const BowlerLine(
                playerId: '',
                name: '',
                legalBalls: 0,
                maidens: 0,
                runsConceded: 0,
                wickets: 0,
              ),
              needsNewBowler: true,
              isOpeningSelection: true,
              onSwapStrike: () {},
              onSelectNextBatter: () => strikerTapped = true,
              onSelectNonStriker: () => nonStrikerTapped = true,
              onSelectNextBowler: () => bowlerTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Select striker'), findsOneWidget);
      expect(find.text('Select non-striker'), findsOneWidget);
      expect(find.text('Select opening bowler'), findsOneWidget);

      await tester.tap(find.text('Select striker'));
      await tester.tap(find.text('Select non-striker'));
      await tester.tap(find.text('Select opening bowler'));
      await tester.pump();

      expect(strikerTapped, isTrue);
      expect(nonStrikerTapped, isTrue);
      expect(bowlerTapped, isTrue);
    });
  });
}
