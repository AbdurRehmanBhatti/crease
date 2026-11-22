import 'package:flutter/foundation.dart';

import 'models.dart';

@immutable
class PlayerCareerStats {
  const PlayerCareerStats({
    required this.name,
    this.teamName,
    required this.matchesPlayed,
    required this.inningsBatted,
    required this.runs,
    required this.ballsFaced,
    required this.fours,
    required this.sixes,
    required this.notOuts,
    required this.highestScore,
    required this.highestNotOut,
    required this.fifties,
    required this.hundreds,
    required this.legalBallsBowled,
    required this.maidens,
    required this.runsConceded,
    required this.wickets,
    required this.bestBowlingWickets,
    required this.bestBowlingRuns,
    required this.fieldingDismissals,
  });

  final String name;
  final String? teamName;
  final int matchesPlayed;
  final int inningsBatted;
  final int runs;
  final int ballsFaced;
  final int fours;
  final int sixes;
  final int notOuts;
  final int highestScore;
  final bool highestNotOut;
  final int fifties;
  final int hundreds;
  final int legalBallsBowled;
  final int maidens;
  final int runsConceded;
  final int wickets;
  final int bestBowlingWickets;
  final int bestBowlingRuns;
  final int fieldingDismissals;

  int get dismissals => (inningsBatted - notOuts).clamp(0, inningsBatted);
  double get battingAverage =>
      dismissals == 0 ? runs.toDouble() : runs / dismissals;
  double get strikeRate =>
      ballsFaced == 0 ? 0.0 : (runs / ballsFaced) * 100.0;

  String get oversBowledText =>
      '${legalBallsBowled ~/ 6}.${legalBallsBowled % 6}';
  double get economy =>
      legalBallsBowled == 0 ? 0.0 : runsConceded / (legalBallsBowled / 6.0);
  String get bestBowlingText =>
      bestBowlingWickets == 0 && legalBallsBowled == 0
          ? '—'
          : '$bestBowlingWickets/$bestBowlingRuns';

  String get highestScoreText =>
      inningsBatted == 0 ? '—' : '$highestScore${highestNotOut ? '*' : ''}';

  /// Transparent, deterministic MVP formula derived purely from match events.
  int get mvpPoints =>
      runs +
      fours +
      (sixes * 2) +
      (fifties * 10) +
      (hundreds * 25) +
      (wickets * 20) +
      (maidens * 10) +
      (fieldingDismissals * 8);
}

class StatsEngine {
  StatsEngine._();

  static List<PlayerCareerStats> derive(
    List<DerivedMatchState> matches, {
    String? tournamentId,
    String? teamName,
    bool excludeDemo = false,
  }) {
    final filtered = matches.where((m) {
      if (excludeDemo && m.config.isDemo) return false;
      if (tournamentId != null && m.config.tournamentId != tournamentId) {
        return false;
      }
      return true;
    }).toList();

    final teamLower = teamName?.trim().toLowerCase();

    final map = <String, _MutableCareer>{};
    _MutableCareer ensure(String name, {String? team}) {
      final p = map.putIfAbsent(name, () => _MutableCareer(name));
      if (team != null && team.isNotEmpty) p.teamName = team;
      return p;
    }

    for (final match in filtered) {
      final participants = <String>{};
      final inningsList = match.allInnings;

      for (final inn in inningsList) {
        final includeBatting = teamLower == null ||
            inn.battingTeam.toLowerCase() == teamLower;
        final includeBowling = teamLower == null ||
            inn.bowlingTeam.toLowerCase() == teamLower;

        if (includeBatting) {
          for (final b in inn.batters) {
            if (b.balls == 0 && !b.isOut && b.runs == 0) continue;
            participants.add(b.name);
            final p = ensure(b.name, team: inn.battingTeam);
            p.inningsBatted += 1;
            p.runs += b.runs;
            p.ballsFaced += b.balls;
            p.fours += b.fours;
            p.sixes += b.sixes;
            if (!b.isOut) p.notOuts += 1;
            if (b.runs >= 100) {
              p.hundreds += 1;
            } else if (b.runs >= 50) {
              p.fifties += 1;
            }
            if (b.runs > p.highestScore ||
                (b.runs == p.highestScore && !b.isOut && !p.highestNotOut)) {
              p.highestScore = b.runs;
              p.highestNotOut = !b.isOut;
            }
          }
        }

        if (includeBowling) {
          for (final bw in inn.bowlers) {
            if (bw.legalBalls == 0 && bw.runsConceded == 0 && bw.wickets == 0) {
              continue;
            }
            participants.add(bw.name);
            final p = ensure(bw.name, team: inn.bowlingTeam);
            p.legalBallsBowled += bw.legalBalls;
            p.maidens += bw.maidens;
            p.runsConceded += bw.runsConceded;
            p.wickets += bw.wickets;
            if (bw.wickets > p.bestBowlingWickets ||
                (bw.wickets == p.bestBowlingWickets &&
                    (p.bestBowlingRuns == -1 ||
                        bw.runsConceded < p.bestBowlingRuns))) {
              p.bestBowlingWickets = bw.wickets;
              p.bestBowlingRuns = bw.runsConceded;
            }
          }

          // Credit fielding dismissals from the ball log
          for (final ov in inn.overs) {
            for (final ball in ov.balls) {
              if (ball.isWicket &&
                  ball.fielder != null &&
                  ball.fielder!.trim().isNotEmpty) {
                final fName = ball.fielder!.trim();
                participants.add(fName);
                ensure(fName, team: inn.bowlingTeam).fieldingDismissals += 1;
              }
            }
          }
        }
      }

      for (final name in participants) {
        ensure(name).matchesPlayed += 1;
      }
    }

    return map.values.map((m) => m.toStats()).toList();
  }

