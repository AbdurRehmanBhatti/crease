import 'package:crease/data/sample_match.dart';
import 'package:crease/domain/cricket_engine.dart';
import 'package:crease/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CricketEngine derivation', () {
    test('derives exact sample match totals from 100 real ball events', () {
      final config = SampleMatchSeed.config();
      final events = SampleMatchSeed.events();
      final state = CricketEngine.derive(config, events);

      final inn = state.activeInnings;
      expect(state.activeInningsNumber, 2);
      expect(state.status, MatchStatus.live);
      expect(inn.totalRuns, 142);
      expect(inn.wickets, 3);
      expect(inn.oversText, '16.4');
      expect(inn.runsNeeded, 38);
      expect(inn.ballsRemaining, 20);
      expect(inn.requiredRunRate, closeTo(11.4, 0.01));

      final rauf = inn.bowlerByName('H. Rauf');
      expect(rauf.figuresText, '3.4-0-31-1');

      final over17 = inn.overs.last;
      expect(over17.overNumber, 17);
      expect(over17.balls.map((b) => b.shortMark).toList(), ['1', '•', '4', 'W']);
    });

    test('rotates strike on odd runs, end of over, and handles wides/no-balls', () {
      final cfg = MatchConfig(
        id: 'm1',
        teamA: 'A',
        teamB: 'B',
        oversLimit: 2,
        formatLabel: '2OV',
        battingFirstTeam: 'A',
        openingStrikerInnings1: 'Ali',
        openingNonStrikerInnings1: 'Bilal',
        openingBowlerInnings1: 'Zain',
        createdAt: DateTime(2026, 11, 21),
      );

      final now = DateTime(2026, 11, 21);
      final events = [
        // Ball 1: single -> Bilal on strike
        BallEvent(
          id: '1',
          matchId: 'm1',
          inningsNumber: 1,
          sequenceNumber: 1,
          striker: 'Ali',
          nonStriker: 'Bilal',
          bowler: 'Zain',
          runsOffBat: 1,
          createdAt: now,
        ),
        // Wide (+1 penalty): not a legal ball, strike stays with Bilal
        BallEvent(
          id: '2',
          matchId: 'm1',
          inningsNumber: 1,
          sequenceNumber: 2,
          striker: 'Bilal',
          nonStriker: 'Ali',
          bowler: 'Zain',
          extraType: ExtraType.wide,
          extraRuns: 1,
          createdAt: now,
        ),
        // Ball 2: four -> Bilal stays on strike
        BallEvent(
          id: '3',
          matchId: 'm1',
          inningsNumber: 1,
          sequenceNumber: 3,
          striker: 'Bilal',
          nonStriker: 'Ali',
          bowler: 'Zain',
          runsOffBat: 4,
          createdAt: now,
        ),
      ];

      final state = CricketEngine.derive(cfg, events);
      final inn = state.innings1;
      expect(inn.totalRuns, 6);
      expect(inn.legalBalls, 2);
      expect(inn.oversText, '0.2');
      expect(inn.wides, 1);
      expect(inn.striker, 'Bilal');
      expect(inn.batterByName('Bilal').runs, 4);
      expect(inn.batterByName('Bilal').balls, 1);
      expect(inn.batterByName('Bilal').fours, 1);
    });

    test('voiding any ball recalculates score cleanly with zero drift', () {
      final config = SampleMatchSeed.config();
      final events = SampleMatchSeed.events();
      // Void the 4 on ball 17.3 (second to last ball)
      events[events.length - 2] =
          events[events.length - 2].copyWith(voided: true);

      final state = CricketEngine.derive(config, events);
      expect(state.activeInnings.totalRuns, 138);
      expect(state.activeInnings.oversText, '16.3');
    });

    test('recording a wicket without nextBatter prompts for next batter', () {
      final config = SampleMatchSeed.config();
      final events = SampleMatchSeed.events();
      final last = events.last;
      events[events.length - 1] = BallEvent(
        id: last.id,
        matchId: last.matchId,
        inningsNumber: last.inningsNumber,
        sequenceNumber: last.sequenceNumber,
        striker: last.striker,
        nonStriker: last.nonStriker,
        bowler: last.bowler,
        isWicket: true,
        wicketType: WicketType.caught,
        dismissedBatter: last.dismissedBatter,
        fielder: last.fielder,
        nextBatter: null,
        createdAt: last.createdAt,
      );

      final pending = CricketEngine.derive(config, events);
      expect(pending.activeInnings.needsNextBatter, isTrue);
      expect(pending.activeInnings.striker, isEmpty);

      // Selecting the next batter resolves the crease cleanly
      events[events.length - 1] =
          events.last.copyWith(nextBatter: 'Shadab K.');
      final resolved = CricketEngine.derive(config, events);
      expect(resolved.activeInnings.needsNextBatter, isFalse);
      expect(resolved.activeInnings.striker, 'Shadab K.');
    });
  });
}

