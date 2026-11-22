import 'package:crease/domain/cricket_engine.dart';
import 'package:crease/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CricketEngine 4-innings Test match support', () {
    test('handles declaration, lead/trail, and 4th-innings chase win', () {
      final now = DateTime(2026, 11, 22);
      final cfg = MatchConfig(
        id: 'test-1',
        teamA: 'Pakistan',
        teamB: 'England',
        oversLimit: 0,
        playersPerSide: 3, // 2 wickets = all out
        formatLabel: 'TEST',
        battingFirstTeam: 'Pakistan',
        openingStrikerInnings1: 'P1',
        openingNonStrikerInnings1: 'P2',
        openingBowlerInnings1: 'E1',
        openingStrikerInnings2: 'E1',
        openingNonStrikerInnings2: 'E2',
        openingBowlerInnings2: 'P1',
        isTestMatch: true,
        declaredInnings: const [1, 3],
        createdAt: now,
      );

      final events = <BallEvent>[
        // Inn 1: Pakistan 10/0d
        BallEvent(id: '1', matchId: 'test-1', inningsNumber: 1, sequenceNumber: 1, striker: 'P1', nonStriker: 'P2', bowler: 'E1', runsOffBat: 6, createdAt: now),
        BallEvent(id: '2', matchId: 'test-1', inningsNumber: 1, sequenceNumber: 2, striker: 'P1', nonStriker: 'P2', bowler: 'E1', runsOffBat: 4, createdAt: now),

        // Inn 2: England 4/2 (all out, trail by 6)
        BallEvent(id: '3', matchId: 'test-1', inningsNumber: 2, sequenceNumber: 3, striker: 'E1', nonStriker: 'E2', bowler: 'P1', runsOffBat: 4, createdAt: now),
        BallEvent(id: '4', matchId: 'test-1', inningsNumber: 2, sequenceNumber: 4, striker: 'E1', nonStriker: 'E2', bowler: 'P1', isWicket: true, wicketType: WicketType.bowled, nextBatter: 'E3', createdAt: now),
        BallEvent(id: '5', matchId: 'test-1', inningsNumber: 2, sequenceNumber: 5, striker: 'E3', nonStriker: 'E2', bowler: 'P1', isWicket: true, wicketType: WicketType.bowled, createdAt: now),

        // Inn 3: Pakistan 4/0d -> lead by 10 -> Target 11
        BallEvent(id: '6', matchId: 'test-1', inningsNumber: 3, sequenceNumber: 6, striker: 'P1', nonStriker: 'P2', bowler: 'E1', runsOffBat: 4, createdAt: now),

        // Inn 4: England chase 12/0 (win by 2 wickets)
        BallEvent(id: '7', matchId: 'test-1', inningsNumber: 4, sequenceNumber: 7, striker: 'E1', nonStriker: 'E2', bowler: 'P1', runsOffBat: 6, createdAt: now),
        BallEvent(id: '8', matchId: 'test-1', inningsNumber: 4, sequenceNumber: 8, striker: 'E1', nonStriker: 'E2', bowler: 'P1', runsOffBat: 6, createdAt: now),
      ];

      final state = CricketEngine.derive(cfg, events);
      expect(state.innings1.scoreText, '10/0d');
      expect(state.innings2!.scoreText, '4/2');
      expect(state.innings3!.scoreText, '4/0d');
      expect(state.innings4!.target, 11);
      expect(state.status, MatchStatus.completed);
      expect(state.resultSummary, 'England won by 2 wickets');
    });

    test('handles follow-on innings victory', () {
      final now = DateTime(2026, 11, 22);
      final cfg = MatchConfig(
        id: 'test-2',
        teamA: 'Pakistan',
        teamB: 'England',
        oversLimit: 0,
        playersPerSide: 2, // 1 wicket = all out
        formatLabel: 'TEST',
        battingFirstTeam: 'Pakistan',
        openingStrikerInnings1: 'P1',
        openingNonStrikerInnings1: 'P2',
        openingBowlerInnings1: 'E1',
        openingStrikerInnings2: 'E1',
        openingNonStrikerInnings2: 'E2',
        openingBowlerInnings2: 'P1',
        isTestMatch: true,
        declaredInnings: const [1],
        followOnEnforced: true,
        createdAt: now,
      );

      final events = <BallEvent>[
        // Inn 1: Pakistan 12/0d
        BallEvent(id: '1', matchId: 'test-2', inningsNumber: 1, sequenceNumber: 1, striker: 'P1', nonStriker: 'P2', bowler: 'E1', runsOffBat: 6, createdAt: now),
        BallEvent(id: '2', matchId: 'test-2', inningsNumber: 1, sequenceNumber: 2, striker: 'P1', nonStriker: 'P2', bowler: 'E1', runsOffBat: 6, createdAt: now),
        // Inn 2: England 4/1 (all out)
        BallEvent(id: '3', matchId: 'test-2', inningsNumber: 2, sequenceNumber: 3, striker: 'E1', nonStriker: 'E2', bowler: 'P1', runsOffBat: 4, createdAt: now),
        BallEvent(id: '4', matchId: 'test-2', inningsNumber: 2, sequenceNumber: 4, striker: 'E1', nonStriker: 'E2', bowler: 'P1', isWicket: true, wicketType: WicketType.bowled, createdAt: now),
        // Inn 3 (follow-on): England 2/1 (all out, total 6 vs 12 -> lost by an innings and 6 runs)
        BallEvent(id: '5', matchId: 'test-2', inningsNumber: 3, sequenceNumber: 5, striker: 'E1', nonStriker: 'E2', bowler: 'P1', runsOffBat: 2, createdAt: now),
        BallEvent(id: '6', matchId: 'test-2', inningsNumber: 3, sequenceNumber: 6, striker: 'E1', nonStriker: 'E2', bowler: 'P1', isWicket: true, wicketType: WicketType.bowled, createdAt: now),
      ];

      final state = CricketEngine.derive(cfg, events);
      expect(state.status, MatchStatus.completed);
      expect(state.resultSummary, 'Pakistan won by an innings and 6 runs');
    });
  });
}