  static List<PlayerCareerStats> byMvp(List<PlayerCareerStats> all) =>
      List<PlayerCareerStats>.from(all)
        ..sort((a, b) {
          final cmp = b.mvpPoints.compareTo(a.mvpPoints);
          if (cmp != 0) return cmp;
          return b.runs.compareTo(a.runs);
        });

  static List<PlayerCareerStats> byRuns(List<PlayerCareerStats> all) =>
      all.where((p) => p.inningsBatted > 0).toList()
        ..sort((a, b) {
          final cmp = b.runs.compareTo(a.runs);
          if (cmp != 0) return cmp;
          return b.strikeRate.compareTo(a.strikeRate);
        });

  static List<PlayerCareerStats> byWickets(List<PlayerCareerStats> all) =>
      all.where((p) => p.legalBallsBowled > 0 || p.wickets > 0).toList()
        ..sort((a, b) {
          final cmp = b.wickets.compareTo(a.wickets);
          if (cmp != 0) return cmp;
          return a.economy.compareTo(b.economy);
        });

  static List<PlayerCareerStats> bySixes(List<PlayerCareerStats> all) =>
      all.where((p) => p.sixes > 0 || p.fours > 0).toList()
        ..sort((a, b) {
          final sCmp = b.sixes.compareTo(a.sixes);
          if (sCmp != 0) return sCmp;
          return b.fours.compareTo(a.fours);
        });
}

class _MutableCareer {
  _MutableCareer(this.name);
  final String name;
  String? teamName;
  int matchesPlayed = 0;
  int inningsBatted = 0;
  int runs = 0;
  int ballsFaced = 0;
  int fours = 0;
  int sixes = 0;
  int notOuts = 0;
  int highestScore = 0;
  bool highestNotOut = false;
  int fifties = 0;
  int hundreds = 0;
  int legalBallsBowled = 0;
  int maidens = 0;
  int runsConceded = 0;
  int wickets = 0;
  int bestBowlingWickets = 0;
  int bestBowlingRuns = -1;
  int fieldingDismissals = 0;

  PlayerCareerStats toStats() => PlayerCareerStats(
        name: name,
        teamName: teamName,
        matchesPlayed: matchesPlayed,
        inningsBatted: inningsBatted,
        runs: runs,
        ballsFaced: ballsFaced,
        fours: fours,
        sixes: sixes,
        notOuts: notOuts,
        highestScore: highestScore,
        highestNotOut: highestNotOut,
        fifties: fifties,
        hundreds: hundreds,
        legalBallsBowled: legalBallsBowled,
        maidens: maidens,
        runsConceded: runsConceded,
        wickets: wickets,
        bestBowlingWickets: bestBowlingWickets,
        bestBowlingRuns: bestBowlingRuns < 0 ? 0 : bestBowlingRuns,
        fieldingDismissals: fieldingDismissals,
      );
}
