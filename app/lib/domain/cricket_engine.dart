import 'models.dart';

/// Deterministic cricket scoring engine.
/// Derives the complete state of a match solely from [MatchConfig] and its
/// ordered list of [BallEvent]s. Nothing is mutated or cached out-of-band, so
/// undo, edit-any-ball, offline replay, and NRR can never drift.
class CricketEngine {
  CricketEngine._();

  static DerivedMatchState derive(
    MatchConfig config,
    List<BallEvent> allEvents, {
    int? forcedInnings,
    String? manualStrikerOverride,
    String? manualNonStrikerOverride,
    String? manualBowlerOverride,
  }) {
    final activeEvents = allEvents.where((e) => !e.voided).toList()
      ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

    final unsyncedCount = allEvents.where((e) => !e.synced).length;

    final inn1Events =
        activeEvents.where((e) => e.inningsNumber == 1).toList();
    final inn2Events =
        activeEvents.where((e) => e.inningsNumber == 2).toList();

    final hasDemoChase = config.firstInningsTargetOverride != null;

    final innings1 = _deriveInnings(
      inningsNumber: 1,
      battingTeam: config.battingFirstTeam,
      bowlingTeam: config.battingSecondTeam,
      oversLimit: config.oversLimit,
      playersPerSide: config.playersPerSide,
      openingStriker: config.openingStrikerInnings1,
      openingNonStriker: config.openingNonStrikerInnings1,
      openingBowler: config.openingBowlerInnings1,
      events: inn1Events,
      target: null,
    );

    final int? targetForInn2 = hasDemoChase
        ? config.firstInningsTargetOverride
        : (innings1.isComplete || inn2Events.isNotEmpty)
            ? innings1.totalRuns + 1
            : null;

    final bool showInnings2 =
        hasDemoChase || inn2Events.isNotEmpty || forcedInnings == 2;

    DerivedInningsState? innings2;
    if (showInnings2) {
      innings2 = _deriveInnings(
        inningsNumber: 2,
        battingTeam: config.battingSecondTeam,
        bowlingTeam: config.battingFirstTeam,
        oversLimit: config.oversLimit,
        playersPerSide: config.playersPerSide,
        openingStriker: config.openingStrikerInnings2,
        openingNonStriker: config.openingNonStrikerInnings2,
        openingBowler: config.openingBowlerInnings2,
        events: inn2Events,
        target: targetForInn2,
      );
    }

    int activeInningsNumber = showInnings2 ? 2 : 1;
    if (forcedInnings == 1 && !hasDemoChase) activeInningsNumber = 1;

    // Apply optional manual striker/bowler overrides (e.g. scorer swapped strike
    // or picked a new bowler before bowling the next ball).
    DerivedInningsState finalInn1 = innings1;
    DerivedInningsState? finalInn2 = innings2;
    if (activeInningsNumber == 1) {
      finalInn1 = _applyManualOverrides(
        innings1,
        striker: manualStrikerOverride,
        nonStriker: manualNonStrikerOverride,
        bowler: manualBowlerOverride,
      );
    } else if (finalInn2 != null) {
      finalInn2 = _applyManualOverrides(
        finalInn2,
        striker: manualStrikerOverride,
        nonStriker: manualNonStrikerOverride,
        bowler: manualBowlerOverride,
      );
    }

    MatchStatus status = MatchStatus.live;
    String? resultSummary;

    if (finalInn2 != null && finalInn2.isComplete) {
      status = MatchStatus.completed;
      final target = finalInn2.target ?? (finalInn1.totalRuns + 1);
      final targetScore = target - 1;
      if (finalInn2.totalRuns >= target) {
        final wicketsLeft =
            (config.playersPerSide - 1 - finalInn2.wickets).clamp(1, 10);
        resultSummary =
            '${finalInn2.battingTeam} won by $wicketsLeft wicket${wicketsLeft == 1 ? '' : 's'}';
      } else if (finalInn2.totalRuns == targetScore) {
        resultSummary = 'Match tied';
      } else {
        final margin = targetScore - finalInn2.totalRuns;
        resultSummary =
            '${finalInn2.bowlingTeam} won by $margin run${margin == 1 ? '' : 's'}';
      }
    } else if (!showInnings2 && finalInn1.isComplete) {
      status = MatchStatus.inningsBreak;
      resultSummary =
          'Innings break · ${config.battingSecondTeam} need ${finalInn1.totalRuns + 1}';
    }

    return DerivedMatchState(
      config: config,
      innings1: finalInn1,
      innings2: finalInn2,
      activeInningsNumber: activeInningsNumber,
      status: status,
      resultSummary: resultSummary,
      unsyncedCount: unsyncedCount,
    );
  }

