import 'models.dart';

/// Deterministic cricket scoring engine.
/// Derives the complete state of a match solely from [MatchConfig] and its
/// ordered list of [BallEvent]s. Nothing is mutated or cached out-of-band, so
/// undo, edit-any-ball, offline replay, and NRR can never drift.
class CricketEngine {
  CricketEngine._();

  /// Returns a team's display label for plain-text summaries/banners.
  /// Leaves names untouched for normal matches; appends `(A)` / `(B)` only
  /// when both clubs share the exact same name (case-insensitive).
  static String _displayLabel(MatchConfig config, MatchSide side) {
    final name = config.teamNameForSide(side);
    if (!config.hasSameTeamNames) return name;
    return '$name (${side == MatchSide.a ? 'A' : 'B'})';
  }

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
      battingSide: config.battingFirstSide,
      oversLimit: config.oversLimit,
      playersPerSide: config.playersPerSide,
      openingStriker: config.openingStrikerInnings1,
      openingNonStriker: config.openingNonStrikerInnings1,
      openingBowler: config.openingBowlerInnings1,
      events: inn1Events,
      isDeclared: config.declaredInnings.contains(1),
      target: null,
    );

    final int? targetForInn2 = config.firstInningsTargetOverride ??
        ((innings1.isComplete || inn2Events.isNotEmpty)
            ? innings1.totalRuns + 1
            : null);

    final bool showInnings2 = hasDemoChase ||
        inn2Events.isNotEmpty ||
        inn3Events.isNotEmpty ||
        inn4Events.isNotEmpty ||
        (forcedInnings != null && forcedInnings >= 2);

    DerivedInningsState? innings2;
    if (showInnings2) {
      innings2 = _deriveInnings(
        inningsNumber: 2,
        battingTeam: config.battingSecondTeam,
        bowlingTeam: config.battingFirstTeam,
        battingSide: config.battingSecondSide,
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

    // True In-Match Super Over (innings 3 & 4) when regulation limited-overs match ties.
    final regulationTarget =
        innings2?.target ?? (innings1.totalRuns + 1);
    final isRegulationTied = innings2 != null &&
        innings2.isComplete &&
        innings2.totalRuns == (regulationTarget - 1);

    final bool showSuperOver1 = isRegulationTied &&
        (inn3Events.isNotEmpty ||
            inn4Events.isNotEmpty ||
            (forcedInnings != null && forcedInnings >= 3));
    DerivedInningsState? innings3;
    if (showSuperOver1) {
      // ICC Super Over rule: team that batted 2nd in regulation bats 1st.
      final so1BatSide = config.battingSecondSide;
      final so1BowlSide = config.battingFirstSide;
      final so1BatTeam = config.teamNameForSide(so1BatSide);
      final so1BowlTeam = config.teamNameForSide(so1BowlSide);
      final so1BatRoster = config.rosterForSide(so1BatSide);
      final so1BowlRoster = config.rosterForSide(so1BowlSide);
      innings3 = _deriveInnings(
        inningsNumber: 3,
        battingTeam: so1BatTeam,
        bowlingTeam: so1BowlTeam,
        battingSide: so1BatSide,
        oversLimit: 1,
        playersPerSide: 3, // 2 wickets all-out
        openingStriker:
            so1BatRoster.isNotEmpty ? so1BatRoster[0] : 'Batter 1',
        openingNonStriker:
            so1BatRoster.length > 1 ? so1BatRoster[1] : 'Batter 2',
        openingBowler:
            so1BowlRoster.isNotEmpty ? so1BowlRoster[0] : 'Bowler 1',
        events: inn3Events,
        isDeclared: config.declaredInnings.contains(3),
        target: null,
      );
    }

    final bool showSuperOver2 = innings3 != null &&
        (inn4Events.isNotEmpty ||
            (forcedInnings != null && forcedInnings >= 4));
    DerivedInningsState? innings4;
    if (showSuperOver2) {
      final so2BatSide = config.battingFirstSide;
      final so2BowlSide = config.battingSecondSide;
      final so2BatTeam = config.teamNameForSide(so2BatSide);
      final so2BowlTeam = config.teamNameForSide(so2BowlSide);
      final so2BatRoster = config.rosterForSide(so2BatSide);
      final so2BowlRoster = config.rosterForSide(so2BowlSide);
      innings4 = _deriveInnings(
        inningsNumber: 4,
        battingTeam: so2BatTeam,
        bowlingTeam: so2BowlTeam,
        battingSide: so2BatSide,
        oversLimit: 1,
        playersPerSide: 3, // 2 wickets all-out
        openingStriker:
            so2BatRoster.isNotEmpty ? so2BatRoster[0] : 'Batter 1',
        openingNonStriker:
            so2BatRoster.length > 1 ? so2BatRoster[1] : 'Batter 2',
        openingBowler:
            so2BowlRoster.isNotEmpty ? so2BowlRoster[0] : 'Bowler 1',
        events: inn4Events,
        isDeclared: config.declaredInnings.contains(4),
        target: innings3.totalRuns + 1,
      );
    }

    int activeInningsNumber = 1;
    if (innings4 != null) {
      activeInningsNumber = 4;
    } else if (innings3 != null) {
      activeInningsNumber = 3;
    } else if (showInnings2) {
      activeInningsNumber = 2;
    }
    if (forcedInnings == 1 && !hasDemoChase) activeInningsNumber = 1;
    if (forcedInnings == 2 && innings2 != null) activeInningsNumber = 2;
    if (forcedInnings == 3 && innings3 != null) activeInningsNumber = 3;
    if (forcedInnings == 4 && innings4 != null) activeInningsNumber = 4;

    // Apply optional manual striker/bowler overrides (e.g. scorer swapped strike
    // or picked a new bowler before bowling the next ball).
    DerivedInningsState finalInn1 = innings1;
    DerivedInningsState? finalInn2 = innings2;
    DerivedInningsState? finalInn3 = innings3;
    DerivedInningsState? finalInn4 = innings4;
    if (activeInningsNumber == 1) {
      finalInn1 = _applyManualOverrides(
        innings1,
        striker: manualStrikerOverride,
        nonStriker: manualNonStrikerOverride,
        bowler: manualBowlerOverride,
      );
    } else if (activeInningsNumber == 2 && finalInn2 != null) {
      finalInn2 = _applyManualOverrides(
        finalInn2,
        striker: manualStrikerOverride,
        nonStriker: manualNonStrikerOverride,
        bowler: manualBowlerOverride,
      );
    } else if (activeInningsNumber == 3 && finalInn3 != null) {
      finalInn3 = _applyManualOverrides(
        finalInn3,
        striker: manualStrikerOverride,
        nonStriker: manualNonStrikerOverride,
        bowler: manualBowlerOverride,
      );
    } else if (activeInningsNumber == 4 && finalInn4 != null) {
      finalInn4 = _applyManualOverrides(
        finalInn4,
        striker: manualStrikerOverride,
        nonStriker: manualNonStrikerOverride,
        bowler: manualBowlerOverride,
      );
    }

    MatchStatus status = MatchStatus.live;
    MatchSide? winnerSide;
    String? resultSummary;

    if (config.isAbandoned) {
      status = MatchStatus.completed;
      resultSummary = 'Match abandoned (No result)';
    } else if (finalInn4 != null && finalInn4.isComplete && finalInn3 != null) {
      status = MatchStatus.completed;
      final soTarget = finalInn3.totalRuns + 1;
      if (finalInn4.totalRuns >= soTarget) {
        winnerSide = finalInn4.battingSide;
        resultSummary =
            '${_displayLabel(config, finalInn4.battingSide)} won Super Over';
      } else if (finalInn4.totalRuns == finalInn3.totalRuns) {
        resultSummary = 'Super Over tied';
      } else {
        winnerSide = finalInn4.bowlingSide;
        resultSummary =
            '${_displayLabel(config, finalInn4.bowlingSide)} won Super Over';
      }
    } else if (finalInn4 == null && finalInn3 != null && finalInn3.isComplete) {
      status = MatchStatus.inningsBreak;
      resultSummary =
          'Super Over break · ${_displayLabel(config, config.battingFirstSide)} need ${finalInn3.totalRuns + 1} in 1 ov';
    } else if (finalInn3 != null) {
      status = MatchStatus.live;
    } else if (finalInn2 != null && finalInn2.isComplete) {
      status = MatchStatus.completed;
      final target = finalInn2.target ?? (finalInn1.totalRuns + 1);
      final targetScore = target - 1;
      if (finalInn2.totalRuns >= target) {
        winnerSide = finalInn2.battingSide;
        final wicketsLeft =
            (config.playersPerSide - 1 - finalInn2.wickets).clamp(1, 10);
        resultSummary =
            '${_displayLabel(config, finalInn2.battingSide)} won by $wicketsLeft wicket${wicketsLeft == 1 ? '' : 's'}';
      } else if (finalInn2.totalRuns == targetScore) {
        resultSummary = 'Match tied';
      } else {
        winnerSide = finalInn2.bowlingSide;
        final margin = targetScore - finalInn2.totalRuns;
        resultSummary =
            '${_displayLabel(config, finalInn2.bowlingSide)} won by $margin run${margin == 1 ? '' : 's'}';
      }
    } else if (!showInnings2 && finalInn1.isComplete) {
      status = MatchStatus.inningsBreak;
      resultSummary =
          'Innings break · ${_displayLabel(config, config.battingSecondSide)} need ${finalInn1.totalRuns + 1}';
    }

    return DerivedMatchState(
      config: config,
      innings1: finalInn1,
      innings2: finalInn2,
      innings3: finalInn3,
      innings4: finalInn4,
      activeInningsNumber: activeInningsNumber,
      status: status,
      winnerSide: winnerSide,
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
    final side1 = config.battingFirstSide;
    final side2 = config.battingSecondSide;
    final followOn = config.followOnEnforced;

    MatchSide battingSideFor(int inn) => switch (inn) {
          1 => side1,
          2 => side2,
          3 => followOn ? side2 : side1,
          _ => followOn ? side1 : side2,
        };
    MatchSide bowlingSideFor(int inn) =>
        battingSideFor(inn) == side1 ? side2 : side1;

    (String, String, String) openersFor(
      MatchSide batSide,
      MatchSide bowlSide,
      int inn,
    ) {
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
      final batRoster = config.rosterForSide(batSide);
      final bowlRoster = config.rosterForSide(bowlSide);
      return (
        batRoster.isNotEmpty ? batRoster[0] : 'Opener 1',
        batRoster.length > 1 ? batRoster[1] : 'Opener 2',
        bowlRoster.isNotEmpty ? bowlRoster[0] : 'Bowler 1',
      );
    }

    final batSide1 = battingSideFor(1);
    final bowlSide1 = bowlingSideFor(1);
    final op1 = openersFor(batSide1, bowlSide1, 1);
    var inn1 = _deriveInnings(
      inningsNumber: 1,
      battingTeam: config.teamNameForSide(batSide1),
      bowlingTeam: config.teamNameForSide(bowlSide1),
      battingSide: batSide1,
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
      final batSide2 = battingSideFor(2);
      final bowlSide2 = bowlingSideFor(2);
      final op2 = openersFor(batSide2, bowlSide2, 2);
      inn2 = _deriveInnings(
        inningsNumber: 2,
        battingTeam: config.teamNameForSide(batSide2),
        bowlingTeam: config.teamNameForSide(bowlSide2),
        battingSide: batSide2,
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
      final batSide3 = battingSideFor(3);
      final bowlSide3 = bowlingSideFor(3);
      final op3 = openersFor(batSide3, bowlSide3, 3);
      inn3 = _deriveInnings(
        inningsNumber: 3,
        battingTeam: config.teamNameForSide(batSide3),
        bowlingTeam: config.teamNameForSide(bowlSide3),
        battingSide: batSide3,
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
      final batSide4 = battingSideFor(4);
      final bowlSide4 = bowlingSideFor(4);
      final op4 = openersFor(batSide4, bowlSide4, 4);
      inn4 = _deriveInnings(
        inningsNumber: 4,
        battingTeam: config.teamNameForSide(batSide4),
        bowlingTeam: config.teamNameForSide(bowlSide4),
        battingSide: batSide4,
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
    MatchSide? winnerSide;
    String? resultSummary;
    String? leadTrailText;
    bool canEnforceFollowOn = false;

    if (inn4 != null) {
      final t4 = target4 ?? 1;
      if (inn4.isComplete) {
        status = MatchStatus.completed;
        if (inn4.totalRuns >= t4) {
          winnerSide = inn4.battingSide;
          final wLeft =
              (config.playersPerSide - 1 - inn4.wickets).clamp(1, 10);
          resultSummary =
              '${_displayLabel(config, inn4.battingSide)} won by $wLeft wicket${wLeft == 1 ? '' : 's'}';
        } else if (inn4.totalRuns == t4 - 1) {
          resultSummary = 'Match tied';
        } else {
          winnerSide = inn4.bowlingSide;
          final margin = (t4 - 1) - inn4.totalRuns;
          resultSummary =
              '${_displayLabel(config, inn4.bowlingSide)} won by $margin run${margin == 1 ? '' : 's'}';
        }
      } else {
        final need = (t4 - inn4.totalRuns).clamp(0, 99999);
        leadTrailText = '${_displayLabel(config, inn4.battingSide)} need $need runs';
      }
    } else if (inn3 != null && inn2 != null) {
      final team3Total =
          followOn ? (inn2.totalRuns + inn3.totalRuns) : (inn1.totalRuns + inn3.totalRuns);
      final oppTotal = followOn ? inn1.totalRuns : inn2.totalRuns;
      final diff = team3Total - oppTotal;

      if (inn3.isComplete && diff < 0) {
        status = MatchStatus.completed;
        winnerSide = inn3.bowlingSide;
        final margin = -diff;
        resultSummary =
            '${_displayLabel(config, inn3.bowlingSide)} won by an innings and $margin run${margin == 1 ? '' : 's'}';
      } else if (inn3.isComplete) {
        status = MatchStatus.inningsBreak;
        final target = diff + 1;
        leadTrailText =
            '${_displayLabel(config, inn3.bowlingSide)} need $target to win';
        resultSummary = 'Innings break · Target $target';
      } else if (diff >= 0) {
        leadTrailText =
            '${_displayLabel(config, inn3.battingSide)} lead by $diff';
      } else {
        leadTrailText =
            '${_displayLabel(config, inn3.battingSide)} trail by ${-diff}';
      }
    } else if (inn2 != null) {
      final diff = inn2.totalRuns - inn1.totalRuns;
      if (inn2.isComplete) {
        status = MatchStatus.inningsBreak;
        if (diff < 0) {
          canEnforceFollowOn = true;
          leadTrailText =
              '${_displayLabel(config, inn1.battingSide)} lead by ${-diff}';
          resultSummary =
              'Innings break · ${_displayLabel(config, inn1.battingSide)} lead by ${-diff}';
        } else if (diff > 0) {
          leadTrailText =
              '${_displayLabel(config, inn2.battingSide)} lead by $diff';
          resultSummary =
              'Innings break · ${_displayLabel(config, inn2.battingSide)} lead by $diff';
        } else {
          leadTrailText = 'Scores level';
          resultSummary = 'Innings break · Scores level';
        }
      } else if (diff >= 0) {
        leadTrailText =
            '${_displayLabel(config, inn2.battingSide)} lead by $diff';
      } else {
        leadTrailText =
            '${_displayLabel(config, inn2.battingSide)} trail by ${-diff}';
      }
    } else {
      if (inn1.isComplete) {
        status = MatchStatus.inningsBreak;
        resultSummary =
            'Innings break · ${_displayLabel(config, inn1.battingSide)} ${inn1.scoreText}';
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
      winnerSide: winnerSide,
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
      battingSide: state.battingSide,
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
    required MatchSide battingSide,
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

      // Batter stats (wide, penalty, and retired hurt do not count as a ball faced)
      b.runs += ball.runsOffBat;
      final isRetiredHurt =
          ball.isWicket && ball.wicketType == WicketType.retiredHurt;
      if (ball.extraType != ExtraType.wide &&
          ball.extraType != ExtraType.penalty &&
          !isRetiredHurt) {
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
        case ExtraType.penalty:
          byes += ball.extraRuns;
      }

      // Bowler runs conceded (byes, leg-byes, and penalty runs are not charged to bowler)
      if (ball.extraType == ExtraType.penalty) {
        // Penalty runs are dead-ball awards — not charged to bowler.
      } else if (ball.extraType == ExtraType.bye ||
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

      // Wicket / Retired Hurt handling
      if (ball.isWicket) {
        final dismissedName = ball.dismissedBatter ?? ball.striker;
        final dismissed = ensureBatter(dismissedName);
        final countsWicket = ball.wicketType?.countsAsTeamWicket ?? true;

        if (countsWicket) {
          wickets += 1;
          currentOverWickets += 1;
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
        } else {
          // Retired hurt: batter leaves crease without losing a wicket
          dismissed.isOut = false;
          dismissed.dismissalText = 'retired hurt';
        }

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
      battingSide: battingSide,
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

