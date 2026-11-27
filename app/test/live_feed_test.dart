import 'package:crease/data/local_event_store.dart';
import 'package:crease/domain/cricket_engine.dart';
import 'package:crease/domain/live_feed.dart';
import 'package:crease/domain/models.dart';
import 'package:crease/domain/tournament_engine.dart';
import 'package:crease/features/live/widgets/live_broadcast_toggle.dart';
import 'package:crease/theme/crease_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BallEvent _ball({
  required String id,
  int innings = 1,
  int seq = 1,
  int runsOffBat = 0,
  ExtraType extraType = ExtraType.none,
  int extraRuns = 0,
  bool isWicket = false,
  WicketType? wicketType,
  bool voided = false,
  DateTime? createdAt,
}) =>
    BallEvent(
      id: id,
      matchId: 'm-1',
      inningsNumber: innings,
      sequenceNumber: seq,
      strikerId: 'p1',
      nonStrikerId: 'p2',
      bowlerId: 'b1',
      runsOffBat: runsOffBat,
      extraType: extraType,
      extraRuns: extraRuns,
      isWicket: isWicket,
      wicketType: wicketType,
      dismissedBatterId: isWicket ? 'p1' : null,
      voided: voided,
      createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(1764240000000 + seq * 1000),
    );

void main() {
  group('BroadcastVisibility defaults & serialization', () {
    test('fromName handles case, whitespace, null, and unknown strings safely', () {
      expect(BroadcastVisibility.fromName(null), BroadcastVisibility.unlisted);
      expect(BroadcastVisibility.fromName(''), BroadcastVisibility.unlisted);
      expect(BroadcastVisibility.fromName('private'), BroadcastVisibility.unlisted);
      expect(BroadcastVisibility.fromName('unlisted'), BroadcastVisibility.unlisted);
      expect(BroadcastVisibility.fromName('public'), BroadcastVisibility.public);
      expect(BroadcastVisibility.fromName(' PUBLIC '), BroadcastVisibility.public);
    });

    test('MatchConfig defaults to unlisted and round-trips visibility & venue', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1764240000000);
      final unlisted = MatchConfig(
        id: 'm-1',
        teamA: 'Lahore Lions',
        teamB: 'Karachi Titans',
        oversLimit: 20,
        formatLabel: 'T20',
        createdAt: now,
      );
      expect(unlisted.visibility, BroadcastVisibility.unlisted);
      expect(unlisted.isPublicLive, isFalse);

      final restoredUnlisted = MatchConfig.fromMap(unlisted.toMap());
      expect(restoredUnlisted.visibility, BroadcastVisibility.unlisted);
      expect(restoredUnlisted.venue, isNull);

      final publicMatch = unlisted.copyWith(
        visibility: BroadcastVisibility.public,
        venue: 'Model Town Ground, Lahore',
      );
      expect(publicMatch.isPublicLive, isTrue);

      final restoredPublic = MatchConfig.fromMap(publicMatch.toMap());
      expect(restoredPublic.visibility, BroadcastVisibility.public);
      expect(restoredPublic.isPublicLive, isTrue);
      expect(restoredPublic.venue, 'Model Town Ground, Lahore');
    });

    test('Tournament defaults to unlisted and round-trips visibility', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1764240000000);
      final t = Tournament(
        id: 't-1',
        name: 'Ramadan Cup',
        oversLimit: 10,
        formatLabel: 'T10',
        createdAt: now,
      );
      expect(t.visibility, BroadcastVisibility.unlisted);
      expect(t.isPublicLive, isFalse);

      final pub = t.copyWith(visibility: BroadcastVisibility.public);
      final restored = Tournament.fromMap(pub.toMap());
      expect(restored.visibility, BroadcastVisibility.public);
      expect(restored.isPublicLive, isTrue);
    });
  });

  group('Remote match merge regression (visibility & venue preservation)', () {
    test('preserves local public visibility & venue when remote payload omits keys', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1764240000000);
      final localPublic = MatchConfig(
        id: 'm-1',
        teamA: 'Test 1',
        teamB: 'Test 2',
        oversLimit: 2,
        formatLabel: '2OV',
        visibility: BroadcastVisibility.public,
        venue: 'Dhamial',
        createdAt: now,
      );

      final remoteWithoutNewCols = Map<String, Object?>.from(localPublic.toMap())
        ..remove('visibility')
        ..remove('venue');

      final merged = LocalEventStoreMatchesBalls.mergeRemoteMatchConfig(
        remoteWithoutNewCols,
        existingLocal: localPublic,
      );

      expect(merged.visibility, BroadcastVisibility.public);
      expect(merged.isPublicLive, isTrue);
      expect(merged.venue, 'Dhamial');
    });

    test('applies explicit remote visibility change when key is present', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1764240000000);
      final localPublic = MatchConfig(
        id: 'm-1',
        teamA: 'Test 1',
        teamB: 'Test 2',
        oversLimit: 2,
        formatLabel: '2OV',
        visibility: BroadcastVisibility.public,
        createdAt: now,
      );

      final remoteExplicitUnlisted =
          Map<String, Object?>.from(localPublic.toMap())
            ..['visibility'] = 'unlisted';

      final merged = LocalEventStoreMatchesBalls.mergeRemoteMatchConfig(
        remoteExplicitUnlisted,
        existingLocal: localPublic,
      );

      expect(merged.visibility, BroadcastVisibility.unlisted);
      expect(merged.isPublicLive, isFalse);
    });
  });

  group('Last-ball badge & live summary projection', () {
    test('describeLastBall formats dots, runs, boundaries, wickets, and all extras', () {
      expect(LocalEventStoreLiveFeed.describeLastBall(null), isNull);

      expect(
        LocalEventStoreLiveFeed.describeLastBall(_ball(id: '1', runsOffBat: 0)),
        (label: '0', kind: 'normal'),
      );
      expect(
        LocalEventStoreLiveFeed.describeLastBall(_ball(id: '2', runsOffBat: 2)),
        (label: '2', kind: 'normal'),
      );
      expect(
        LocalEventStoreLiveFeed.describeLastBall(_ball(id: '3', runsOffBat: 4)),
        (label: '4', kind: 'boundary'),
      );
      expect(
        LocalEventStoreLiveFeed.describeLastBall(_ball(id: '4', runsOffBat: 6)),
        (label: '6', kind: 'boundary'),
      );
      expect(
        LocalEventStoreLiveFeed.describeLastBall(
          _ball(id: '5', isWicket: true, wicketType: WicketType.bowled),
        ),
        (label: 'W', kind: 'wicket'),
      );
      expect(
        LocalEventStoreLiveFeed.describeLastBall(
          _ball(
            id: '6',
            runsOffBat: 1,
            isWicket: true,
            wicketType: WicketType.runOut,
          ),
        ),
        (label: 'W+1', kind: 'wicket'),
      );
      expect(
        LocalEventStoreLiveFeed.describeLastBall(
          _ball(id: '7', extraType: ExtraType.wide, extraRuns: 1),
        ),
        (label: 'WD', kind: 'extra'),
      );
      expect(
        LocalEventStoreLiveFeed.describeLastBall(
          _ball(id: '8', extraType: ExtraType.wide, extraRuns: 3),
        ),
        (label: '3WD', kind: 'extra'),
      );
      expect(
        LocalEventStoreLiveFeed.describeLastBall(
          _ball(id: '9', extraType: ExtraType.noBall, extraRuns: 1),
        ),
        (label: 'NB', kind: 'extra'),
      );
      expect(
        LocalEventStoreLiveFeed.describeLastBall(
          _ball(id: '10', runsOffBat: 4, extraType: ExtraType.noBall, extraRuns: 1),
        ),
        (label: '5NB', kind: 'extra'),
      );
      expect(
        LocalEventStoreLiveFeed.describeLastBall(
          _ball(id: '11', extraType: ExtraType.bye, extraRuns: 2),
        ),
        (label: '2B', kind: 'extra'),
      );
      expect(
        LocalEventStoreLiveFeed.describeLastBall(
          _ball(id: '12', extraType: ExtraType.legBye, extraRuns: 1),
        ),
        (label: '1LB', kind: 'extra'),
      );
      expect(
        LocalEventStoreLiveFeed.describeLastBall(
          _ball(id: '13', extraType: ExtraType.penalty, extraRuns: 5),
        ),
        (label: '+5', kind: 'extra'),
      );
    });

    test('buildLiveSummaryPayload skips voided balls and computes live/break/chase/abandoned states', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1764240000000);
      final cfg = MatchConfig(
        id: 'm-1',
        teamA: 'Lahore Lions',
        teamB: 'Karachi Titans',
        oversLimit: 1,
        formatLabel: '1OV',
        visibility: BroadcastVisibility.public,
        createdAt: now,
      );

      // 1. Live 1st innings with a voided trailing ball
      final ev1 = [
        _ball(id: 'b1', seq: 1, runsOffBat: 4),
        _ball(id: 'b2', seq: 2, runsOffBat: 6),
        _ball(id: 'b3', seq: 3, runsOffBat: 1, voided: true),
      ];
      final derived1 = CricketEngine.derive(cfg, ev1);
      final sum1 = LocalEventStoreLiveFeed.buildLiveSummaryPayload(
        cfg,
        ev1,
        derived1,
        nowMs: 1764240099000,
      );
      expect(sum1['status'], 'live');
      expect(sum1['balls_count'], 2);
      expect(sum1['inn1_runs'], 10);
      expect(sum1['inn1_overs'], '0.2');
      expect(sum1['inn2_started'], isFalse);
      expect(sum1['last_ball_label'], '6');
      expect(sum1['last_ball_kind'], 'boundary');
      expect(sum1['status_line'], 'CRR 30.00');

      // 2. Complete 1st innings (6 legal balls) -> inningsBreak
      final inn1Complete = [
        for (var i = 1; i <= 6; i++) _ball(id: 'i1-$i', seq: i, runsOffBat: 2),
      ];
      final derivedBreak = CricketEngine.derive(cfg, inn1Complete);
      final sumBreak = LocalEventStoreLiveFeed.buildLiveSummaryPayload(
        cfg,
        inn1Complete,
        derivedBreak,
      );
      expect(sumBreak['status'], 'inningsBreak');
      expect(sumBreak['status_line'], 'Innings break · Karachi Titans need 13');
      expect(sumBreak['inn1_runs'], 12);

      // 3. 2nd innings chase with 1 ball remaining -> singular "1 ball"
      final chaseEvents = [
        ...inn1Complete,
        for (var i = 1; i <= 5; i++)
          _ball(id: 'i2-$i', innings: 2, seq: i, runsOffBat: 2),
      ];
      final derivedChase = CricketEngine.derive(cfg, chaseEvents);
      final sumChase = LocalEventStoreLiveFeed.buildLiveSummaryPayload(
        cfg,
        chaseEvents,
        derivedChase,
      );
      expect(sumChase['status'], 'live');
      expect(sumChase['inn2_started'], isTrue);
      expect(sumChase['status_line'], 'Karachi Titans need 3 from 1 ball');

      // 4. Abandoned match encodes status = 'abandoned'
      final abandonedCfg = cfg.copyWith(declaredInnings: const [-1]);
      final derivedAbandoned = CricketEngine.derive(abandonedCfg, ev1);
      final sumAbandoned = LocalEventStoreLiveFeed.buildLiveSummaryPayload(
        abandonedCfg,
        ev1,
        derivedAbandoned,
      );
      expect(sumAbandoned['status'], 'abandoned');
    });
  });

  group('LiveFeedSnapshot parsing & edge cases', () {
    test('empty feed parses cleanly with isEmpty == true', () {
      final snap = LiveFeedSnapshot.fromMap({
        'server_now_ms': 1764240060000,
        'live_matches': const [],
        'recent_matches': const [],
        'tournaments': const [],
      });
      expect(snap.isEmpty, isTrue);
      expect(snap.liveMatches, isEmpty);
      expect(snap.recentMatches, isEmpty);
      expect(snap.tournaments, isEmpty);
    });

    test('handles Team B batting first (swaps inn1/inn2 names, IDs, and logos)', () {
      final match = LiveFeedMatch.fromMap({
        'id': 'm-b-first',
        'team_a': 'Alpha XI',
        'team_b': 'Beta CC',
        'team_a_id': 'id-a',
        'team_b_id': 'id-b',
        'team_a_logo_url': 'https://example.com/a.png',
        'team_b_logo_url': 'https://example.com/b.png',
        'format_label': 'T10',
        'overs_limit': 10,
        'is_test_match': false,
        'status': 'live',
        'active_innings': 1,
        'batting_side': 'b',
        'inn1_batting_side': 'b',
        'inn1_runs': 45,
        'inn1_wickets': 1,
        'inn1_overs': '4.2',
        'inn2_started': false,
        'balls_count': 26,
        'last_event_at': 1764240050000,
      });

      expect(match.inn1TeamName, 'Beta CC');
      expect(match.inn2TeamName, 'Alpha XI');
      expect(match.inn1TeamId, 'id-b');
      expect(match.inn2TeamId, 'id-a');
      expect(match.inn1LogoUrl, 'https://example.com/b.png');
      expect(match.inn2LogoUrl, 'https://example.com/a.png');
      expect(match.resolvedInn2Side, MatchSide.a);
    });

    test('LiveFeedTournament formats same-day, multi-day, start-only, and null date ranges', () {
      LiveFeedTournament makeT({DateTime? start, DateTime? end}) =>
          LiveFeedTournament(
            id: 't1',
            name: 'Cup',
            formatLabel: 'T20',
            structure: TournamentStructure.open,
            startDate: start,
            endDate: end,
            teamCount: 4,
            liveMatchCount: 0,
            completedMatchCount: 0,
            latestActivity: DateTime(2026, 11, 27),
          );

      expect(makeT().dateRangeLabel, isNull);
      expect(
        makeT(start: DateTime(2026, 11, 27), end: DateTime(2026, 11, 27))
            .dateRangeLabel,
        'Nov 27',
      );
      expect(
        makeT(start: DateTime(2026, 11, 27), end: DateTime(2026, 12, 4))
            .dateRangeLabel,
        'Nov 27 – Dec 4',
      );
      expect(
        makeT(start: DateTime(2026, 11, 27)).dateRangeLabel,
        'Starts Nov 27',
      );
      expect(
        makeT(end: DateTime(2026, 12, 4)).dateRangeLabel,
        'Ends Dec 4',
      );
    });

    test('parses live matches, recent matches, and public tournaments', () {
      final snap = LiveFeedSnapshot.fromMap({
        'server_now_ms': 1764240060000,
        'live_matches': [
          {
            'id': 'm-live-1',
            'team_a': 'Lahore Lions',
            'team_b': 'Karachi Titans',
            'team_a_id': 'ta-1',
            'team_b_id': 'tb-1',
            'format_label': 'T20',
            'overs_limit': 20,
            'is_test_match': false,
            'tournament_id': 't-1',
            'tournament_name': 'Ramadan Cup',
            'venue': 'Lahore',
            'status': 'live',
            'active_innings': 2,
            'batting_side': 'b',
            'inn1_batting_side': 'a',
            'inn1_runs': 152,
            'inn1_wickets': 6,
            'inn1_overs': '20.0',
            'inn2_started': true,
            'inn2_batting_side': 'b',
            'inn2_runs': 139,
            'inn2_wickets': 4,
            'inn2_overs': '18.3',
            'status_line': 'Karachi Titans need 14 from 9 balls',
            'last_ball_label': '4',
            'last_ball_kind': 'boundary',
            'balls_count': 231,
            'last_event_at': 1764240050000,
          },
        ],
        'recent_matches': [
          {
            'id': 'm-done-1',
            'team_a': 'Gulberg Stars',
            'team_b': 'Model Town XI',
            'format_label': 'T10',
            'overs_limit': 10,
            'is_test_match': false,
            'status': 'completed',
            'active_innings': 2,
            'batting_side': 'b',
            'inn1_batting_side': 'a',
            'inn1_runs': 108,
            'inn1_wickets': 5,
            'inn1_overs': '10.0',
            'inn2_started': true,
            'inn2_batting_side': 'b',
            'inn2_runs': 109,
            'inn2_wickets': 3,
            'inn2_overs': '9.4',
            'status_line': 'Model Town XI won by 7 wickets',
            'balls_count': 118,
            'last_event_at': 1764230000000,
          },
        ],
        'tournaments': [
          {
            'id': 't-1',
            'name': 'Ramadan Cup',
            'location': 'Lahore',
            'format_label': 'T20',
            'structure': 'leagueKnockout',
            'team_count': 8,
            'live_match_count': 1,
            'completed_match_count': 4,
            'latest_activity': 1764240050000,
          },
        ],
      });

      expect(snap.isEmpty, isFalse);
      expect(snap.liveMatches, hasLength(1));
      expect(snap.recentMatches, hasLength(1));
      expect(snap.tournaments, hasLength(1));

      final live = snap.liveMatches.first;
      expect(live.isLive, isTrue);
      expect(live.inn1TeamName, 'Lahore Lions');
      expect(live.inn2TeamName, 'Karachi Titans');
      expect(live.inn1ScoreText, '152/6');
      expect(live.inn2ScoreText, '139/4');
      expect(live.lastBallLabel, '4');
      expect(live.lastBallKind, 'boundary');

      final tr = snap.tournaments.first;
      expect(tr.hasLiveMatches, isTrue);
      expect(tr.structure, TournamentStructure.leagueKnockout);
      expect(tr.teamCount, 8);
    });
  });

  group('LiveBroadcastToggleTile widget', () {
    testWidgets('shows unlisted copy by default and toggles to public match & tournament copy', (tester) async {
      var isPublic = false;
      var isTournament = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: CreaseTheme.light(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  LiveBroadcastToggleTile(
                    isPublic: isPublic,
                    isTournament: isTournament,
                    onChanged: (v) => setState(() => isPublic = v),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => isTournament = !isTournament),
                    child: const Text('Switch mode'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Show on Live tab'), findsOneWidget);
      expect(
        find.text('Unlisted · Only people with your link can view'),
        findsOneWidget,
      );

      // Tap row -> toggles public ON for match (CreaseLiveDot pulses continuously)
      await tester.tap(find.text('Show on Live tab'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        find.text('Public · Appears on Crease Live after the first ball'),
        findsOneWidget,
      );

      // Switch to tournament mode -> shows tournament public copy
      await tester.tap(find.text('Switch mode'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        find.text('Public · Tournament and live matches appear on Crease Live'),
        findsOneWidget,
      );
    });
  });
}
