import 'package:flutter/foundation.dart';

import 'models.dart';

@immutable
class PlayerCareerStats {
  const PlayerCareerStats({
    required this.playerId,
    this.userId,
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
    this.thirties = 0,
    required this.fifties,
    required this.hundreds,
    this.ducks = 0,
    this.inningsBowled = 0,
    required this.legalBallsBowled,
    required this.maidens,
    required this.runsConceded,
    required this.wickets,
    required this.bestBowlingWickets,
    required this.bestBowlingRuns,
    required this.fieldingDismissals,
    this.catches = 0,
    this.stumpings = 0,
    this.runOuts = 0,
  });

  final String playerId;
  final String? userId;
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
  final int thirties;
  final int fifties;
  final int hundreds;
  final int ducks;
  final int inningsBowled;
  final int legalBallsBowled;
  final int maidens;
  final int runsConceded;
  final int wickets;
  final int bestBowlingWickets;
  final int bestBowlingRuns;
  final int fieldingDismissals;
  final int catches;
  final int stumpings;
  final int runOuts;

  int get dismissals => (inningsBatted - notOuts).clamp(0, inningsBatted);
  double get battingAverage =>
      dismissals == 0 ? runs.toDouble() : runs / dismissals;
  double get strikeRate =>
      ballsFaced == 0 ? 0.0 : (runs / ballsFaced) * 100.0;

