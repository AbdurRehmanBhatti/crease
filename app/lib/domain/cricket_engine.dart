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
    final inn3Events =
        activeEvents.where((e) => e.inningsNumber == 3).toList();
    final inn4Events =
        activeEvents.where((e) => e.inningsNumber == 4).toList();

    final hasDemoChase = config.firstInningsTargetOverride != null;
    final isTest = config.isTestMatch;

    if (isTest) {
      return _deriveTestMatch(
        config: config,
        inn1Events: inn1Events,
        inn2Events: inn2Events,
        inn3Events: inn3Events,
        inn4Events: inn4Events,
        unsyncedCount: unsyncedCount,
        forcedInnings: forcedInnings,
        manualStrikerOverride: manualStrikerOverride,
        manualNonStrikerOverride: manualNonStrikerOverride,
        manualBowlerOverride: manualBowlerOverride,
      );
    }

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
      isDeclared: config.declaredInnings.contains(1),
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
        isDeclared: config.declaredInnings.contains(2),
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

  static DerivedMatchState _deriveTestMatch({
    required MatchConfig config,
    required List<BallEvent> inn1Events,
    required List<BallEvent> inn2Events,
    required List<BallEvent> inn3Events,
    required List<BallEvent> inn4Events,
    required int unsyncedCount,
    int? forcedInnings,
    String? manualStrikerOverride,
    String? manualNonStrikerOverride,
    String? manualBowlerOverride,
  }) {
    final team1 = config.battingFirstTeam;
    final team2 = config.battingSecondTeam;
    final followOn = config.followOnEnforced;

    String battingTeamFor(int inn) => switch (inn) {
          1 => team1,
          2 => team2,
          3 => followOn ? team2 : team1,
          _ => followOn ? team1 : team2,
        };
    String bowlingTeamFor(int inn) =>
        battingTeamFor(inn) == team1 ? team2 : team1;

    (String, String, String) openersFor(String batTeam, String bowlTeam, int inn) {
      if (inn == 1) {
        return (
          config.openingStrikerInnings1,
          config.openingNonStrikerInnings1,
          config.openingBowlerInnings1,
        );
      }
      if (inn == 2) {
        return (
          config.openingStrikerInnings2,
          config.openingNonStrikerInnings2,
          config.openingBowlerInnings2,
        );
      }
      final batRoster = config.rosterForTeam(batTeam);
      final bowlRoster = config.rosterForTeam(bowlTeam);
      return (
        batRoster.isNotEmpty ? batRoster[0] : 'Opener 1',
        batRoster.length > 1 ? batRoster[1] : 'Opener 2',
        bowlRoster.isNotEmpty ? bowlRoster[0] : 'Bowler 1',
      );
    }

    final op1 = openersFor(battingTeamFor(1), bowlingTeamFor(1), 1);
    var inn1 = _deriveInnings(
      inningsNumber: 1,
      battingTeam: battingTeamFor(1),
      bowlingTeam: bowlingTeamFor(1),
      oversLimit: 0,
      playersPerSide: config.playersPerSide,
      openingStriker: op1.$1,
      openingNonStriker: op1.$2,
      openingBowler: op1.$3,
      events: inn1Events,
      isDeclared: config.declaredInnings.contains(1),
      target: null,
    );

    final show2 = inn2Events.isNotEmpty ||
        inn3Events.isNotEmpty ||
        inn4Events.isNotEmpty ||
        (forcedInnings != null && forcedInnings >= 2);
    DerivedInningsState? inn2;
    if (show2) {
      final op2 = openersFor(battingTeamFor(2), bowlingTeamFor(2), 2);
      inn2 = _deriveInnings(
        inningsNumber: 2,
        battingTeam: battingTeamFor(2),
        bowlingTeam: bowlingTeamFor(2),
        oversLimit: 0,
        playersPerSide: config.playersPerSide,
        openingStriker: op2.$1,
        openingNonStriker: op2.$2,
        openingBowler: op2.$3,
        events: inn2Events,
        isDeclared: config.declaredInnings.contains(2),
        target: null,
      );
    }

    final show3 = inn3Events.isNotEmpty ||
        inn4Events.isNotEmpty ||
        (forcedInnings != null && forcedInnings >= 3);
    DerivedInningsState? inn3;
    if (show3 && inn2 != null) {
      final op3 = openersFor(battingTeamFor(3), bowlingTeamFor(3), 3);
      inn3 = _deriveInnings(
        inningsNumber: 3,
        battingTeam: battingTeamFor(3),
        bowlingTeam: bowlingTeamFor(3),
        oversLimit: 0,
        playersPerSide: config.playersPerSide,
        openingStriker: op3.$1,
        openingNonStriker: op3.$2,
        openingBowler: op3.$3,
        events: inn3Events,
        isDeclared: config.declaredInnings.contains(3),
        target: null,
      );
    }

    // Calculate 4th innings target (if inn3 completed without an innings victory)
    int? target4;
    if (inn2 != null && inn3 != null) {
      if (followOn) {
        // Team 2 batted in inn2 + inn3; Team 1 chases in inn4
        final lead = (inn2.totalRuns + inn3.totalRuns) - inn1.totalRuns;
        if (lead >= 0) target4 = lead + 1;
      } else {
        // Team 1 batted in inn1 + inn3; Team 2 chases in inn4
        final lead = (inn1.totalRuns + inn3.totalRuns) - inn2.totalRuns;
        if (lead >= 0) target4 = lead + 1;
      }
    }

    final show4 =
        inn4Events.isNotEmpty || (forcedInnings != null && forcedInnings >= 4);
    DerivedInningsState? inn4;
    if (show4 && inn3 != null) {
      final op4 = openersFor(battingTeamFor(4), bowlingTeamFor(4), 4);
      inn4 = _deriveInnings(
        inningsNumber: 4,
        battingTeam: battingTeamFor(4),
        bowlingTeam: bowlingTeamFor(4),
        oversLimit: 0,
        playersPerSide: config.playersPerSide,
        openingStriker: op4.$1,
        openingNonStriker: op4.$2,
        openingBowler: op4.$3,
        events: inn4Events,
        isDeclared: config.declaredInnings.contains(4),
        target: target4,
      );
    }

    var activeNum = 1;
    if (inn4 != null) {
      activeNum = 4;
    } else if (inn3 != null) {
      activeNum = 3;
    } else if (inn2 != null) {
      activeNum = 2;
    }
    if (forcedInnings != null && forcedInnings >= 1 && forcedInnings <= 4) {
      if (forcedInnings == 4 && inn4 != null) activeNum = 4;
      if (forcedInnings == 3 && inn3 != null) activeNum = 3;
      if (forcedInnings == 2 && inn2 != null) activeNum = 2;
      if (forcedInnings == 1) activeNum = 1;
    }

    // Apply manual overrides to active innings
    if (activeNum == 1) {
      inn1 = _applyManualOverrides(
        inn1,
        striker: manualStrikerOverride,
        nonStriker: manualNonStrikerOverride,
        bowler: manualBowlerOverride,
      );
    } else if (activeNum == 2 && inn2 != null) {
      inn2 = _applyManualOverrides(
        inn2,
        striker: manualStrikerOverride,
        nonStriker: manualNonStrikerOverride,
        bowler: manualBowlerOverride,
      );
    } else if (activeNum == 3 && inn3 != null) {
      inn3 = _applyManualOverrides(
        inn3,
        striker: manualStrikerOverride,
        nonStriker: manualNonStrikerOverride,
        bowler: manualBowlerOverride,
      );
    } else if (activeNum == 4 && inn4 != null) {
      inn4 = _applyManualOverrides(
        inn4,
        striker: manualStrikerOverride,
        nonStriker: manualNonStrikerOverride,
        bowler: manualBowlerOverride,
      );
    }

    // Compute Lead / Trail text and MatchStatus
    MatchStatus status = MatchStatus.live;
    String? resultSummary;
    String? leadTrailText;
    bool canEnforceFollowOn = false;

    if (inn4 != null) {
      final t4 = target4 ?? 1;
      if (inn4.isComplete) {
        status = MatchStatus.completed;
        if (inn4.totalRuns >= t4) {
          final wLeft =
              (config.playersPerSide - 1 - inn4.wickets).clamp(1, 10);
          resultSummary =
              '${inn4.battingTeam} won by $wLeft wicket${wLeft == 1 ? '' : 's'}';
        } else if (inn4.totalRuns == t4 - 1) {
          resultSummary = 'Match tied';
        } else {
          final margin = (t4 - 1) - inn4.totalRuns;
          resultSummary =
              '${inn4.bowlingTeam} won by $margin run${margin == 1 ? '' : 's'}';
        }
      } else {
        final need = (t4 - inn4.totalRuns).clamp(0, 99999);
        leadTrailText = '${inn4.battingTeam} need $need runs';
      }
    } else if (inn3 != null && inn2 != null) {
      final team3Total =
          followOn ? (inn2.totalRuns + inn3.totalRuns) : (inn1.totalRuns + inn3.totalRuns);
      final oppTotal = followOn ? inn1.totalRuns : inn2.totalRuns;
      final diff = team3Total - oppTotal;

      if (inn3.isComplete && diff < 0) {
        status = MatchStatus.completed;
        final margin = -diff;
        resultSummary =
            '${inn3.bowlingTeam} won by an innings and $margin run${margin == 1 ? '' : 's'}';
      } else if (inn3.isComplete) {
        status = MatchStatus.inningsBreak;
        final target = diff + 1;
        leadTrailText = '${inn3.bowlingTeam} need $target to win';
        resultSummary = 'Innings break · Target $target';
      } else if (diff >= 0) {
        leadTrailText = '${inn3.battingTeam} lead by $diff';
      } else {
        leadTrailText = '${inn3.battingTeam} trail by ${-diff}';
      }
    } else if (inn2 != null) {
      final diff = inn2.totalRuns - inn1.totalRuns;
      if (inn2.isComplete) {
        status = MatchStatus.inningsBreak;
        if (diff < 0) {
          canEnforceFollowOn = true;
          leadTrailText = '${inn1.battingTeam} lead by ${-diff}';
          resultSummary = 'Innings break · ${inn1.battingTeam} lead by ${-diff}';
        } else if (diff > 0) {
          leadTrailText = '${inn2.battingTeam} lead by $diff';
          resultSummary = 'Innings break · ${inn2.battingTeam} lead by $diff';
        } else {
          leadTrailText = 'Scores level';
          resultSummary = 'Innings break · Scores level';
        }
      } else if (diff >= 0) {
        leadTrailText = '${inn2.battingTeam} lead by $diff';
      } else {
        leadTrailText = '${inn2.battingTeam} trail by ${-diff}';
      }
    } else {
      if (inn1.isComplete) {
        status = MatchStatus.inningsBreak;
        resultSummary =
            'Innings break · ${inn1.battingTeam} ${inn1.scoreText}';
      } else {
        leadTrailText = '1st Innings';
      }
    }

    return DerivedMatchState(
      config: config,
      innings1: inn1,
      innings2: inn2,
      innings3: inn3,
      innings4: inn4,
      activeInningsNumber: activeNum,
      status: status,
      resultSummary: resultSummary,
      leadTrailText: leadTrailText,
      canEnforceFollowOn: canEnforceFollowOn,
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
      isDeclared: state.isDeclared,
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
    bool isDeclared = false,
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
    if (currentOverBalls.isNotEmpty || oversLimit <= 0 || overs.length < oversLimit) {
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
    final bool oversFinished = oversLimit > 0 && legalBalls >= oversLimit * 6;
    final bool targetChased = target != null && totalRuns >= target;
    final bool isComplete =
        allOut || oversFinished || targetChased || isDeclared;

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
      isDeclared: isDeclared,
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

