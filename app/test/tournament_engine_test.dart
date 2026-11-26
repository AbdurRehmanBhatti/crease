import 'package:crease/domain/cricket_engine.dart';
import 'package:crease/domain/models.dart';
import 'package:crease/domain/tournament_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const _testPlayers = {
  'a1': 'A1',
  'a2': 'A2',
  'a3': 'A3',
  'b1': 'B1',
  'b2': 'B2',
  'd1': 'D1',
};

List<TournamentTeamEntry> _entries(String tournamentId, List<String> names) {
  final now = DateTime(2026, 11, 21);
  return [
    for (var i = 0; i < names.length; i++)
      TournamentTeamEntry(
        id: '$tournamentId-team-$i',
        tournamentId: tournamentId,
        adHocName: names[i],
        seedOrder: i,
        createdAt: now,
      ),
  ];
}

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
    battingFirstSide: MatchSide.a,
    openingStriker1Id: 'a1',
    openingNonStriker1Id: 'a2',
    openingBowler1Id: 'b1',
    openingStriker2Id: 'b1',
    openingNonStriker2Id: 'b2',
    openingBowler2Id: 'a1',
    adHocPlayers: _testPlayers,
    tournamentId: tournamentId,
    tournamentStage: stage.name,
    fixtureIndex: fixtureIndex,
    createdAt: now,
  );

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
          strikerId: inn == 1 ? 'a1' : 'b1',
          nonStrikerId: inn == 1 ? 'a2' : 'b2',
          bowlerId: inn == 1 ? 'b1' : 'a1',
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
        entries: _entries('t1', const ['Lions', 'Kites', 'Stars']),
        createdAt: DateTime(2026, 11, 21),
      );

      final cfg = MatchConfig(
        id: 'm1',
        teamA: 'Lions',
        teamB: 'Kites',
        oversLimit: 2,
        playersPerSide: 3,
        formatLabel: '2OV',
        battingFirstSide: MatchSide.a,
        openingStriker1Id: 'a1',
        openingNonStriker1Id: 'a2',
        openingBowler1Id: 'b1',
        openingStriker2Id: 'b1',
        openingNonStriker2Id: 'b2',
        openingBowler2Id: 'a1',
        adHocPlayers: _testPlayers,
        tournamentId: 't1',
        createdAt: DateTime(2026, 11, 21),
      );

      final now = DateTime(2026, 11, 21);
      final events = <BallEvent>[
        BallEvent(id: '1', matchId: 'm1', inningsNumber: 1, sequenceNumber: 1, strikerId: 'a1', nonStrikerId: 'a2', bowlerId: 'b1', runsOffBat: 4, createdAt: now),
        BallEvent(id: '2', matchId: 'm1', inningsNumber: 1, sequenceNumber: 2, strikerId: 'a1', nonStrikerId: 'a2', bowlerId: 'b1', runsOffBat: 4, createdAt: now),
        BallEvent(id: '3', matchId: 'm1', inningsNumber: 1, sequenceNumber: 3, strikerId: 'a1', nonStrikerId: 'a2', bowlerId: 'b1', runsOffBat: 4, createdAt: now),
        BallEvent(id: '4', matchId: 'm1', inningsNumber: 1, sequenceNumber: 4, strikerId: 'a1', nonStrikerId: 'a2', bowlerId: 'b1', runsOffBat: 0, createdAt: now),
        BallEvent(id: '5', matchId: 'm1', inningsNumber: 1, sequenceNumber: 5, strikerId: 'a1', nonStrikerId: 'a2', bowlerId: 'b1', isWicket: true, wicketType: WicketType.bowled, nextBatterId: 'a3', createdAt: now),
        BallEvent(id: '6', matchId: 'm1', inningsNumber: 1, sequenceNumber: 6, strikerId: 'a3', nonStrikerId: 'a2', bowlerId: 'b1', isWicket: true, wicketType: WicketType.bowled, createdAt: now),
        BallEvent(id: '7', matchId: 'm1', inningsNumber: 2, sequenceNumber: 7, strikerId: 'b1', nonStrikerId: 'b2', bowlerId: 'a1', runsOffBat: 6, createdAt: now),
        BallEvent(id: '8', matchId: 'm1', inningsNumber: 2, sequenceNumber: 8, strikerId: 'b1', nonStrikerId: 'b2', bowlerId: 'a1', runsOffBat: 6, createdAt: now),
        BallEvent(id: '9', matchId: 'm1', inningsNumber: 2, sequenceNumber: 9, strikerId: 'b1', nonStrikerId: 'b2', bowlerId: 'a1', runsOffBat: 1, createdAt: now),
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
        entries: _entries('t-ko', const ['Alpha', 'Beta', 'Gamma', 'Delta']),
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

      final initial = TournamentEngine.deriveOverview(t, const []);
      expect(initial.leagueFixtures.length, 6);
      expect(initial.knockoutFixtures.length, 3);
      expect(initial.knockoutsUnlocked, isFalse);
      expect(initial.knockoutFixtures.first.lockedReason, isNotNull);

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
      expect(afterSemis.standings.first.teamName, 'Alpha');
      expect(afterSemis.standings.first.played, 3);
      expect(afterSemis.standings.last.teamName, 'Delta');
      expect(afterSemis.standings.last.points, 0);

      final readyFinal = afterSemis.knockoutFixtures[2];
      expect(readyFinal.teamA, 'Delta');
      expect(readyFinal.teamB, 'Beta');
      expect(readyFinal.isReadyToStart, isTrue);

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
        entries: _entries('t-pure-ko', const ['Bhatti XI', 'LHR Lions', 'Street XI']),
        structure: TournamentStructure.knockout,
        createdAt: DateTime(2026, 11, 23),
      );

      final init = TournamentEngine.deriveOverview(t, const []);
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
        entries: _entries('t-ko-tie', const ['Alpha', 'Beta', 'Gamma', 'Delta']),
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
      final sf1 = afterLeague.knockoutFixtures[0];
      final sf2 = afterLeague.knockoutFixtures[1];

      final abandonedSf1Config = MatchConfig(
        id: 'sf1-washout',
        teamA: 'Alpha',
        teamB: 'Delta',
        oversLimit: 1,
        playersPerSide: 5,
        formatLabel: '1OV',
        battingFirstSide: MatchSide.a,
        openingStriker1Id: 'a1',
        openingNonStriker1Id: 'a2',
        openingBowler1Id: 'd1',
        adHocPlayers: _testPlayers,
        tournamentId: t.id,
        tournamentStage: MatchStage.semiFinal.name,
        fixtureIndex: sf1.fixtureIndex,
        declaredInnings: const [-1],
        createdAt: DateTime(2026, 11, 24),
      );
      final sf1Washout = CricketEngine.derive(abandonedSf1Config, const []);

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
