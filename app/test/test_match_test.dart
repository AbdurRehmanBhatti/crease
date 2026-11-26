import 'package:crease/domain/cricket_engine.dart';
import 'package:crease/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const players = {
    'p1': 'P1',
    'p2': 'P2',
    'e1': 'E1',
    'e2': 'E2',
    'e3': 'E3',
  };

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
        battingFirstSide: MatchSide.a,
        openingStriker1Id: 'p1',
        openingNonStriker1Id: 'p2',
        openingBowler1Id: 'e1',
        openingStriker2Id: 'e1',
        openingNonStriker2Id: 'e2',
        openingBowler2Id: 'p1',
        adHocPlayers: players,
        isTestMatch: true,
        declaredInnings: const [1, 3],
        createdAt: now,
      );

      final events = <BallEvent>[
        // Inn 1: Pakistan 10/0d
        BallEvent(id: '1', matchId: 'test-1', inningsNumber: 1, sequenceNumber: 1, strikerId: 'p1', nonStrikerId: 'p2', bowlerId: 'e1', runsOffBat: 6, createdAt: now),
        BallEvent(id: '2', matchId: 'test-1', inningsNumber: 1, sequenceNumber: 2, strikerId: 'p1', nonStrikerId: 'p2', bowlerId: 'e1', runsOffBat: 4, createdAt: now),

        // Inn 2: England 4/2 (all out, trail by 6)
        BallEvent(id: '3', matchId: 'test-1', inningsNumber: 2, sequenceNumber: 3, strikerId: 'e1', nonStrikerId: 'e2', bowlerId: 'p1', runsOffBat: 4, createdAt: now),
        BallEvent(id: '4', matchId: 'test-1', inningsNumber: 2, sequenceNumber: 4, strikerId: 'e1', nonStrikerId: 'e2', bowlerId: 'p1', isWicket: true, wicketType: WicketType.bowled, nextBatterId: 'e3', createdAt: now),
        BallEvent(id: '5', matchId: 'test-1', inningsNumber: 2, sequenceNumber: 5, strikerId: 'e3', nonStrikerId: 'e2', bowlerId: 'p1', isWicket: true, wicketType: WicketType.bowled, createdAt: now),

        // Inn 3: Pakistan 4/0d -> lead by 10 -> Target 11
        BallEvent(id: '6', matchId: 'test-1', inningsNumber: 3, sequenceNumber: 6, strikerId: 'p1', nonStrikerId: 'p2', bowlerId: 'e1', runsOffBat: 4, createdAt: now),

        // Inn 4: England chase 12/0 (win by 2 wickets)
        BallEvent(id: '7', matchId: 'test-1', inningsNumber: 4, sequenceNumber: 7, strikerId: 'e1', nonStrikerId: 'e2', bowlerId: 'p1', runsOffBat: 6, createdAt: now),
        BallEvent(id: '8', matchId: 'test-1', inningsNumber: 4, sequenceNumber: 8, strikerId: 'e1', nonStrikerId: 'e2', bowlerId: 'p1', runsOffBat: 6, createdAt: now),
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
        battingFirstSide: MatchSide.a,
        openingStriker1Id: 'p1',
        openingNonStriker1Id: 'p2',
        openingBowler1Id: 'e1',
        openingStriker2Id: 'e1',
        openingNonStriker2Id: 'e2',
        openingBowler2Id: 'p1',
        adHocPlayers: players,
        isTestMatch: true,
        declaredInnings: const [1],
        followOnEnforced: true,
        createdAt: now,
      );

      final events = <BallEvent>[
        // Inn 1: Pakistan 12/0d
        BallEvent(id: '1', matchId: 'test-2', inningsNumber: 1, sequenceNumber: 1, strikerId: 'p1', nonStrikerId: 'p2', bowlerId: 'e1', runsOffBat: 6, createdAt: now),
        BallEvent(id: '2', matchId: 'test-2', inningsNumber: 1, sequenceNumber: 2, strikerId: 'p1', nonStrikerId: 'p2', bowlerId: 'e1', runsOffBat: 6, createdAt: now),
        // Inn 2: England 4/1 (all out)
        BallEvent(id: '3', matchId: 'test-2', inningsNumber: 2, sequenceNumber: 3, strikerId: 'e1', nonStrikerId: 'e2', bowlerId: 'p1', runsOffBat: 4, createdAt: now),
        BallEvent(id: '4', matchId: 'test-2', inningsNumber: 2, sequenceNumber: 4, strikerId: 'e1', nonStrikerId: 'e2', bowlerId: 'p1', isWicket: true, wicketType: WicketType.bowled, createdAt: now),
        // Inn 3 (follow-on): England 2/1 (all out, total 6 vs 12 -> lost by an innings and 6 runs)
        BallEvent(id: '5', matchId: 'test-2', inningsNumber: 3, sequenceNumber: 5, strikerId: 'e1', nonStrikerId: 'e2', bowlerId: 'p1', runsOffBat: 2, createdAt: now),
        BallEvent(id: '6', matchId: 'test-2', inningsNumber: 3, sequenceNumber: 6, strikerId: 'e1', nonStrikerId: 'e2', bowlerId: 'p1', isWicket: true, wicketType: WicketType.bowled, createdAt: now),
      ];

      final state = CricketEngine.derive(cfg, events);
      expect(state.status, MatchStatus.completed);
      expect(state.resultSummary, 'Pakistan won by an innings and 6 runs');
    });
  });
}