  static DerivedInningsState _applyManualOverrides(
    DerivedInningsState state, {
    String? striker,
    String? nonStriker,
    String? bowler,
  }) {
    if (striker == null && nonStriker == null && bowler == null) return state;
    return DerivedInningsState(
      inningsNumber: state.inningsNumber,
      battingTeam: state.battingTeam,
      bowlingTeam: state.bowlingTeam,
      totalRuns: state.totalRuns,
      wickets: state.wickets,
      legalBalls: state.legalBalls,
      oversLimit: state.oversLimit,
      playersPerSide: state.playersPerSide,
      striker: striker ?? state.striker,
      nonStriker: nonStriker ?? state.nonStriker,
      currentBowler: bowler ?? state.currentBowler,
      batters: state.batters,
      bowlers: state.bowlers,
      overs: state.overs,
      fallOfWickets: state.fallOfWickets,
      wides: state.wides,
      noBalls: state.noBalls,
      byes: state.byes,
      legByes: state.legByes,
      isComplete: state.isComplete,
      target: state.target,
    );
  }

  static DerivedInningsState _deriveInnings({
    required int inningsNumber,
    required String battingTeam,
    required String bowlingTeam,
    required int oversLimit,
    required int playersPerSide,
    required String openingStriker,
    required String openingNonStriker,
    required String openingBowler,
    required List<BallEvent> events,
    required int? target,
  }) {
    int totalRuns = 0;
    int wickets = 0;
    int legalBalls = 0;
    int wides = 0;
    int noBalls = 0;
    int byes = 0;
    int legByes = 0;

    String striker = openingStriker;
    String nonStriker = openingNonStriker;
    String currentBowler = openingBowler;

    final batterOrder = <String>[openingStriker, openingNonStriker];
    final batterStats = <String, _MutableBatter>{
      openingStriker: _MutableBatter(openingStriker),
      openingNonStriker: _MutableBatter(openingNonStriker),
    };

    final bowlerOrder = <String>[openingBowler];
    final bowlerStats = <String, _MutableBowler>{
      openingBowler: _MutableBowler(openingBowler),
    };

    final overs = <OverSummary>[];
    var currentOverBalls = <BallEvent>[];
    var currentOverLegal = 0;
    var currentOverRuns = 0;
    var currentOverWickets = 0;
    var currentOverBowler = openingBowler;
    var currentOverNumber = 1;

    final fallOfWickets = <FallOfWicket>[];

    _MutableBatter ensureBatter(String name) {
      if (!batterStats.containsKey(name)) {
        batterOrder.add(name);
        batterStats[name] = _MutableBatter(name);
      }
      return batterStats[name]!;
    }

    _MutableBowler ensureBowler(String name) {
      if (!bowlerStats.containsKey(name)) {
        bowlerOrder.add(name);
        bowlerStats[name] = _MutableBowler(name);
      }
      return bowlerStats[name]!;
    }

    for (final ball in events) {
      final b = ensureBatter(ball.striker);
      ensureBatter(ball.nonStriker);
      final bowl = ensureBowler(ball.bowler);

      striker = ball.striker;
      nonStriker = ball.nonStriker;
      currentBowler = ball.bowler;
      currentOverBowler = ball.bowler;

      totalRuns += ball.totalRuns;
      currentOverRuns += ball.totalRuns;

      // Batter stats
      b.runs += ball.runsOffBat;
      if (ball.extraType != ExtraType.wide) {
        b.balls += 1;
      }
      if (ball.runsOffBat == 4) b.fours += 1;
      if (ball.runsOffBat == 6) b.sixes += 1;

      // Extras breakdown
      switch (ball.extraType) {
        case ExtraType.none:
          break;
        case ExtraType.wide:
          wides += ball.extraRuns;
        case ExtraType.noBall:
          noBalls += ball.extraRuns;
        case ExtraType.bye:
          byes += ball.extraRuns;
        case ExtraType.legBye:
          legByes += ball.extraRuns;
      }

      // Bowler runs conceded (byes and leg-byes are not charged to the bowler)
      if (ball.extraType == ExtraType.bye ||
          ball.extraType == ExtraType.legBye) {
        bowl.runsConceded += ball.runsOffBat;
      } else {
        bowl.runsConceded += ball.totalRuns;
      }

      if (ball.isLegalDelivery) {
        legalBalls += 1;
        currentOverLegal += 1;
        bowl.legalBalls += 1;
      }

      // Wicket handling
      if (ball.isWicket) {
        wickets += 1;
        currentOverWickets += 1;
        final dismissedName = ball.dismissedBatter ?? ball.striker;
        final dismissed = ensureBatter(dismissedName);
        dismissed.isOut = true;
        dismissed.dismissalText = ball.scorecardDismissalText ?? 'out';

        if (ball.wicketType?.creditedToBowler ?? true) {
          bowl.wickets += 1;
        }

        fallOfWickets.add(
          FallOfWicket(
            wicketNumber: wickets,
            runsAtFall: totalRuns,
            oversAtFall: '${legalBalls ~/ 6}.${legalBalls % 6}',
            batterName: dismissedName,
          ),
        );

        final incoming = ball.nextBatter?.trim() ?? '';
        if (incoming.isNotEmpty) {
          ensureBatter(incoming);
        }
        if (dismissedName == nonStriker) {
          nonStriker = incoming;
        } else {
          striker = incoming;
        }
      }

      // Rotate strike on odd running runs
      if (ball.runningRuns.isOdd) {
        final temp = striker;
        striker = nonStriker;
        nonStriker = temp;
      }

      currentOverBalls.add(ball);

      // End of over
      if (currentOverLegal == 6) {
        if (currentOverRuns == 0) {
          bowl.maidens += 1;
        }
        overs.add(
          OverSummary(
            overNumber: currentOverNumber,
            bowler: currentOverBowler,
            balls: List.unmodifiable(currentOverBalls),
            runsInOver: currentOverRuns,
            wicketsInOver: currentOverWickets,
            legalBallsInOver: currentOverLegal,
          ),
        );
        currentOverNumber += 1;
        currentOverBalls = <BallEvent>[];
        currentOverLegal = 0;
        currentOverRuns = 0;
        currentOverWickets = 0;

        // Swap strike at end of over
        final temp = striker;
        striker = nonStriker;
        nonStriker = temp;
      }
    }

    // Add in-progress over (or an empty current over slot so the timeline always shows current over)
    if (currentOverBalls.isNotEmpty || overs.length < oversLimit) {
      overs.add(
        OverSummary(
          overNumber: currentOverNumber,
          bowler: currentOverBowler,
          balls: List.unmodifiable(currentOverBalls),
          runsInOver: currentOverRuns,
          wicketsInOver: currentOverWickets,
          legalBallsInOver: currentOverLegal,
        ),
      );
    }

    final maxWickets = (playersPerSide - 1).clamp(1, 10);
    final bool allOut = wickets >= maxWickets;
    final bool oversFinished = legalBalls >= oversLimit * 6;
    final bool targetChased = target != null && totalRuns >= target;
    final bool isComplete = allOut || oversFinished || targetChased;

    return DerivedInningsState(
      inningsNumber: inningsNumber,
      battingTeam: battingTeam,
      bowlingTeam: bowlingTeam,
      totalRuns: totalRuns,
      wickets: wickets,
      legalBalls: legalBalls,
      oversLimit: oversLimit,
      playersPerSide: playersPerSide,
      striker: striker,
      nonStriker: nonStriker,
      currentBowler: currentBowler,
      batters: [
        for (final name in batterOrder) batterStats[name]!.toLine(),
      ],
      bowlers: [
        for (final name in bowlerOrder) bowlerStats[name]!.toLine(),
      ],
      overs: overs,
      fallOfWickets: fallOfWickets,
      wides: wides,
      noBalls: noBalls,
      byes: byes,
      legByes: legByes,
      isComplete: isComplete,
      target: target,
    );
  }
}

class _MutableBatter {
  _MutableBatter(this.name);
  final String name;
  int runs = 0;
  int balls = 0;
  int fours = 0;
  int sixes = 0;
  bool isOut = false;
  String? dismissalText;

  BatterLine toLine() => BatterLine(
        name: name,
        runs: runs,
        balls: balls,
        fours: fours,
        sixes: sixes,
        isOut: isOut,
        dismissalText: dismissalText,
      );
}

class _MutableBowler {
  _MutableBowler(this.name);
  final String name;
  int legalBalls = 0;
  int maidens = 0;
  int runsConceded = 0;
  int wickets = 0;

  BowlerLine toLine() => BowlerLine(
        name: name,
        legalBalls: legalBalls,
        maidens: maidens,
        runsConceded: runsConceded,
        wickets: wickets,
      );
}

