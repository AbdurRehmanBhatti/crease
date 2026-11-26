import 'models.dart';

/// Deterministic cricket scoring engine.
/// Derives the complete state of a match solely from [MatchConfig], its
/// ordered list of UUID-referenced [BallEvent]s, and current [playerNamesById].
class CricketEngine {
  CricketEngine._();

  static String _teamName(
    MatchConfig config,
    MatchSide side,
    Map<String, String> teamNamesById,
  ) {
    final tid = config.teamIdForSide(side);
    if (tid != null && tid.isNotEmpty) {
      final resolved = teamNamesById[tid]?.trim();
      if (resolved != null && resolved.isNotEmpty) return resolved;
    }
    return config.teamNameForSide(side);
  }

  static String _displayLabel(
    MatchConfig config,
    MatchSide side,
    Map<String, String> teamNamesById,
  ) {
    final nameA = _teamName(config, MatchSide.a, teamNamesById);
    final nameB = _teamName(config, MatchSide.b, teamNamesById);
    final name = side == MatchSide.a ? nameA : nameB;
    if (nameA.trim().toLowerCase() != nameB.trim().toLowerCase()) return name;
    return '$name (${side == MatchSide.a ? 'A' : 'B'})';
  }

  static DerivedMatchState derive(
    MatchConfig config,
    List<BallEvent> allEvents, {
    Map<String, String> playerNamesById = const {},
    Map<String, String> teamNamesById = const {},
    int? forcedInnings,
    String? manualStrikerIdOverride,
    String? manualNonStrikerIdOverride,
    String? manualBowlerIdOverride,
  }) {
    final resolvedConfig = config.copyWith(
      teamA: _teamName(config, MatchSide.a, teamNamesById),
      teamB: _teamName(config, MatchSide.b, teamNamesById),
    );
    final resolvedNames = <String, String>{
      ...resolvedConfig.adHocPlayers,
      ...playerNamesById,
    };

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

    final hasDemoChase = resolvedConfig.firstInningsTargetOverride != null;
    final isTest = resolvedConfig.isTestMatch;

    if (isTest) {
      return _deriveTestMatch(
        config: resolvedConfig,
        resolvedNames: resolvedNames,
        teamNamesById: teamNamesById,
        inn1Events: inn1Events,
        inn2Events: inn2Events,
        inn3Events: inn3Events,
        inn4Events: inn4Events,
        unsyncedCount: unsyncedCount,
        forcedInnings: forcedInnings,
        manualStrikerIdOverride: manualStrikerIdOverride,
        manualNonStrikerIdOverride: manualNonStrikerIdOverride,
        manualBowlerIdOverride: manualBowlerIdOverride,
      );
    }

    final innings1 = _deriveInnings(
      inningsNumber: 1,
      battingTeam: resolvedConfig.battingFirstTeam,
      bowlingTeam: resolvedConfig.battingSecondTeam,
      battingSide: resolvedConfig.battingFirstSide,
      oversLimit: resolvedConfig.oversLimit,
      playersPerSide: resolvedConfig.playersPerSide,
      openingStrikerId: resolvedConfig.openingStriker1Id ?? '',
      openingNonStrikerId: resolvedConfig.openingNonStriker1Id ?? '',
      openingBowlerId: resolvedConfig.openingBowler1Id ?? '',
      events: inn1Events,
      resolvedNames: resolvedNames,
      isDeclared: resolvedConfig.declaredInnings.contains(1),
      target: null,
    );

    final int? targetForInn2 = resolvedConfig.firstInningsTargetOverride ??
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
        battingTeam: resolvedConfig.battingSecondTeam,
        bowlingTeam: resolvedConfig.battingFirstTeam,
        battingSide: resolvedConfig.battingSecondSide,
        oversLimit: resolvedConfig.oversLimit,
        playersPerSide: resolvedConfig.playersPerSide,
        openingStrikerId: resolvedConfig.openingStriker2Id ?? '',
        openingNonStrikerId: resolvedConfig.openingNonStriker2Id ?? '',
        openingBowlerId: resolvedConfig.openingBowler2Id ?? '',
        events: inn2Events,
        resolvedNames: resolvedNames,
        isDeclared: resolvedConfig.declaredInnings.contains(2),
        target: targetForInn2,
      );
    }

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
      final so1BatSide = resolvedConfig.battingSecondSide;
      final so1BowlSide = resolvedConfig.battingFirstSide;
      final so1BatRoster = resolvedConfig.rosterIdsForSide(so1BatSide);
      final so1BowlRoster = resolvedConfig.rosterIdsForSide(so1BowlSide);
      innings3 = _deriveInnings(
        inningsNumber: 3,
        battingTeam: resolvedConfig.teamNameForSide(so1BatSide),
        bowlingTeam: resolvedConfig.teamNameForSide(so1BowlSide),
        battingSide: so1BatSide,
        oversLimit: 1,
        playersPerSide: 3,
        openingStrikerId: so1BatRoster.isNotEmpty ? so1BatRoster[0] : '',
        openingNonStrikerId: so1BatRoster.length > 1 ? so1BatRoster[1] : '',
        openingBowlerId: so1BowlRoster.isNotEmpty ? so1BowlRoster[0] : '',
        events: inn3Events,
        resolvedNames: resolvedNames,
        isDeclared: resolvedConfig.declaredInnings.contains(3),
        target: null,
      );
    }

    final bool showSuperOver2 = innings3 != null &&
        (inn4Events.isNotEmpty ||
            (forcedInnings != null && forcedInnings >= 4));
    DerivedInningsState? innings4;
    if (showSuperOver2) {
      final so2BatSide = resolvedConfig.battingFirstSide;
      final so2BowlSide = resolvedConfig.battingSecondSide;
      final so2BatRoster = resolvedConfig.rosterIdsForSide(so2BatSide);
      final so2BowlRoster = resolvedConfig.rosterIdsForSide(so2BowlSide);
      innings4 = _deriveInnings(
        inningsNumber: 4,
        battingTeam: resolvedConfig.teamNameForSide(so2BatSide),
        bowlingTeam: resolvedConfig.teamNameForSide(so2BowlSide),
        battingSide: so2BatSide,
        oversLimit: 1,
        playersPerSide: 3,
        openingStrikerId: so2BatRoster.isNotEmpty ? so2BatRoster[0] : '',
        openingNonStrikerId: so2BatRoster.length > 1 ? so2BatRoster[1] : '',
        openingBowlerId: so2BowlRoster.isNotEmpty ? so2BowlRoster[0] : '',
        events: inn4Events,
        resolvedNames: resolvedNames,
        isDeclared: resolvedConfig.declaredInnings.contains(4),
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

    DerivedInningsState finalInn1 = innings1;
    DerivedInningsState? finalInn2 = innings2;
    DerivedInningsState? finalInn3 = innings3;
    DerivedInningsState? finalInn4 = innings4;
    if (activeInningsNumber == 1) {
      finalInn1 = _applyManualOverrides(
        innings1,
        resolvedNames: resolvedNames,
        strikerId: manualStrikerIdOverride,
        nonStrikerId: manualNonStrikerIdOverride,
        bowlerId: manualBowlerIdOverride,
      );
    } else if (activeInningsNumber == 2 && finalInn2 != null) {
      finalInn2 = _applyManualOverrides(
        finalInn2,
        resolvedNames: resolvedNames,
        strikerId: manualStrikerIdOverride,
        nonStrikerId: manualNonStrikerIdOverride,
        bowlerId: manualBowlerIdOverride,
      );
    } else if (activeInningsNumber == 3 && finalInn3 != null) {
      finalInn3 = _applyManualOverrides(
        finalInn3,
        resolvedNames: resolvedNames,
        strikerId: manualStrikerIdOverride,
        nonStrikerId: manualNonStrikerIdOverride,
        bowlerId: manualBowlerIdOverride,
      );
    } else if (activeInningsNumber == 4 && finalInn4 != null) {
      finalInn4 = _applyManualOverrides(
        finalInn4,
        resolvedNames: resolvedNames,
        strikerId: manualStrikerIdOverride,
        nonStrikerId: manualNonStrikerIdOverride,
        bowlerId: manualBowlerIdOverride,
      );
    }

    MatchStatus status = MatchStatus.live;
    MatchSide? winnerSide;
    String? resultSummary;

    if (resolvedConfig.isAbandoned) {
      status = MatchStatus.completed;
      resultSummary = 'Match abandoned (No result)';
    } else if (finalInn4 != null && finalInn4.isComplete && finalInn3 != null) {
      status = MatchStatus.completed;
      final soTarget = finalInn3.totalRuns + 1;
      if (finalInn4.totalRuns >= soTarget) {
        winnerSide = finalInn4.battingSide;
        resultSummary =
            '${_displayLabel(resolvedConfig, finalInn4.battingSide, teamNamesById)} won Super Over';
      } else if (finalInn4.totalRuns == finalInn3.totalRuns) {
        resultSummary = 'Super Over tied';
      } else {
        winnerSide = finalInn4.bowlingSide;
        resultSummary =
            '${_displayLabel(resolvedConfig, finalInn4.bowlingSide, teamNamesById)} won Super Over';
      }
    } else if (finalInn4 == null && finalInn3 != null && finalInn3.isComplete) {
      status = MatchStatus.inningsBreak;
      resultSummary =
          'Super Over break · ${_displayLabel(resolvedConfig, resolvedConfig.battingFirstSide, teamNamesById)} need ${finalInn3.totalRuns + 1} in 1 ov';
    } else if (finalInn3 != null) {
      status = MatchStatus.live;
    } else if (finalInn2 != null && finalInn2.isComplete) {
      status = MatchStatus.completed;
      final target = finalInn2.target ?? (finalInn1.totalRuns + 1);
      final targetScore = target - 1;
      if (finalInn2.totalRuns >= target) {
        winnerSide = finalInn2.battingSide;
        final wicketsLeft =
            (resolvedConfig.playersPerSide - 1 - finalInn2.wickets).clamp(1, 10);
        resultSummary =
            '${_displayLabel(resolvedConfig, finalInn2.battingSide, teamNamesById)} won by $wicketsLeft wicket${wicketsLeft == 1 ? '' : 's'}';
      } else if (finalInn2.totalRuns == targetScore) {
        resultSummary = 'Match tied';
      } else {
        winnerSide = finalInn2.bowlingSide;
        final margin = targetScore - finalInn2.totalRuns;
        resultSummary =
            '${_displayLabel(resolvedConfig, finalInn2.bowlingSide, teamNamesById)} won by $margin run${margin == 1 ? '' : 's'}';
      }
    } else if (!showInnings2 && finalInn1.isComplete) {
      status = MatchStatus.inningsBreak;
      resultSummary =
          'Innings break · ${_displayLabel(resolvedConfig, resolvedConfig.battingSecondSide, teamNamesById)} need ${finalInn1.totalRuns + 1}';
    }

    return DerivedMatchState(
      config: resolvedConfig,
      innings1: finalInn1,
      innings2: finalInn2,
      innings3: finalInn3,
      innings4: finalInn4,
      activeInningsNumber: activeInningsNumber,
      status: status,
      winnerSide: winnerSide,
      resultSummary: resultSummary,
      unsyncedCount: unsyncedCount,
      resolvedPlayerNames: Map.unmodifiable(resolvedNames),
    );
  }

  static DerivedMatchState _deriveTestMatch({
    required MatchConfig config,
    required Map<String, String> resolvedNames,
    required Map<String, String> teamNamesById,
    required List<BallEvent> inn1Events,
    required List<BallEvent> inn2Events,
    required List<BallEvent> inn3Events,
    required List<BallEvent> inn4Events,
    required int unsyncedCount,
    int? forcedInnings,
    String? manualStrikerIdOverride,
    String? manualNonStrikerIdOverride,
    String? manualBowlerIdOverride,
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
          config.openingStriker1Id ?? '',
          config.openingNonStriker1Id ?? '',
          config.openingBowler1Id ?? '',
        );
      }
      if (inn == 2) {
        return (
          config.openingStriker2Id ?? '',
          config.openingNonStriker2Id ?? '',
          config.openingBowler2Id ?? '',
        );
      }
      final batRoster = config.rosterIdsForSide(batSide);
      final bowlRoster = config.rosterIdsForSide(bowlSide);
      return (
        batRoster.isNotEmpty ? batRoster[0] : '',
        batRoster.length > 1 ? batRoster[1] : '',
        bowlRoster.isNotEmpty ? bowlRoster[0] : '',
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
      openingStrikerId: op1.$1,
      openingNonStrikerId: op1.$2,
      openingBowlerId: op1.$3,
      events: inn1Events,
      resolvedNames: resolvedNames,
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
        openingStrikerId: op2.$1,
        openingNonStrikerId: op2.$2,
        openingBowlerId: op2.$3,
        events: inn2Events,
        resolvedNames: resolvedNames,
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
        openingStrikerId: op3.$1,
        openingNonStrikerId: op3.$2,
        openingBowlerId: op3.$3,
        events: inn3Events,
        resolvedNames: resolvedNames,
        isDeclared: config.declaredInnings.contains(3),
        target: null,
      );
    }

    int? target4;
    if (inn2 != null && inn3 != null) {
      if (followOn) {
        final lead = (inn2.totalRuns + inn3.totalRuns) - inn1.totalRuns;
        if (lead >= 0) target4 = lead + 1;
      } else {
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
        openingStrikerId: op4.$1,
        openingNonStrikerId: op4.$2,
        openingBowlerId: op4.$3,
        events: inn4Events,
        resolvedNames: resolvedNames,
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

    if (activeNum == 1) {
      inn1 = _applyManualOverrides(
        inn1,
        resolvedNames: resolvedNames,
        strikerId: manualStrikerIdOverride,
        nonStrikerId: manualNonStrikerIdOverride,
        bowlerId: manualBowlerIdOverride,
      );
    } else if (activeNum == 2 && inn2 != null) {
      inn2 = _applyManualOverrides(
        inn2,
        resolvedNames: resolvedNames,
        strikerId: manualStrikerIdOverride,
        nonStrikerId: manualNonStrikerIdOverride,
        bowlerId: manualBowlerIdOverride,
      );
    } else if (activeNum == 3 && inn3 != null) {
      inn3 = _applyManualOverrides(
        inn3,
        resolvedNames: resolvedNames,
        strikerId: manualStrikerIdOverride,
        nonStrikerId: manualNonStrikerIdOverride,
        bowlerId: manualBowlerIdOverride,
      );
    } else if (activeNum == 4 && inn4 != null) {
      inn4 = _applyManualOverrides(
        inn4,
        resolvedNames: resolvedNames,
        strikerId: manualStrikerIdOverride,
        nonStrikerId: manualNonStrikerIdOverride,
        bowlerId: manualBowlerIdOverride,
      );
    }

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
              '${_displayLabel(config, inn4.battingSide, teamNamesById)} won by $wLeft wicket${wLeft == 1 ? '' : 's'}';
        } else if (inn4.totalRuns == t4 - 1) {
          resultSummary = 'Match tied';
        } else {
          winnerSide = inn4.bowlingSide;
          final margin = (t4 - 1) - inn4.totalRuns;
          resultSummary =
              '${_displayLabel(config, inn4.bowlingSide, teamNamesById)} won by $margin run${margin == 1 ? '' : 's'}';
        }
      } else {
        final need = (t4 - inn4.totalRuns).clamp(0, 99999);
        leadTrailText =
            '${_displayLabel(config, inn4.battingSide, teamNamesById)} need $need runs';
      }
    } else if (inn3 != null && inn2 != null) {
      final team3Total = followOn
          ? (inn2.totalRuns + inn3.totalRuns)
          : (inn1.totalRuns + inn3.totalRuns);
      final oppTotal = followOn ? inn1.totalRuns : inn2.totalRuns;
      final diff = team3Total - oppTotal;

      if (inn3.isComplete && diff < 0) {
        status = MatchStatus.completed;
        winnerSide = inn3.bowlingSide;
        final margin = -diff;
        resultSummary =
            '${_displayLabel(config, inn3.bowlingSide, teamNamesById)} won by an innings and $margin run${margin == 1 ? '' : 's'}';
      } else if (inn3.isComplete) {
        status = MatchStatus.inningsBreak;
        final target = diff + 1;
        leadTrailText =
            '${_displayLabel(config, inn3.bowlingSide, teamNamesById)} need $target to win';
        resultSummary = 'Innings break · Target $target';
      } else if (diff >= 0) {
        leadTrailText =
            '${_displayLabel(config, inn3.battingSide, teamNamesById)} lead by $diff';
      } else {
        leadTrailText =
            '${_displayLabel(config, inn3.battingSide, teamNamesById)} trail by ${-diff}';
      }
    } else if (inn2 != null) {
      final diff = inn2.totalRuns - inn1.totalRuns;
      if (inn2.isComplete) {
        status = MatchStatus.inningsBreak;
        if (diff < 0) {
          canEnforceFollowOn = true;
          leadTrailText =
              '${_displayLabel(config, inn1.battingSide, teamNamesById)} lead by ${-diff}';
          resultSummary =
              'Innings break · ${_displayLabel(config, inn1.battingSide, teamNamesById)} lead by ${-diff}';
        } else if (diff > 0) {
          leadTrailText =
              '${_displayLabel(config, inn2.battingSide, teamNamesById)} lead by $diff';
          resultSummary =
              'Innings break · ${_displayLabel(config, inn2.battingSide, teamNamesById)} lead by $diff';
        } else {
          leadTrailText = 'Scores level';
          resultSummary = 'Innings break · Scores level';
        }
      } else if (diff >= 0) {
        leadTrailText =
            '${_displayLabel(config, inn2.battingSide, teamNamesById)} lead by $diff';
      } else {
        leadTrailText =
            '${_displayLabel(config, inn2.battingSide, teamNamesById)} trail by ${-diff}';
      }
    } else {
      if (inn1.isComplete) {
        status = MatchStatus.inningsBreak;
        resultSummary =
            'Innings break · ${_displayLabel(config, inn1.battingSide, teamNamesById)} ${inn1.scoreText}';
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
      resolvedPlayerNames: Map.unmodifiable(resolvedNames),
    );
  }

  static DerivedInningsState _applyManualOverrides(
    DerivedInningsState state, {
    required Map<String, String> resolvedNames,
    String? strikerId,
    String? nonStrikerId,
    String? bowlerId,
  }) {
    if (strikerId == null && nonStrikerId == null && bowlerId == null) {
      return state;
    }
    final nextStrikerId = strikerId ?? state.strikerId;
    final nextNonStrikerId = nonStrikerId ?? state.nonStrikerId;
    final nextBowlerId = bowlerId ?? state.currentBowlerId;
    String nameOf(String id, String prev) =>
        id.isEmpty ? '' : (resolvedNames[id] ?? (id == prev ? prev : id));

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
      strikerId: nextStrikerId,
      nonStrikerId: nextNonStrikerId,
      currentBowlerId: nextBowlerId,
      striker: nextStrikerId == state.strikerId
          ? state.striker
          : nameOf(nextStrikerId, state.striker),
      nonStriker: nextNonStrikerId == state.nonStrikerId
          ? state.nonStriker
          : nameOf(nextNonStrikerId, state.nonStriker),
      currentBowler: nextBowlerId == state.currentBowlerId
          ? state.currentBowler
          : nameOf(nextBowlerId, state.currentBowler),
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
    required String openingStrikerId,
    required String openingNonStrikerId,
    required String openingBowlerId,
    required List<BallEvent> events,
    required Map<String, String> resolvedNames,
    bool isDeclared = false,
    required int? target,
  }) {
    String nameOf(String id) =>
        id.isEmpty ? '' : (resolvedNames[id] ?? 'Player');

    int totalRuns = 0;
    int wickets = 0;
    int legalBalls = 0;
    int wides = 0;
    int noBalls = 0;
    int byes = 0;
    int legByes = 0;

    String strikerId = openingStrikerId.trim();
    String nonStrikerId = openingNonStrikerId.trim();
    String currentBowlerId = openingBowlerId.trim();

    final batterOrder = <String>[
      if (strikerId.isNotEmpty) strikerId,
      if (nonStrikerId.isNotEmpty && nonStrikerId != strikerId) nonStrikerId,
    ];
    final batterStats = <String, _MutableBatter>{
      for (final id in batterOrder) id: _MutableBatter(id, nameOf(id)),
    };

    final bowlerOrder = <String>[
      if (currentBowlerId.isNotEmpty) currentBowlerId,
    ];
    final bowlerStats = <String, _MutableBowler>{
      for (final id in bowlerOrder) id: _MutableBowler(id, nameOf(id)),
    };

    final overs = <OverSummary>[];
    var currentOverBalls = <BallEvent>[];
    var currentOverLegal = 0;
    var currentOverRuns = 0;
    var currentOverWickets = 0;
    var currentOverBowlerId = currentBowlerId;
    var currentOverNumber = 1;

    final fallOfWickets = <FallOfWicket>[];

    _MutableBatter ensureBatter(String id) {
      if (!batterStats.containsKey(id)) {
        batterOrder.add(id);
        batterStats[id] = _MutableBatter(id, nameOf(id));
      }
      return batterStats[id]!;
    }

    _MutableBowler ensureBowler(String id) {
      if (!bowlerStats.containsKey(id)) {
        bowlerOrder.add(id);
        bowlerStats[id] = _MutableBowler(id, nameOf(id));
      }
      return bowlerStats[id]!;
    }

    for (final ball in events) {
      final b = ensureBatter(ball.strikerId);
      ensureBatter(ball.nonStrikerId);
      final bowl = ensureBowler(ball.bowlerId);

      strikerId = ball.strikerId;
      nonStrikerId = ball.nonStrikerId;
      currentBowlerId = ball.bowlerId;
      currentOverBowlerId = ball.bowlerId;

      totalRuns += ball.totalRuns;
      currentOverRuns += ball.totalRuns;

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

      if (ball.isWicket) {
        final dismissedId = ball.dismissedBatterId ?? ball.strikerId;
        final dismissed = ensureBatter(dismissedId);
        final countsWicket = ball.wicketType?.countsAsTeamWicket ?? true;

        if (countsWicket) {
          wickets += 1;
          currentOverWickets += 1;
          dismissed.isOut = true;
          dismissed.dismissalText =
              ball.scorecardDismissalText(resolvedNames) ?? 'out';

          if (ball.wicketType?.creditedToBowler ?? true) {
            bowl.wickets += 1;
          }

          fallOfWickets.add(
            FallOfWicket(
              wicketNumber: wickets,
              runsAtFall: totalRuns,
              oversAtFall: '${legalBalls ~/ 6}.${legalBalls % 6}',
              batterId: dismissedId,
              batterName: nameOf(dismissedId),
            ),
          );
        } else {
          dismissed.isOut = false;
          dismissed.dismissalText = 'retired hurt';
        }

        final incomingId = ball.nextBatterId?.trim() ?? '';
        if (incomingId.isNotEmpty) {
          ensureBatter(incomingId);
        }
        if (dismissedId == nonStrikerId) {
          nonStrikerId = incomingId;
        } else {
          strikerId = incomingId;
        }
      }

      if (ball.runningRuns.isOdd) {
        final temp = strikerId;
        strikerId = nonStrikerId;
        nonStrikerId = temp;
      }

      currentOverBalls.add(ball);

      if (currentOverLegal == 6) {
        if (currentOverRuns == 0) {
          bowl.maidens += 1;
        }
        overs.add(
          OverSummary(
            overNumber: currentOverNumber,
            bowlerId: currentOverBowlerId,
            bowler: nameOf(currentOverBowlerId),
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

        final temp = strikerId;
        strikerId = nonStrikerId;
        nonStrikerId = temp;
      }
    }

    if (currentOverBalls.isNotEmpty ||
        oversLimit <= 0 ||
        overs.length < oversLimit) {
      overs.add(
        OverSummary(
          overNumber: currentOverNumber,
          bowlerId: currentOverBowlerId,
          bowler: nameOf(currentOverBowlerId),
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
      strikerId: strikerId,
      nonStrikerId: nonStrikerId,
      currentBowlerId: currentBowlerId,
      striker: nameOf(strikerId),
      nonStriker: nameOf(nonStrikerId),
      currentBowler: nameOf(currentBowlerId),
      batters: [
        for (final id in batterOrder) batterStats[id]!.toLine(),
      ],
      bowlers: [
        for (final id in bowlerOrder) bowlerStats[id]!.toLine(),
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
  _MutableBatter(this.playerId, this.name);
  final String playerId;
  final String name;
  int runs = 0;
  int balls = 0;
  int fours = 0;
  int sixes = 0;
  bool isOut = false;
  String? dismissalText;

  BatterLine toLine() => BatterLine(
        playerId: playerId,
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
  _MutableBowler(this.playerId, this.name);
  final String playerId;
  final String name;
  int legalBalls = 0;
  int maidens = 0;
  int runsConceded = 0;
  int wickets = 0;

  BowlerLine toLine() => BowlerLine(
        playerId: playerId,
        name: name,
        legalBalls: legalBalls,
        maidens: maidens,
        runsConceded: runsConceded,
        wickets: wickets,
      );
}