  String get oversBowledText =>
      '${legalBallsBowled ~/ 6}.${legalBallsBowled % 6}';
  double get economy =>
      legalBallsBowled == 0 ? 0.0 : runsConceded / (legalBallsBowled / 6.0);
  double get bowlingAverage => wickets == 0 ? 0.0 : runsConceded / wickets;
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
    String? teamId,
    String? teamName,
    bool excludeDemo = false,
    bool excludePlaceholders = true,
    Map<String, String> playerNamesById = const {},
    Map<String, String> playerUserIdsById = const {},
  }) {
    final filtered = matches.where((m) {
      if (excludeDemo && m.config.isDemo) return false;
      if (tournamentId != null && m.config.tournamentId != tournamentId) {
        return false;
      }
      return true;
    }).toList();

    final hasTeamFilter = (teamId != null && teamId.trim().isNotEmpty) ||
        (teamName != null && teamName.trim().isNotEmpty);

    final map = <String, _MutableCareer>{};

    String identityKey(String playerId) {
      final uid = playerUserIdsById[playerId];
      if (uid != null && uid.isNotEmpty) return 'u:$uid';
      return 'p:$playerId';
    }

    String resolvedName(
      String playerId,
      String fallbackName,
      DerivedMatchState match,
    ) {
      return playerNamesById[playerId] ??
          match.resolvedPlayerNames[playerId] ??
          fallbackName;
    }

    _MutableCareer ensure(
      String playerId,
      String displayName, {
      String? team,
    }) {
      final key = identityKey(playerId);
      final uid = playerUserIdsById[playerId];
      final p = map.putIfAbsent(
        key,
        () => _MutableCareer(
          playerId: playerId,
          userId: uid,
          name: displayName,
        ),
      );
      if (displayName.isNotEmpty) p.name = displayName;
      if (team != null && team.isNotEmpty) p.teamName = team;
      return p;
    }

    for (final match in filtered) {
      MatchSide? matchedSide;
      if (hasTeamFilter) {
        matchedSide = match.config.sideForTeam(
          teamId: teamId,
          teamName: teamName,
        );
        if (matchedSide == null) continue;
      }
      final participants = <String, (String, String)>{};
      final inningsList = match.allInnings;

      for (final inn in inningsList) {
        if (!match.config.isTestMatch && inn.inningsNumber >= 3) continue;
        final includeBatting =
            matchedSide == null || inn.battingSide == matchedSide;
        final includeBowling =
            matchedSide == null || inn.bowlingSide == matchedSide;

        if (includeBatting) {
          for (final b in inn.batters) {
            if (b.balls == 0 && !b.isOut && b.runs == 0) continue;
            if (b.playerId.isEmpty) continue;
            final name = resolvedName(b.playerId, b.name, match);
            if (excludePlaceholders && isPlaceholderPlayerName(name)) continue;
            final key = identityKey(b.playerId);
            participants[key] = (b.playerId, name);
            final p = ensure(b.playerId, name, team: inn.battingTeam);
            p.inningsBatted += 1;
            p.runs += b.runs;
            p.ballsFaced += b.balls;
            p.fours += b.fours;
            p.sixes += b.sixes;
            if (!b.isOut) p.notOuts += 1;
            if (b.isOut && b.runs == 0) p.ducks += 1;
            if (b.runs >= 100) {
              p.hundreds += 1;
            } else if (b.runs >= 50) {
              p.fifties += 1;
            } else if (b.runs >= 30) {
              p.thirties += 1;
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
            if (bw.playerId.isEmpty) continue;
            final name = resolvedName(bw.playerId, bw.name, match);
            if (excludePlaceholders && isPlaceholderPlayerName(name)) continue;
            final key = identityKey(bw.playerId);
            participants[key] = (bw.playerId, name);
            final p = ensure(bw.playerId, name, team: inn.bowlingTeam);
            p.inningsBowled += 1;
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

          for (final ov in inn.overs) {
            for (final ball in ov.balls) {
              final fId = ball.fielderId;
              if (ball.isWicket && fId != null && fId.isNotEmpty) {
                final fName = resolvedName(fId, 'Player', match);
                if (excludePlaceholders && isPlaceholderPlayerName(fName)) {
                  continue;
                }
                final key = identityKey(fId);
                participants[key] = (fId, fName);
                final fp = ensure(fId, fName, team: inn.bowlingTeam);
                fp.fieldingDismissals += 1;
                if (ball.wicketType == WicketType.caught) {
                  fp.catches += 1;
                } else if (ball.wicketType == WicketType.stumped) {
                  fp.stumpings += 1;
                } else if (ball.wicketType == WicketType.runOut) {
                  fp.runOuts += 1;
                }
              }
            }
          }
        }
      }

      for (final entry in participants.values) {
        ensure(entry.$1, entry.$2).matchesPlayed += 1;
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
  _MutableCareer({
    required this.playerId,
    this.userId,
    required this.name,
  });

  final String playerId;
  final String? userId;
  String name;
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
  int thirties = 0;
  int fifties = 0;
  int hundreds = 0;
  int ducks = 0;
  int inningsBowled = 0;
  int legalBallsBowled = 0;
  int maidens = 0;
  int runsConceded = 0;
  int wickets = 0;
  int bestBowlingWickets = 0;
  int bestBowlingRuns = -1;
  int fieldingDismissals = 0;
  int catches = 0;
  int stumpings = 0;
  int runOuts = 0;

  PlayerCareerStats toStats() => PlayerCareerStats(
        playerId: playerId,
        userId: userId,
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
        thirties: thirties,
        fifties: fifties,
        hundreds: hundreds,
        ducks: ducks,
        inningsBowled: inningsBowled,
        legalBallsBowled: legalBallsBowled,
        maidens: maidens,
        runsConceded: runsConceded,
        wickets: wickets,
        bestBowlingWickets: bestBowlingWickets,
        bestBowlingRuns: bestBowlingRuns < 0 ? 0 : bestBowlingRuns,
        fieldingDismissals: fieldingDismissals,
        catches: catches,
        stumpings: stumpings,
        runOuts: runOuts,
      );
}

@immutable
class PlayerMatchContribution {
  const PlayerMatchContribution({
    required this.match,
    required this.opponent,
    this.batLabel,
    this.bowlLabel,
  });

  final DerivedMatchState match;
  final String opponent;
  final String? batLabel;
  final String? bowlLabel;
}

@immutable
class PlayerOpponentSummary {
  const PlayerOpponentSummary({
    required this.opponent,
    required this.inningsBatted,
    required this.runs,
    required this.ballsFaced,
    required this.wickets,
    required this.runsConceded,
    required this.legalBallsBowled,
  });

  final String opponent;
  final int inningsBatted;
  final int runs;
  final int ballsFaced;
  final int wickets;
  final int runsConceded;
  final int legalBallsBowled;

  double get strikeRate => ballsFaced == 0 ? 0.0 : (runs / ballsFaced) * 100.0;
  double get economy =>
      legalBallsBowled == 0 ? 0.0 : runsConceded / (legalBallsBowled / 6.0);
}

@immutable
class PlayerFullProfile {
  const PlayerFullProfile({
    required this.overall,
    required this.byFormat,
    required this.contributions,
    required this.opponents,
  });

  final PlayerCareerStats? overall;
  final Map<String, PlayerCareerStats> byFormat;
  final List<PlayerMatchContribution> contributions;
  final List<PlayerOpponentSummary> opponents;
}

extension StatsEnginePlayerProfile on StatsEngine {
  static PlayerFullProfile derivePlayerProfile(
    List<DerivedMatchState> matches,
    String playerName, {
    String? playerId,
    String? userId,
    bool excludeDemo = true,
    Map<String, String> playerNamesById = const {},
    Map<String, String> playerUserIdsById = const {},
  }) {
    final lower = playerName.trim().toLowerCase();
    final targetPid = playerId?.trim();
    final targetUid = (userId?.trim().isNotEmpty ?? false)
        ? userId!.trim()
        : (targetPid != null ? playerUserIdsById[targetPid] : null);

    bool matchesPlayer(String candidateId, String candidateName) {
      if (targetUid != null && targetUid.isNotEmpty) {
        final candUid = playerUserIdsById[candidateId];
        if (candUid == targetUid) return true;
      }
      if (targetPid != null && targetPid.isNotEmpty) {
        return candidateId == targetPid;
      }
      return candidateName.trim().toLowerCase() == lower;
    }

    bool matchesCareer(PlayerCareerStats s) {
      if (targetUid != null && targetUid.isNotEmpty) {
        return s.userId == targetUid || s.playerId == targetPid;
      }
      if (targetPid != null && targetPid.isNotEmpty) {
        return s.playerId == targetPid;
      }
      return s.name.trim().toLowerCase() == lower;
    }

    final filtered = matches
        .where((m) => !excludeDemo || !m.config.isDemo)
        .toList()
      ..sort((a, b) => b.config.createdAt.compareTo(a.config.createdAt));

    final allOverall = StatsEngine.derive(
      filtered,
      excludeDemo: false,
      playerNamesById: playerNamesById,
      playerUserIdsById: playerUserIdsById,
    );
    final overall = allOverall.where(matchesCareer).firstOrNull;

    final matchesByFormat = <String, List<DerivedMatchState>>{};
    final contributions = <PlayerMatchContribution>[];
    final oppMap = <String, ({
      String name,
      int inn,
      int runs,
      int balls,
      int wkts,
      int rc,
      int lb,
    })>{};

    for (final m in filtered) {
      MatchSide? playerSide;
      int batRuns = 0;
      int batBalls = 0;
      bool batted = false;
      bool notOut = true;
      int bowlWkts = 0;
      int bowlRuns = 0;
      int bowlBalls = 0;
      bool bowled = false;
      bool fielded = false;

      for (final inn in m.allInnings) {
        if (!m.config.isTestMatch && inn.inningsNumber >= 3) continue;
        for (final b in inn.batters) {
          if (matchesPlayer(b.playerId, b.name) &&
              (b.balls > 0 || b.isOut || b.runs > 0)) {
            batted = true;
            playerSide ??= inn.battingSide;
            batRuns += b.runs;
            batBalls += b.balls;
            if (b.isOut) notOut = false;
          }
        }
        for (final bw in inn.bowlers) {
          if (matchesPlayer(bw.playerId, bw.name) &&
              (bw.legalBalls > 0 || bw.runsConceded > 0 || bw.wickets > 0)) {
            bowled = true;
            playerSide ??= inn.bowlingSide;
            bowlWkts += bw.wickets;
            bowlRuns += bw.runsConceded;
            bowlBalls += bw.legalBalls;
          }
        }
        for (final ov in inn.overs) {
          for (final ball in ov.balls) {
            final fId = ball.fielderId;
            if (ball.isWicket && fId != null && fId.isNotEmpty) {
              final fName = playerNamesById[fId] ??
                  m.resolvedPlayerNames[fId] ??
                  '';
              if (matchesPlayer(fId, fName)) {
                fielded = true;
                playerSide ??= inn.bowlingSide;
              }
            }
          }
        }
      }

      if (!batted && !bowled && !fielded) continue;

      final opponent = playerSide == MatchSide.a
          ? m.config.teamB
          : m.config.teamA;

      final batLabel = batted ? '$batRuns${notOut ? '*' : ''}' : null;
      final bowlLabel = bowled ? '$bowlWkts/$bowlRuns' : null;
      contributions.add(
        PlayerMatchContribution(
          match: m,
          opponent: opponent,
          batLabel: batLabel,
          bowlLabel: bowlLabel,
        ),
      );

      final fmt = m.config.formatLabel;
      matchesByFormat.putIfAbsent(fmt, () => <DerivedMatchState>[]).add(m);

      final oppKey = opponent.toLowerCase();
      final prev = oppMap[oppKey] ??
          (name: opponent, inn: 0, runs: 0, balls: 0, wkts: 0, rc: 0, lb: 0);
      oppMap[oppKey] = (
        name: prev.name,
        inn: prev.inn + (batted ? 1 : 0),
        runs: prev.runs + batRuns,
        balls: prev.balls + batBalls,
        wkts: prev.wkts + bowlWkts,
        rc: prev.rc + bowlRuns,
        lb: prev.lb + bowlBalls,
      );
    }

    final byFormat = <String, PlayerCareerStats>{};
    for (final entry in matchesByFormat.entries) {
      final fmtStats = StatsEngine.derive(
        entry.value,
        excludeDemo: false,
        playerNamesById: playerNamesById,
        playerUserIdsById: playerUserIdsById,
      ).where(matchesCareer).firstOrNull;
      if (fmtStats != null) byFormat[entry.key] = fmtStats;
    }

    final opponents = oppMap.values
        .map(
          (v) => PlayerOpponentSummary(
            opponent: v.name,
            inningsBatted: v.inn,
            runs: v.runs,
            ballsFaced: v.balls,
            wickets: v.wkts,
            runsConceded: v.rc,
            legalBallsBowled: v.lb,
          ),
        )
        .toList();

    return PlayerFullProfile(
      overall: overall,
      byFormat: byFormat,
      contributions: contributions,
      opponents: opponents,
    );
  }
}
