import 'package:crease/domain/cricket_engine.dart';
import 'package:crease/domain/models.dart';
import 'package:crease/domain/tournament_engine.dart';
import 'package:crease/theme/crease_theme.dart';
import 'package:crease/widgets/match_rules_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BallEvent _e({
  required String id,
  int innings = 1,
  required int seq,
  required String striker,
  required String nonStriker,
  String bowler = 'bw1',
  int runs = 0,
  bool isWicket = false,
  WicketType? wicketType,
  String? dismissed,
  String? nextBatter,
}) =>
    BallEvent(
      id: id,
      matchId: 'm-rules',
      inningsNumber: innings,
      sequenceNumber: seq,
      strikerId: striker,
      nonStrikerId: nonStriker,
      bowlerId: bowler,
      runsOffBat: runs,
      isWicket: isWicket,
      wicketType: wicketType,
      dismissedBatterId: dismissed ?? (isWicket ? striker : null),
      nextBatterId: nextBatter,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1764250000000 + seq * 1000),
    );

void main() {
  group('Custom Match Rules serialization', () {
    test('MatchConfig & Tournament round-trip playersPerSide, lastManStands, maxOversPerBowler', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1764250000000);
      final cfg = MatchConfig(
        id: 'm-rules',
        teamA: 'Street XI',
        teamB: 'Gully Boys',
        oversLimit: 8,
        playersPerSide: 7,
        lastManStands: true,
        maxOversPerBowler: 2,
        formatLabel: '8OV',
        createdAt: now,
      );
      final restored = MatchConfig.fromMap(cfg.toMap());
      expect(restored.playersPerSide, 7);
      expect(restored.lastManStands, isTrue);
      expect(restored.maxOversPerBowler, 2);

      final cleared = restored.copyWith(clearMaxOversPerBowler: true);
      expect(cleared.maxOversPerBowler, isNull);

      final tr = Tournament(
        id: 't-rules',
        name: 'Tape Ball Cup',
        oversLimit: 6,
        playersPerSide: 6,
        lastManStands: true,
        maxOversPerBowler: 2,
        formatLabel: '6OV',
        createdAt: now,
      );
      final trRestored = Tournament.fromMap(tr.toMap());
      expect(trRestored.playersPerSide, 6);
      expect(trRestored.lastManStands, isTrue);
      expect(trRestored.maxOversPerBowler, 2);
    });
  });

  group('CricketEngine — Players per side & Last Man Stands', () {
    final names = {
      'a1': 'Ali',
      'a2': 'Bilal',
      'a3': 'Chaudhry',
      'a4': 'Danish',
      'a5': 'Ehsan',
      'a6': 'Faisal',
      'bw1': 'Haris',
      'bw2': 'Shaheen',
    };

    test('6-a-side standard match is all out at 5 wickets', () {
      final cfg = MatchConfig(
        id: 'm-rules',
        teamA: 'Street XI',
        teamB: 'Gully Boys',
        oversLimit: 6,
        playersPerSide: 6,
        lastManStands: false,
        formatLabel: '6OV',
        openingStriker1Id: 'a1',
        openingNonStriker1Id: 'a2',
        createdAt: DateTime(2026, 11, 27),
      );

      final events = [
        _e(id: '1', seq: 1, striker: 'a1', nonStriker: 'a2', isWicket: true, wicketType: WicketType.bowled, nextBatter: 'a3'),
        _e(id: '2', seq: 2, striker: 'a3', nonStriker: 'a2', isWicket: true, wicketType: WicketType.bowled, nextBatter: 'a4'),
        _e(id: '3', seq: 3, striker: 'a4', nonStriker: 'a2', isWicket: true, wicketType: WicketType.bowled, nextBatter: 'a5'),
        _e(id: '4', seq: 4, striker: 'a5', nonStriker: 'a2', isWicket: true, wicketType: WicketType.bowled, nextBatter: 'a6'),
        _e(id: '5', seq: 5, striker: 'a6', nonStriker: 'a2', isWicket: true, wicketType: WicketType.bowled),
      ];

      final state = CricketEngine.derive(cfg, events, playerNamesById: names);
      expect(state.innings1.wickets, 5);
      expect(state.innings1.isComplete, isTrue);
      expect(state.innings1.isLastManStanding, isFalse);
      expect(state.status, MatchStatus.inningsBreak);
    });

    test('6-a-side Last Man Stands lets 6th batter bat solo, holds strike on odd runs & over end, and ends at 6th wicket', () {
      final cfg = MatchConfig(
        id: 'm-rules',
        teamA: 'Street XI',
        teamB: 'Gully Boys',
        oversLimit: 6,
        playersPerSide: 6,
        lastManStands: true,
        formatLabel: '6OV',
        openingStriker1Id: 'a1',
        openingNonStriker1Id: 'a2',
        createdAt: DateTime(2026, 11, 27),
      );

      // 5 wickets fall; 'a2' (Bilal) is the sole surviving batter!
      final fiveWickets = [
        _e(id: '1', seq: 1, striker: 'a1', nonStriker: 'a2', isWicket: true, wicketType: WicketType.bowled, nextBatter: 'a3'),
        _e(id: '2', seq: 2, striker: 'a3', nonStriker: 'a2', isWicket: true, wicketType: WicketType.bowled, nextBatter: 'a4'),
        _e(id: '3', seq: 3, striker: 'a4', nonStriker: 'a2', isWicket: true, wicketType: WicketType.bowled, nextBatter: 'a5'),
        _e(id: '4', seq: 4, striker: 'a5', nonStriker: 'a2', isWicket: true, wicketType: WicketType.bowled, nextBatter: 'a6'),
        _e(id: '5', seq: 5, striker: 'a6', nonStriker: 'a2', isWicket: true, wicketType: WicketType.bowled),
      ];

      final soloState = CricketEngine.derive(
        cfg,
        fiveWickets,
        playerNamesById: names,
      );
      expect(soloState.innings1.wickets, 5);
      expect(soloState.innings1.isComplete, isFalse);
      expect(soloState.innings1.isLastManStanding, isTrue);
      expect(soloState.innings1.needsNextBatter, isFalse);
      expect(soloState.innings1.strikerId, 'a2');
      expect(soloState.innings1.nonStrikerId, isEmpty);

      // Bilal scores a single on ball 6 (completing the over!) — stays on strike
      final afterSoloSingle = [
        ...fiveWickets,
        _e(id: '6', seq: 6, striker: 'a2', nonStriker: 'a2', runs: 1),
      ];
      final afterOverState = CricketEngine.derive(
        cfg,
        afterSoloSingle,
        playerNamesById: names,
      );
      expect(afterOverState.innings1.totalRuns, 1);
      expect(afterOverState.innings1.oversText, '1.0');
      expect(afterOverState.innings1.isLastManStanding, isTrue);
      expect(afterOverState.innings1.strikerId, 'a2');
      expect(afterOverState.innings1.nonStrikerId, isEmpty);
      expect(afterOverState.innings1.batters.where((b) => b.playerId == 'a2').length, 1);

      // Bilal gets out on ball 7 -> 6th wicket ends the innings
      final allSixOut = [
        ...afterSoloSingle,
        _e(id: '7', seq: 7, striker: 'a2', nonStriker: 'a2', bowler: 'bw2', isWicket: true, wicketType: WicketType.caught),
      ];
      final endState = CricketEngine.derive(
        cfg,
        allSixOut,
        playerNamesById: names,
      );
      expect(endState.innings1.wickets, 6);
      expect(endState.innings1.isComplete, isTrue);
      expect(endState.innings1.isLastManStanding, isFalse);
      expect(endState.status, MatchStatus.inningsBreak);
    });

    test('Last Man Stands chase victory reports 1 wicket remaining accurately', () {
      final cfg = MatchConfig(
        id: 'm-rules',
        teamA: 'Street XI',
        teamB: 'Gully Boys',
        oversLimit: 1,
        playersPerSide: 3,
        lastManStands: true,
        formatLabel: '1OV',
        firstInningsTargetOverride: 5,
        createdAt: DateTime(2026, 11, 27),
      );

      final events = [
        _e(id: '1', innings: 2, seq: 1, striker: 'a1', nonStriker: 'a2', isWicket: true, wicketType: WicketType.bowled, nextBatter: 'a3'),
        _e(id: '2', innings: 2, seq: 2, striker: 'a3', nonStriker: 'a2', isWicket: true, wicketType: WicketType.bowled),
        _e(id: '3', innings: 2, seq: 3, striker: 'a2', nonStriker: 'a2', runs: 6),
      ];

      final state = CricketEngine.derive(cfg, events, playerNamesById: names);
      expect(state.status, MatchStatus.completed);
      expect(state.resultSummary, 'Gully Boys won by 1 wicket');
    });
  });

  group('MatchRulesSection widget', () {
    testWidgets('starts collapsed and updates summary when rules are customized', (tester) async {
      var players = 11;
      var lms = false;
      int? cap;

      await tester.pumpWidget(
        MaterialApp(
          theme: CreaseTheme.light(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => MatchRulesSection(
                playersPerSide: players,
                lastManStands: lms,
                maxOversPerBowler: cap,
                oversLimit: 10,
                isTestMatch: false,
                onPlayersPerSideChanged: (v) => setState(() => players = v),
                onLastManStandsChanged: (v) => setState(() => lms = v),
                onMaxOversPerBowlerChanged: (v) => setState(() => cap = v),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Match rules'), findsOneWidget);
      expect(find.text('11 players · Standard rules'), findsOneWidget);
      expect(find.text('Players per side'), findsNothing);

      // Expand
      await tester.tap(find.text('Match rules'));
      await tester.pumpAndSettle();
      expect(find.text('Players per side'), findsOneWidget);

      // Pick 8 players, enable Last man stands, pick 2 ov cap
      await tester.tap(find.text('8'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last man stands'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 ov'));
      await tester.pumpAndSettle();

      expect(
        find.text('8 players · Last man stands · Max 2 ov/bowler'),
        findsOneWidget,
      );
    });
  });
}
