import 'package:crease/domain/cricket_engine.dart';
import 'package:crease/domain/models.dart';
import 'package:crease/domain/tournament_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper to create a clean completed 1-over match where [winner] defeats [loser].
DerivedMatchState _completedMatch({
  required String id,
  required String tournamentId,
  required String winner,
  required String loser,
  int winnerRuns = 12,
  int loserRuns = 6,
  MatchStage stage = MatchStage.league,
  int? fixtureIndex,
}) {
  final now = DateTime(2026, 11, 23);
  final cfg = MatchConfig(
    id: id,
    teamA: winner,
    teamB: loser,
    oversLimit: 1,
    playersPerSide: 5,
    formatLabel: '1OV',
    battingFirstTeam: winner,
    openingStrikerInnings1: 'A1',
    openingNonStrikerInnings1: 'A2',
    openingBowlerInnings1: 'B1',
    openingStrikerInnings2: 'B1',
    openingNonStrikerInnings2: 'B2',
    openingBowlerInnings2: 'A1',
    tournamentId: tournamentId,
    tournamentStage: stage.name,
    fixtureIndex: fixtureIndex,
    createdAt: now,
  );

  // Build 6 legal balls for innings 1 totaling winnerRuns, and 6 legal balls for innings 2 totaling loserRuns
  List<BallEvent> inningsBalls(int inn, int totalRuns, int startSeq) {
    final list = <BallEvent>[];
    var rem = totalRuns;
    for (var i = 0; i < 6; i++) {
      final r = rem >= 6
          ? 6
          : rem >= 4
              ? 4
              : rem >= 2
                  ? 2
                  : rem >= 1
                      ? 1
                      : 0;
      rem -= r;
      list.add(
        BallEvent(
          id: '$id-$inn-$i',
          matchId: id,
          inningsNumber: inn,
          sequenceNumber: startSeq + i,
          striker: inn == 1 ? 'A1' : 'B1',
          nonStriker: inn == 1 ? 'A2' : 'B2',
          bowler: inn == 1 ? 'B1' : 'A1',
          runsOffBat: r,
          createdAt: now,
        ),
      );
    }
    return list;
  }

  final events = [
    ...inningsBalls(1, winnerRuns, 1),
    ...inningsBalls(2, loserRuns, 7),
  ];
  final derived = CricketEngine.derive(cfg, events);
  expect(derived.status, MatchStatus.completed);
  return derived;
}

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
      final events = <BallEvent>[
        BallEvent(id: '1', matchId: 'm1', inningsNumber: 1, sequenceNumber: 1, striker: 'A1', nonStriker: 'A2', bowler: 'B1', runsOffBat: 4, createdAt: now),
        BallEvent(id: '2', matchId: 'm1', inningsNumber: 1, sequenceNumber: 2, striker: 'A1', nonStriker: 'A2', bowler: 'B1', runsOffBat: 4, createdAt: now),
        BallEvent(id: '3', matchId: 'm1', inningsNumber: 1, sequenceNumber: 3, striker: 'A1', nonStriker: 'A2', bowler: 'B1', runsOffBat: 4, createdAt: now),
        BallEvent(id: '4', matchId: 'm1', inningsNumber: 1, sequenceNumber: 4, striker: 'A1', nonStriker: 'A2', bowler: 'B1', runsOffBat: 0, createdAt: now),
        BallEvent(id: '5', matchId: 'm1', inningsNumber: 1, sequenceNumber: 5, striker: 'A1', nonStriker: 'A2', bowler: 'B1', isWicket: true, wicketType: WicketType.bowled, nextBatter: 'A3', createdAt: now),
        BallEvent(id: '6', matchId: 'm1', inningsNumber: 1, sequenceNumber: 6, striker: 'A3', nonStriker: 'A2', bowler: 'B1', isWicket: true, wicketType: WicketType.bowled, createdAt: now),
        BallEvent(id: '7', matchId: 'm1', inningsNumber: 2, sequenceNumber: 7, striker: 'B1', nonStriker: 'B2', bowler: 'A1', runsOffBat: 6, createdAt: now),
        BallEvent(id: '8', matchId: 'm1', inningsNumber: 2, sequenceNumber: 8, striker: 'B1', nonStriker: 'B2', bowler: 'A1', runsOffBat: 6, createdAt: now),
        BallEvent(id: '9', matchId: 'm1', inningsNumber: 2, sequenceNumber: 9, striker: 'B1', nonStriker: 'B2', bowler: 'A1', runsOffBat: 1, createdAt: now),
      ];

      final derived = CricketEngine.derive(cfg, events);
      expect(derived.status, MatchStatus.completed);

      final table = TournamentEngine.deriveStandings(tournament, [derived]);
      expect(table.length, 3);

      expect(table[0].teamName, 'Kites');
      expect(table[0].points, 2);
      expect(table[0].won, 1);
      expect(table[0].nrr, closeTo(20.0, 0.001));

      expect(table[1].teamName, 'Stars');
      expect(table[1].points, 0);
      expect(table[1].nrr, 0.0);

      expect(table[2].teamName, 'Lions');
      expect(table[2].points, 0);
      expect(table[2].lost, 1);
      expect(table[2].nrr, closeTo(-20.0, 0.001));
    });
  });

  group('TournamentEngine fixtures, knockouts & champion', () {
    test('Circle Method schedules balanced round-robin pairs without duplicates', () {
      final pairs4 = TournamentEngine.generateRoundRobinPairs(
        ['A', 'B', 'C', 'D'],
        roundsPerPair: 1,
      );
      expect(pairs4.length, 6);
      // 3 rounds, 2 matches per round, each team plays once per round
      for (var r = 1; r <= 3; r++) {
        final inRound = pairs4.where((p) => p.round == r).toList();
        expect(inRound.length, 2);
        final seen = <String>{};
        for (final m in inRound) {
          seen.add(m.teamA);
          seen.add(m.teamB);
        }
        expect(seen.length, 4);
      }

      final pairs3Double = TournamentEngine.generateRoundRobinPairs(
        ['A', 'B', 'C'],
        roundsPerPair: 2,
      );
      expect(pairs3Double.length, 6);
    });

    test('League + Knockouts seeds SF (#1v#4, #2v#3), isolates NRR, and crowns Champion', () {
      final t = Tournament(
        id: 't-ko',
        name: 'Ramadan Cup',
        oversLimit: 1,
        playersPerSide: 5,
        formatLabel: '1OV',
        teamRosters: const {
          'Alpha': [],
          'Beta': [],
          'Gamma': [],
          'Delta': [],
        },
        structure: TournamentStructure.leagueKnockout,
        roundsPerPair: 1,
        knockoutQualifiers: 4,
        createdAt: DateTime(2026, 11, 23),
      );

      final counts = TournamentEngine.plannedMatchCounts(
        teamCount: 4,
        structure: TournamentStructure.leagueKnockout,
        roundsPerPair: 1,
        knockoutQualifiers: 4,
      );
      expect(counts.league, 6);
      expect(counts.knockout, 3);
      expect(counts.total, 9);

      // Before any matches: knockouts are locked
      final initial = TournamentEngine.deriveOverview(t, const []);
      expect(initial.leagueFixtures.length, 6);
      expect(initial.knockoutFixtures.length, 3);
      expect(initial.knockoutsUnlocked, isFalse);
      expect(initial.knockoutFixtures.first.lockedReason, isNotNull);

      // Play all 6 league fixtures so final order is Alpha (6pts), Beta (4pts), Gamma (2pts), Delta (0pts)
      const rankOrder = ['Alpha', 'Beta', 'Gamma', 'Delta'];
      final leagueMatches = <DerivedMatchState>[];
      for (final f in initial.leagueFixtures) {
        final aRank = rankOrder.indexOf(f.teamA!);
        final bRank = rankOrder.indexOf(f.teamB!);
        final winner = aRank < bRank ? f.teamA! : f.teamB!;
        final loser = winner == f.teamA ? f.teamB! : f.teamA!;
        leagueMatches.add(
          _completedMatch(
            id: 'lm-${f.fixtureIndex}',
            tournamentId: t.id,
            winner: winner,
            loser: loser,
            stage: MatchStage.league,
            fixtureIndex: f.fixtureIndex,
          ),
        );
      }

      final afterLeague = TournamentEngine.deriveOverview(t, leagueMatches);
      expect(afterLeague.leagueComplete, isTrue);
      expect(afterLeague.knockoutsUnlocked, isTrue);
      expect(afterLeague.standings.map((r) => r.teamName).toList(), rankOrder);

      // SF 1: #1 Alpha vs #4 Delta; SF 2: #2 Beta vs #3 Gamma
      final sf1 = afterLeague.knockoutFixtures[0];
      final sf2 = afterLeague.knockoutFixtures[1];
      final finalFix = afterLeague.knockoutFixtures[2];
      expect(sf1.teamA, 'Alpha');
      expect(sf1.teamB, 'Delta');
      expect(sf1.isReadyToStart, isTrue);
      expect(sf2.teamA, 'Beta');
      expect(sf2.teamB, 'Gamma');
      expect(sf2.isReadyToStart, isTrue);
      expect(finalFix.isReadyToStart, isFalse);

      // Upset in SF1: Delta beats Alpha; Beta beats Gamma in SF2
      final sfMatches = [
        _completedMatch(
          id: 'sf1',
          tournamentId: t.id,
          winner: 'Delta',
          loser: 'Alpha',
          stage: MatchStage.semiFinal,
          fixtureIndex: sf1.fixtureIndex,
        ),
        _completedMatch(
          id: 'sf2',
          tournamentId: t.id,
          winner: 'Beta',
          loser: 'Gamma',
          stage: MatchStage.semiFinal,
          fixtureIndex: sf2.fixtureIndex,
        ),
      ];

      final afterSemis = TournamentEngine.deriveOverview(
        t,
        [...leagueMatches, ...sfMatches],
      );
      // Standings must NOT be distorted by knockout matches!
      expect(afterSemis.standings.first.teamName, 'Alpha');
      expect(afterSemis.standings.first.played, 3);
      expect(afterSemis.standings.last.teamName, 'Delta');
      expect(afterSemis.standings.last.points, 0);

      // Final auto-populated with Delta vs Beta
      final readyFinal = afterSemis.knockoutFixtures[2];
      expect(readyFinal.teamA, 'Delta');
      expect(readyFinal.teamB, 'Beta');
      expect(readyFinal.isReadyToStart, isTrue);

      // Delta wins the Final -> Champion!
      final finalMatch = _completedMatch(
        id: 'final',
        tournamentId: t.id,
        winner: 'Delta',
        loser: 'Beta',
        stage: MatchStage.finalMatch,
        fixtureIndex: readyFinal.fixtureIndex,
      );
      final done = TournamentEngine.deriveOverview(
        t,
        [...leagueMatches, ...sfMatches, finalMatch],
      );
      expect(done.champion, 'Delta');
    });

    test('Pure Knockout bracket handles 3 teams with top-seed bye and crowns Champion', () {
      final t = Tournament(
        id: 't-pure-ko',
        name: 'Knockout Cup',
        oversLimit: 1,
        playersPerSide: 5,
        formatLabel: '1OV',
        teamRosters: const {
          'Bhatti XI': [],
          'LHR Lions': [],
          'Street XI': [],
        },
        structure: TournamentStructure.knockout,
        createdAt: DateTime(2026, 11, 23),
      );

      final init = TournamentEngine.deriveOverview(t, const []);
      // 3 teams -> 1 Semi-Final (LHR Lions v Street XI) + Final (Bhatti XI [bye] v Winner SF 1)
      expect(init.knockoutFixtures.length, 2);
      expect(init.knockoutFixtures[0].teamA, 'LHR Lions');
      expect(init.knockoutFixtures[0].teamB, 'Street XI');
      expect(init.knockoutFixtures[0].isReadyToStart, isTrue);
      expect(init.knockoutFixtures[1].teamA, 'Bhatti XI');
      expect(init.knockoutFixtures[1].teamB, isNull);
      expect(init.knockoutFixtures[1].lockedReason, isNotNull);

      final sf = _completedMatch(
        id: 'ko-sf',
        tournamentId: t.id,
        winner: 'Street XI',
        loser: 'LHR Lions',
        stage: MatchStage.semiFinal,
        fixtureIndex: init.knockoutFixtures[0].fixtureIndex,
      );
      final afterSf = TournamentEngine.deriveOverview(t, [sf]);
      expect(afterSf.knockoutFixtures[1].teamA, 'Bhatti XI');
      expect(afterSf.knockoutFixtures[1].teamB, 'Street XI');
      expect(afterSf.knockoutFixtures[1].isReadyToStart, isTrue);

      final fin = _completedMatch(
        id: 'ko-fin',
        tournamentId: t.id,
        winner: 'Bhatti XI',
        loser: 'Street XI',
        stage: MatchStage.finalMatch,
        fixtureIndex: afterSf.knockoutFixtures[1].fixtureIndex,
      );
      final finished = TournamentEngine.deriveOverview(t, [sf, fin]);
      expect(finished.champion, 'Bhatti XI');
    });

    test('Tied or abandoned Semi-Final advances higher league seed without deadlocking Final', () {
      final t = Tournament(
        id: 't-ko-tie',
        name: 'Monsoon Cup',
        oversLimit: 1,
        playersPerSide: 5,
        formatLabel: '1OV',
        teamRosters: const {
          'Alpha': [],
          'Beta': [],
          'Gamma': [],
          'Delta': [],
        },
        structure: TournamentStructure.leagueKnockout,
        roundsPerPair: 1,
        knockoutQualifiers: 4,
        createdAt: DateTime(2026, 11, 24),
      );

      final init = TournamentEngine.deriveOverview(t, const []);
      const rankOrder = ['Alpha', 'Beta', 'Gamma', 'Delta'];
      final leagueMatches = <DerivedMatchState>[];
      for (final f in init.leagueFixtures) {
        final aIdx = rankOrder.indexOf(f.teamA!);
        final bIdx = rankOrder.indexOf(f.teamB!);
        final winner = aIdx < bIdx ? f.teamA! : f.teamB!;
        final loser = aIdx < bIdx ? f.teamB! : f.teamA!;
        leagueMatches.add(
          _completedMatch(
            id: 'lm-tie-${f.fixtureIndex}',
            tournamentId: t.id,
            winner: winner,
            loser: loser,
            stage: MatchStage.league,
            fixtureIndex: f.fixtureIndex,
          ),
        );
      }

      final afterLeague = TournamentEngine.deriveOverview(t, leagueMatches);
      final sf1 = afterLeague.knockoutFixtures[0]; // #1 Alpha vs #4 Delta
      final sf2 = afterLeague.knockoutFixtures[1]; // #2 Beta vs #3 Gamma

      // SF1 abandoned (washout) -> higher seed Alpha advances!
      final abandonedSf1Config = MatchConfig(
        id: 'sf1-washout',
        teamA: 'Alpha',
        teamB: 'Delta',
        oversLimit: 1,
        playersPerSide: 5,
        formatLabel: '1OV',
        battingFirstTeam: 'Alpha',
        openingStrikerInnings1: 'A1',
        openingNonStrikerInnings1: 'A2',
        openingBowlerInnings1: 'D1',
        tournamentId: t.id,
        tournamentStage: MatchStage.semiFinal.name,
        fixtureIndex: sf1.fixtureIndex,
        declaredInnings: const [-1],
        createdAt: DateTime(2026, 11, 24),
      );
      final sf1Washout = CricketEngine.derive(abandonedSf1Config, const []);

      // SF2 normal win for Gamma
      final sf2Win = _completedMatch(
        id: 'sf2-win',
        tournamentId: t.id,
        winner: 'Gamma',
        loser: 'Beta',
        stage: MatchStage.semiFinal,
        fixtureIndex: sf2.fixtureIndex,
      );

      final afterSemis = TournamentEngine.deriveOverview(
        t,
        [...leagueMatches, sf1Washout, sf2Win],
      );
      final finalFix = afterSemis.knockoutFixtures[2];
      expect(finalFix.teamA, 'Alpha');
      expect(finalFix.teamB, 'Gamma');
      expect(finalFix.isReadyToStart, isTrue);
    });
  });
}
