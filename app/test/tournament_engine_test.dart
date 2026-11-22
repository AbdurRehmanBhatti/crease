import 'package:crease/domain/cricket_engine.dart';
import 'package:crease/domain/models.dart';
import 'package:crease/domain/tournament_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TournamentEngine standings & ICC NRR', () {
    test('calculates points and ICC NRR (including all-out full-overs rule)', () {
      final tournament = Tournament(
        id: 't1',
        name: 'Cup',
        oversLimit: 2,
        playersPerSide: 3, // 2 wickets = all out
        formatLabel: '2OV',
        teamRosters: const {
          'Lions': [],
          'Kites': [],
          'Stars': [],
        },
        createdAt: DateTime(2026, 11, 21),
      );

      final cfg = MatchConfig(
        id: 'm1',
        teamA: 'Lions',
        teamB: 'Kites',
        oversLimit: 2,
        playersPerSide: 3, // 2 wickets = all out
        formatLabel: '2OV',
        battingFirstTeam: 'Lions',
        openingStrikerInnings1: 'A1',
        openingNonStrikerInnings1: 'A2',
        openingBowlerInnings1: 'B1',
        openingStrikerInnings2: 'B1',
        openingNonStrikerInnings2: 'B2',
        openingBowlerInnings2: 'A1',
        tournamentId: 't1',
        createdAt: DateTime(2026, 11, 21),
      );

      final now = DateTime(2026, 11, 21);
      // Innings 1: Lions score 12/2 (all out in 1.0 over -> counts as FULL 2.0 overs for NRR = 6.00 RPO)
      // Innings 2: Kites chase 13/0 in 1.0 over (6 balls -> 13.00 RPO)
      // Expected Kites NRR: 13.0 - 6.0 = +7.000; Lions NRR: 6.0 - 13.0 = -7.000
      final events = <BallEvent>[
        // Inn 1: 6 balls -> 4, 4, 4, 0, W, W (12/2 in 1.0 ov, all out)
        BallEvent(id: '1', matchId: 'm1', inningsNumber: 1, sequenceNumber: 1, striker: 'A1', nonStriker: 'A2', bowler: 'B1', runsOffBat: 4, createdAt: now),
        BallEvent(id: '2', matchId: 'm1', inningsNumber: 1, sequenceNumber: 2, striker: 'A1', nonStriker: 'A2', bowler: 'B1', runsOffBat: 4, createdAt: now),
        BallEvent(id: '3', matchId: 'm1', inningsNumber: 1, sequenceNumber: 3, striker: 'A1', nonStriker: 'A2', bowler: 'B1', runsOffBat: 4, createdAt: now),
        BallEvent(id: '4', matchId: 'm1', inningsNumber: 1, sequenceNumber: 4, striker: 'A1', nonStriker: 'A2', bowler: 'B1', runsOffBat: 0, createdAt: now),
        BallEvent(id: '5', matchId: 'm1', inningsNumber: 1, sequenceNumber: 5, striker: 'A1', nonStriker: 'A2', bowler: 'B1', isWicket: true, wicketType: WicketType.bowled, nextBatter: 'A3', createdAt: now),
        BallEvent(id: '6', matchId: 'm1', inningsNumber: 1, sequenceNumber: 6, striker: 'A3', nonStriker: 'A2', bowler: 'B1', isWicket: true, wicketType: WicketType.bowled, createdAt: now),

        // Inn 2: Kites hit 6, 6, 1 in 3 balls (0.3 ov = 0.5 overs -> 13 / 0.5 = 26.0 RPO)
        BallEvent(id: '7', matchId: 'm1', inningsNumber: 2, sequenceNumber: 7, striker: 'B1', nonStriker: 'B2', bowler: 'A1', runsOffBat: 6, createdAt: now),
        BallEvent(id: '8', matchId: 'm1', inningsNumber: 2, sequenceNumber: 8, striker: 'B1', nonStriker: 'B2', bowler: 'A1', runsOffBat: 6, createdAt: now),
        BallEvent(id: '9', matchId: 'm1', inningsNumber: 2, sequenceNumber: 9, striker: 'B1', nonStriker: 'B2', bowler: 'A1', runsOffBat: 1, createdAt: now),
      ];

      final derived = CricketEngine.derive(cfg, events);
      expect(derived.status, MatchStatus.completed);

      final table = TournamentEngine.deriveStandings(tournament, [derived]);
      expect(table.length, 3);

      // 1st: Kites (2 pts, NRR = 26.0 - 6.0 = +20.000)
      expect(table[0].teamName, 'Kites');
      expect(table[0].points, 2);
      expect(table[0].won, 1);
      expect(table[0].nrr, closeTo(20.0, 0.001));

      // 2nd: Stars (0 pts, 0.000 NRR)
      expect(table[1].teamName, 'Stars');
      expect(table[1].points, 0);
      expect(table[1].nrr, 0.0);

      // 3rd: Lions (0 pts, NRR = 6.0 - 26.0 = -20.000)
      expect(table[2].teamName, 'Lions');
      expect(table[2].points, 0);
      expect(table[2].lost, 1);
      expect(table[2].nrr, closeTo(-20.0, 0.001));
    });
  });
}
