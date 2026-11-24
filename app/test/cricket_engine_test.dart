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

    test('handles retired hurt, +5 penalty runs, wide+stumped, and revised target', () {
      final cfg = MatchConfig(
        id: 'edge-cases-1',
        teamA: 'A',
        teamB: 'B',
        oversLimit: 10,
        formatLabel: 'T10',
        battingFirstTeam: 'A',
        openingStrikerInnings1: 'Ali',
        openingNonStrikerInnings1: 'Bilal',
        openingBowlerInnings1: 'Zain',
        firstInningsTargetOverride: 55,
        createdAt: DateTime(2026),
      );
      final events = [
        BallEvent(
          id: 'e1',
          matchId: cfg.id,
          inningsNumber: 1,
          sequenceNumber: 1,
          striker: 'Ali',
          nonStriker: 'Bilal',
          bowler: 'Zain',
          extraType: ExtraType.penalty,
          extraRuns: 5,
          createdAt: DateTime(2026),
        ),
        BallEvent(
          id: 'e2',
          matchId: cfg.id,
          inningsNumber: 1,
          sequenceNumber: 2,
          striker: 'Ali',
          nonStriker: 'Bilal',
          bowler: 'Zain',
          isWicket: true,
          wicketType: WicketType.retiredHurt,
          dismissedBatter: 'Ali',
          nextBatter: 'Kamran',
          createdAt: DateTime(2026),
        ),
        BallEvent(
          id: 'e3',
          matchId: cfg.id,
          inningsNumber: 1,
          sequenceNumber: 3,
          striker: 'Kamran',
          nonStriker: 'Bilal',
          bowler: 'Zain',
          extraType: ExtraType.wide,
          extraRuns: 1,
          isWicket: true,
          wicketType: WicketType.stumped,
          dismissedBatter: 'Kamran',
          fielder: 'WK',
          createdAt: DateTime(2026),
        ),
      ];

      final state = CricketEngine.derive(cfg, events);
      expect(state.innings1.totalRuns, 6);
      expect(state.innings1.legalBalls, 0);
      expect(state.innings1.wickets, 1);
      expect(state.innings1.bowlerByName('Zain').runsConceded, 1);
      expect(state.innings1.bowlerByName('Zain').wickets, 1);
      expect(state.innings1.batterByName('Ali').isOut, isFalse);
      expect(state.innings1.batterByName('Ali').dismissalText, 'retired hurt');
      expect(state.innings1.needsNextBatter, isTrue);
    });

    test('in-match Super Over resolves tied limited-overs match inside innings 3 & 4', () {
      final cfg = MatchConfig(
        id: 'so-match',
        teamA: 'Bhatti XI',
        teamB: 'Street XI',
        oversLimit: 1,
        playersPerSide: 11,
        formatLabel: '1OV',
        battingFirstTeam: 'Bhatti XI',
        openingStrikerInnings1: 'Ali',
        openingNonStrikerInnings1: 'Bilal',
        openingBowlerInnings1: 'Zain',
        openingStrikerInnings2: 'Saad',
        openingNonStrikerInnings2: 'Omer',
        openingBowlerInnings2: 'Hamza',
        teamAPlayers: const ['Ali', 'Bilal', 'Hamza'],
        teamBPlayers: const ['Saad', 'Omer', 'Zain'],
        createdAt: DateTime(2026),
      );

      // Both teams score 6 runs in 1 over -> tied regulation match.
      final regEvents = <BallEvent>[
        for (var i = 1; i <= 6; i++)
          BallEvent(
            id: 'i1-$i',
            matchId: cfg.id,
            inningsNumber: 1,
            sequenceNumber: i,
            striker: 'Ali',
            nonStriker: 'Bilal',
            bowler: 'Zain',
            runsOffBat: i == 1 ? 6 : 0,
            createdAt: DateTime(2026),
          ),
        for (var i = 1; i <= 6; i++)
          BallEvent(
            id: 'i2-$i',
            matchId: cfg.id,
            inningsNumber: 2,
            sequenceNumber: i,
            striker: 'Saad',
            nonStriker: 'Omer',
            bowler: 'Hamza',
            runsOffBat: i == 1 ? 6 : 0,
            createdAt: DateTime(2026),
          ),
      ];

      final tied = CricketEngine.derive(cfg, regEvents);
      expect(tied.status, MatchStatus.completed);
      expect(tied.resultSummary, 'Match tied');
      expect(tied.innings3, isNull);

      // Super Over Innings 1 (inningsNumber 3): Street XI (batted 2nd) bats first,
      // scores 4 then loses 2 wickets -> all out at 2 wickets!
      final so1Events = [
        ...regEvents,
        BallEvent(
          id: 'so1-1',
          matchId: cfg.id,
          inningsNumber: 3,
          sequenceNumber: 1,
          striker: 'Saad',
          nonStriker: 'Omer',
          bowler: 'Hamza',
          runsOffBat: 4,
          createdAt: DateTime(2026),
        ),
        BallEvent(
          id: 'so1-2',
          matchId: cfg.id,
          inningsNumber: 3,
          sequenceNumber: 2,
          striker: 'Saad',
          nonStriker: 'Omer',
          bowler: 'Hamza',
          isWicket: true,
          wicketType: WicketType.bowled,
          dismissedBatter: 'Saad',
          nextBatter: 'Zain',
          createdAt: DateTime(2026),
        ),
        BallEvent(
          id: 'so1-3',
          matchId: cfg.id,
          inningsNumber: 3,
          sequenceNumber: 3,
          striker: 'Zain',
          nonStriker: 'Omer',
          bowler: 'Hamza',
          isWicket: true,
          wicketType: WicketType.bowled,
          dismissedBatter: 'Zain',
          createdAt: DateTime(2026),
        ),
      ];

      final soBreak = CricketEngine.derive(cfg, so1Events);
      expect(soBreak.innings3, isNotNull);
      expect(soBreak.innings3!.battingTeam, 'Street XI');
      expect(soBreak.innings3!.isComplete, isTrue);
      expect(soBreak.innings3!.totalRuns, 4);
      expect(soBreak.status, MatchStatus.inningsBreak);

      // Super Over Innings 2 (inningsNumber 4): Bhatti XI hits 6 on ball 1 -> wins!
      final so2Events = [
        ...so1Events,
        BallEvent(
          id: 'so2-1',
          matchId: cfg.id,
          inningsNumber: 4,
          sequenceNumber: 1,
          striker: 'Ali',
          nonStriker: 'Bilal',
          bowler: 'Zain',
          runsOffBat: 6,
          createdAt: DateTime(2026),
        ),
      ];

      final done = CricketEngine.derive(cfg, so2Events);
      expect(done.status, MatchStatus.completed);
      expect(done.innings4, isNotNull);
      expect(done.innings4!.battingTeam, 'Bhatti XI');
      expect(done.innings4!.isComplete, isTrue);
      expect(done.resultSummary, 'Bhatti XI won Super Over');
    });
  });
}

