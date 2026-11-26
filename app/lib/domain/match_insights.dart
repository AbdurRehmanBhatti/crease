import 'package:flutter/foundation.dart';

import 'models.dart';

@immutable
class PartnershipSegment {
  const PartnershipSegment({
    required this.wicketNumber,
    required this.batterA,
    required this.runsA,
    required this.ballsA,
    required this.batterB,
    required this.runsB,
    required this.ballsB,
    required this.runs,
    required this.balls,
    required this.isActive,
  });

  final int wicketNumber; // 1 = opening stand, 2 = 2nd wicket, etc.
  final String batterA;
  final int runsA;
  final int ballsA;
  final String batterB;
  final int runsB;
  final int ballsB;
  final int runs;
  final int balls;
  final bool isActive;
}

@immutable
class ScoringBreakdown {
  const ScoringBreakdown({
    required this.dotBalls,
    required this.runningBalls,
    required this.fours,
    required this.sixes,
    required this.extrasRuns,
    required this.legalBalls,
    required this.totalRuns,
  });

  final int dotBalls;
  final int runningBalls; // 1s, 2s, 3s, 5s off bat
  final int fours;
  final int sixes;
  final int extrasRuns;
  final int legalBalls;
  final int totalRuns;

  double get dotPercent =>
      legalBalls == 0 ? 0.0 : (dotBalls / legalBalls) * 100.0;

  double get boundaryRunPercent =>
      totalRuns == 0 ? 0.0 : (((fours * 4) + (sixes * 6)) / totalRuns) * 100.0;
}

/// Pure helpers deriving per-match partnerships, worm points, and scoring splits.
class MatchInsights {
  MatchInsights._();

  static List<PartnershipSegment> partnerships(DerivedInningsState inn) {
    final nameById = <String, String>{
      for (final b in inn.batters) b.playerId: b.name,
      if (inn.strikerId.isNotEmpty) inn.strikerId: inn.striker,
      if (inn.nonStrikerId.isNotEmpty) inn.nonStrikerId: inn.nonStriker,
    };
    String nameOf(String? id, String fallback) =>
        (id != null && id.isNotEmpty) ? (nameById[id] ?? fallback) : fallback;

    final segments = <PartnershipSegment>[];
    var wicketNum = 1;
    var runs = 0;
    var balls = 0;
    var runsA = 0;
    var ballsA = 0;
    var runsB = 0;
    var ballsB = 0;
    String? bA;
    String? bB;

    for (final ov in inn.overs) {
      for (final ball in ov.balls) {
        bA ??= ball.strikerId;
        bB ??= ball.nonStrikerId;
        runs += ball.totalRuns;
        if (ball.isLegalDelivery) balls += 1;

        if (ball.strikerId == bA) {
          runsA += ball.runsOffBat;
          if (ball.extraType != ExtraType.wide) ballsA += 1;
        } else if (ball.strikerId == bB) {
          runsB += ball.runsOffBat;
          if (ball.extraType != ExtraType.wide) ballsB += 1;
        }

        if (ball.isWicket) {
          segments.add(
            PartnershipSegment(
              wicketNumber: wicketNum,
              batterA: nameOf(bA, 'Batter 1'),
              runsA: runsA,
              ballsA: ballsA,
              batterB: nameOf(bB, 'Batter 2'),
              runsB: runsB,
              ballsB: ballsB,
              runs: runs,
              balls: balls,
              isActive: false,
            ),
          );
          wicketNum += 1;
          runs = 0;
          balls = 0;
          runsA = 0;
          ballsA = 0;
          runsB = 0;
          ballsB = 0;
          bA = null;
          bB = null;
        }
      }
    }

    if (runs > 0 || balls > 0) {
      segments.add(
        PartnershipSegment(
          wicketNumber: wicketNum,
          batterA: nameOf(bA, inn.striker),
          runsA: runsA,
          ballsA: ballsA,
          batterB: nameOf(bB, inn.nonStriker),
          runsB: runsB,
          ballsB: ballsB,
          runs: runs,
          balls: balls,
          isActive: !inn.isComplete,
        ),
      );
    }

    return segments;
  }

  static ScoringBreakdown breakdown(DerivedInningsState inn) {
    var dots = 0;
    var running = 0;
    var fours = 0;
    var sixes = 0;
    var legal = 0;

    for (final ov in inn.overs) {
      for (final b in ov.balls) {
        if (b.isLegalDelivery) {
          legal += 1;
          if (b.totalRuns == 0) {
            dots += 1;
          } else if (b.runsOffBat == 4) {
            fours += 1;
          } else if (b.runsOffBat == 6) {
            sixes += 1;
          } else if (b.runsOffBat > 0) {
            running += 1;
          }
        } else {
          if (b.runsOffBat == 4) fours += 1;
          if (b.runsOffBat == 6) sixes += 1;
        }
      }
    }

    return ScoringBreakdown(
      dotBalls: dots,
      runningBalls: running,
      fours: fours,
      sixes: sixes,
      extrasRuns: inn.extrasTotal,
      legalBalls: legal,
      totalRuns: inn.totalRuns,
    );
  }

  /// Cumulative runs after each over (1-based) plus wicket counts per over.
  static List<({int over, int cumulativeRuns, int wickets})> wormPoints(
    DerivedInningsState inn,
  ) {
    final pts = <({int over, int cumulativeRuns, int wickets})>[];
    var running = 0;
    for (final ov in inn.overs) {
      if (ov.balls.isEmpty) continue;
      running += ov.runsInOver;
      pts.add((
        over: ov.overNumber,
        cumulativeRuns: running,
        wickets: ov.wicketsInOver,
      ));
    }
    return pts;
  }
}
