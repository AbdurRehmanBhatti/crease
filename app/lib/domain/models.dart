import 'dart:convert';

import 'package:flutter/foundation.dart';

enum ExtraType {
  none,
  wide,
  noBall,
  bye,
  legBye,
  penalty;

  bool get isLegalDelivery =>
      this != wide && this != noBall && this != penalty;

  String get shortLabel => switch (this) {
        ExtraType.none => '',
        ExtraType.wide => 'wd',
        ExtraType.noBall => 'nb',
        ExtraType.bye => 'b',
        ExtraType.legBye => 'lb',
        ExtraType.penalty => 'pen',
      };

  String get displayLabel => switch (this) {
        ExtraType.none => 'None',
        ExtraType.wide => 'Wide',
        ExtraType.noBall => 'No ball',
        ExtraType.bye => 'Bye',
        ExtraType.legBye => 'Leg bye',
        ExtraType.penalty => 'Penalty',
      };

  static ExtraType fromName(String value) => ExtraType.values.firstWhere(
        (e) => e.name == value,
        orElse: () => ExtraType.none,
      );
}

enum WicketType {
  bowled,
  caught,
  lbw,
  runOut,
  stumped,
  hitWicket,
  retiredHurt,
  retired;

  bool get countsAsTeamWicket => this != retiredHurt;

  bool get creditedToBowler =>
      this != runOut && this != retired && this != retiredHurt;

  String get label => switch (this) {
        WicketType.bowled => 'Bowled',
        WicketType.caught => 'Caught',
        WicketType.lbw => 'LBW',
        WicketType.runOut => 'Run out',
        WicketType.stumped => 'Stumped',
        WicketType.hitWicket => 'Hit wicket',
        WicketType.retiredHurt => 'Retired hurt',
        WicketType.retired => 'Retired out',
      };

  static WicketType? fromNullableName(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final w in WicketType.values) {
      if (w.name == value) return w;
    }
    return null;
  }
}

enum MatchStatus {
  live,
  inningsBreak,
  completed;

  static MatchStatus fromName(String value) => MatchStatus.values.firstWhere(
        (e) => e.name == value,
        orElse: () => MatchStatus.live,
      );
}

/// Identifies a match side independent of its display name so same-name
/// derbies (e.g. two clubs both named "Bhatti XI") never collide.
enum MatchSide { a, b }

@immutable
class MatchConfig {
  const MatchConfig({
    required this.id,
    required this.teamA,
    required this.teamB,
    this.teamAId,
    this.teamBId,
    required this.oversLimit,
    this.playersPerSide = 11,
    required this.formatLabel,
    required this.battingFirstTeam,
    required this.openingStrikerInnings1,
    required this.openingNonStrikerInnings1,
    required this.openingBowlerInnings1,
    this.openingStrikerInnings2 = 'Opener 1',
    this.openingNonStrikerInnings2 = 'Opener 2',
    this.openingBowlerInnings2 = 'Bowler 1',
    this.teamAPlayers = const [],
    this.teamBPlayers = const [],
    this.tournamentId,
    this.tournamentStage,
    this.fixtureIndex,
    this.isTestMatch = false,
    this.declaredInnings = const [],
    this.followOnEnforced = false,
    this.firstInningsTargetOverride,
    this.isDemo = false,
    required this.createdAt,
  });

  final String id;
  final String teamA;
  final String teamB;
  final String? teamAId;
  final String? teamBId;
  final int oversLimit; // 0 = unlimited overs (Test match)
  final int playersPerSide;
  final String formatLabel;
  final String battingFirstTeam;
  final String openingStrikerInnings1;
  final String openingNonStrikerInnings1;
  final String openingBowlerInnings1;
  final String openingStrikerInnings2;
  final String openingNonStrikerInnings2;
  final String openingBowlerInnings2;
  final List<String> teamAPlayers;
  final List<String> teamBPlayers;
  final String? tournamentId;
  final String? tournamentStage; // league | quarterFinal | semiFinal | finalMatch
  final int? fixtureIndex; // 1-based scheduled slot within tournament
  final bool isTestMatch;
  final List<int> declaredInnings;
  final bool followOnEnforced;

  /// Optional target override for starting directly in a 2nd-innings chase demo.
  final int? firstInningsTargetOverride;
  final bool isDemo;
  final DateTime createdAt;

  MatchSide get battingFirstSide =>
      battingFirstTeam == teamA ? MatchSide.a : MatchSide.b;

  MatchSide get battingSecondSide =>
      battingFirstSide == MatchSide.a ? MatchSide.b : MatchSide.a;

  String get battingSecondTeam => teamNameForSide(battingSecondSide);

  bool get hasSameTeamNames =>
      teamA.trim().toLowerCase() == teamB.trim().toLowerCase();

  String get title => '$teamA v $teamB';

  /// Matches abandoned due to rain / mutual agreement encode `-1` in `declaredInnings`.
  bool get isAbandoned => declaredInnings.contains(-1);

  String teamNameForSide(MatchSide side) =>
      side == MatchSide.a ? teamA : teamB;

  List<String> rosterForSide(MatchSide side) =>
      side == MatchSide.a ? teamAPlayers : teamBPlayers;

  List<String> rosterForTeam(String teamName) =>
      teamName == teamA ? teamAPlayers : teamBPlayers;

  /// Returns which side (`MatchSide.a` or `MatchSide.b`) corresponds to
  /// [teamId] (preferred) or [teamName] (fallback for legacy/ad-hoc matches
  /// without IDs), or `null` if this match does not involve that team.
  MatchSide? sideForTeam({String? teamId, String? teamName}) {
    final cleanId = teamId?.trim();
    if (cleanId != null && cleanId.isNotEmpty) {
      if (teamAId == cleanId) return MatchSide.a;
      if (teamBId == cleanId) return MatchSide.b;
    }
    final lower = teamName?.trim().toLowerCase();
    if (lower == null || lower.isEmpty) return null;
    if (teamAId == null && teamA.toLowerCase() == lower) return MatchSide.a;
    if (teamBId == null && teamB.toLowerCase() == lower) return MatchSide.b;
    if (cleanId == null || cleanId.isEmpty) {
      if (teamA.toLowerCase() == lower) return MatchSide.a;
      if (teamB.toLowerCase() == lower) return MatchSide.b;
    }
    return null;
  }

  /// Returns the match's display name for the side corresponding to [teamId]
  /// (preferred) or [teamName] (fallback for legacy/ad-hoc matches without IDs),
  /// or `null` if this match does not involve that team.
  String? sideNameForTeam({String? teamId, String? teamName}) {
    final side = sideForTeam(teamId: teamId, teamName: teamName);
    return side == null ? null : teamNameForSide(side);
  }

  bool involvesTeam({String? teamId, String? teamName}) =>
      sideForTeam(teamId: teamId, teamName: teamName) != null;

  MatchConfig copyWith({
    int? oversLimit,
    String? formatLabel,
    List<String>? teamAPlayers,
    List<String>? teamBPlayers,
    List<int>? declaredInnings,
    bool? followOnEnforced,
    int? firstInningsTargetOverride,
    bool clearTargetOverride = false,
  }) =>
      MatchConfig(
        id: id,
        teamA: teamA,
        teamB: teamB,
        teamAId: teamAId,
        teamBId: teamBId,
        oversLimit: oversLimit ?? this.oversLimit,
        playersPerSide: playersPerSide,
        formatLabel: formatLabel ?? this.formatLabel,
        battingFirstTeam: battingFirstTeam,
        openingStrikerInnings1: openingStrikerInnings1,
        openingNonStrikerInnings1: openingNonStrikerInnings1,
        openingBowlerInnings1: openingBowlerInnings1,
        openingStrikerInnings2: openingStrikerInnings2,
        openingNonStrikerInnings2: openingNonStrikerInnings2,
        openingBowlerInnings2: openingBowlerInnings2,
        teamAPlayers: teamAPlayers ?? this.teamAPlayers,
        teamBPlayers: teamBPlayers ?? this.teamBPlayers,
        tournamentId: tournamentId,
        tournamentStage: tournamentStage,
        fixtureIndex: fixtureIndex,
        isTestMatch: isTestMatch,
        declaredInnings: declaredInnings ?? this.declaredInnings,
        followOnEnforced: followOnEnforced ?? this.followOnEnforced,
        firstInningsTargetOverride: clearTargetOverride
            ? null
            : (firstInningsTargetOverride ?? this.firstInningsTargetOverride),
        isDemo: isDemo,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'team_a': teamA,
        'team_b': teamB,
        'team_a_id': teamAId,
        'team_b_id': teamBId,
        'overs_limit': oversLimit,
        'players_per_side': playersPerSide,
        'format_label': formatLabel,
        'batting_first_team': battingFirstTeam,
        'opening_striker_1': openingStrikerInnings1,
        'opening_non_striker_1': openingNonStrikerInnings1,
        'opening_bowler_1': openingBowlerInnings1,
        'opening_striker_2': openingStrikerInnings2,
        'opening_non_striker_2': openingNonStrikerInnings2,
        'opening_bowler_2': openingBowlerInnings2,
        'team_a_players': jsonEncode(teamAPlayers),
        'team_b_players': jsonEncode(teamBPlayers),
        'tournament_id': tournamentId,
        'tournament_stage': tournamentStage,
        'fixture_index': fixtureIndex,
        'is_test_match': isTestMatch ? 1 : 0,
        'declared_innings': jsonEncode(declaredInnings),
        'follow_on_enforced': followOnEnforced ? 1 : 0,
        'first_innings_target_override': firstInningsTargetOverride,
        'is_demo': isDemo ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static bool _decodeBool(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    return false;
  }

  static List<int> _decodeInts(Object? raw) {
    if (raw is List) {
      return raw.map((e) => int.parse(e.toString())).toList();
    }
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        return list.map((e) => int.parse(e.toString())).toList();
      }
    } catch (_) {}
    return const [];
  }

  static List<String> _decodePlayers(Object? raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        return list.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return const [];
  }

  static MatchConfig fromMap(Map<String, Object?> map) => MatchConfig(
        id: map['id']! as String,
        teamA: map['team_a']! as String,
        teamB: map['team_b']! as String,
        teamAId: map['team_a_id'] as String?,
        teamBId: map['team_b_id'] as String?,
        oversLimit: (map['overs_limit']! as num).toInt(),
        playersPerSide: ((map['players_per_side'] as num?) ?? 11).toInt(),
        formatLabel: map['format_label']! as String,
        battingFirstTeam: map['batting_first_team']! as String,
        openingStrikerInnings1: map['opening_striker_1']! as String,
        openingNonStrikerInnings1: map['opening_non_striker_1']! as String,
        openingBowlerInnings1: map['opening_bowler_1']! as String,
        openingStrikerInnings2:
            (map['opening_striker_2'] as String?) ?? 'Opener 1',
        openingNonStrikerInnings2:
            (map['opening_non_striker_2'] as String?) ?? 'Opener 2',
        openingBowlerInnings2:
            (map['opening_bowler_2'] as String?) ?? 'Bowler 1',
        teamAPlayers: _decodePlayers(map['team_a_players']),
        teamBPlayers: _decodePlayers(map['team_b_players']),
        tournamentId: map['tournament_id'] as String?,
        tournamentStage: map['tournament_stage'] as String?,
        fixtureIndex: (map['fixture_index'] as num?)?.toInt(),
        isTestMatch: _decodeBool(map['is_test_match']),
        declaredInnings: _decodeInts(map['declared_innings']),
        followOnEnforced: _decodeBool(map['follow_on_enforced']),
        firstInningsTargetOverride:
            (map['first_innings_target_override'] as num?)?.toInt(),
        isDemo: _decodeBool(map['is_demo']),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at']! as num).toInt(),
        ),
      );
}

/// Append-only ball event. Every scorecard, stat, over timeline, and NRR
/// is derived from the ordered list of non-voided [BallEvent]s.
@immutable
class BallEvent {
  const BallEvent({
    required this.id,
    required this.matchId,
    required this.inningsNumber,
    required this.sequenceNumber,
    required this.striker,
    required this.nonStriker,
    required this.bowler,
    this.runsOffBat = 0,
    this.extraType = ExtraType.none,
    this.extraRuns = 0,
    this.isWicket = false,
    this.wicketType,
    this.dismissedBatter,
    this.fielder,
    this.nextBatter,
    this.synced = false,
    this.voided = false,
    required this.createdAt,
  });

  final String id;
  final String matchId;
  final int inningsNumber; // 1 or 2
  final int sequenceNumber;
  final String striker;
  final String nonStriker;
  final String bowler;
  final int runsOffBat;
  final ExtraType extraType;
  final int extraRuns;
  final bool isWicket;
  final WicketType? wicketType;
  final String? dismissedBatter;
  final String? fielder;
  final String? nextBatter;
  final bool synced;
  final bool voided;
  final DateTime createdAt;

  int get totalRuns => runsOffBat + extraRuns;
  bool get isLegalDelivery =>
      extraType.isLegalDelivery && wicketType != WicketType.retiredHurt;

  /// Runs that rotate strike between batters (excludes the 1-run penalty for wide/no-ball and penalty runs).
  int get runningRuns {
    if (extraType == ExtraType.penalty) return 0;
    if (extraType == ExtraType.wide) {
      return (extraRuns - 1).clamp(0, 10);
    }
    if (extraType == ExtraType.noBall) {
      return runsOffBat + (extraRuns - 1).clamp(0, 10);
    }
    return runsOffBat + extraRuns;
  }

  /// Short notation shown inside an over-timeline ball circle.
  String get shortMark {
    if (isWicket) {
      if (wicketType == WicketType.retiredHurt) return 'RH';
      if (extraType == ExtraType.wide) return 'W+wd';
      if (extraType == ExtraType.noBall) return 'W+nb';
      return 'W';
    }
    if (extraType == ExtraType.penalty) return '+${extraRuns}p';
    if (extraType == ExtraType.wide) {
      return extraRuns > 1 ? '${extraRuns}wd' : 'wd';
    }
    if (extraType == ExtraType.noBall) {
      final total = runsOffBat + extraRuns;
      return total > 1 ? '${total}nb' : 'nb';
    }
    if (extraType == ExtraType.bye) return '${extraRuns}b';
    if (extraType == ExtraType.legBye) return '${extraRuns}lb';
    if (runsOffBat == 0) return '•';
    return '$runsOffBat';
  }

  String? get dismissalSummary {
    if (!isWicket) return null;
    final who = dismissedBatter ?? striker;
    return '$who ${scorecardDismissalText ?? 'out'}';
  }

  /// Cricket-standard scorecard dismissal line (omits the batter's own name).
  String? get scorecardDismissalText {
    if (!isWicket) return null;
    return switch (wicketType) {
      WicketType.caught =>
        fielder != null && fielder!.isNotEmpty
            ? 'c $fielder b $bowler'
            : 'c & b $bowler',
      WicketType.bowled => 'b $bowler',
      WicketType.lbw => 'lbw b $bowler',
      WicketType.runOut =>
        fielder != null && fielder!.isNotEmpty
            ? 'run out ($fielder)'
            : 'run out',
      WicketType.stumped =>
        fielder != null && fielder!.isNotEmpty
            ? 'st $fielder b $bowler'
            : 'stumped b $bowler',
      WicketType.hitWicket => 'hit wkt b $bowler',
      WicketType.retiredHurt => 'retired hurt',
      WicketType.retired => 'retired out',
      null => 'out',
    };
  }

  BallEvent copyWith({
    String? striker,
    String? nonStriker,
    String? bowler,
    int? runsOffBat,
    ExtraType? extraType,
    int? extraRuns,
    bool? isWicket,
    WicketType? wicketType,
    String? dismissedBatter,
    String? fielder,
    String? nextBatter,
    bool? synced,
    bool? voided,
  }) {
    return BallEvent(
      id: id,
      matchId: matchId,
      inningsNumber: inningsNumber,
      sequenceNumber: sequenceNumber,
      striker: striker ?? this.striker,
      nonStriker: nonStriker ?? this.nonStriker,
      bowler: bowler ?? this.bowler,
      runsOffBat: runsOffBat ?? this.runsOffBat,
      extraType: extraType ?? this.extraType,
      extraRuns: extraRuns ?? this.extraRuns,
      isWicket: isWicket ?? this.isWicket,
      wicketType: wicketType ?? this.wicketType,
      dismissedBatter: dismissedBatter ?? this.dismissedBatter,
      fielder: fielder ?? this.fielder,
      nextBatter: nextBatter ?? this.nextBatter,
      synced: synced ?? this.synced,
      voided: voided ?? this.voided,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'match_id': matchId,
        'innings_number': inningsNumber,
        'sequence_number': sequenceNumber,
        'striker': striker,
        'non_striker': nonStriker,
        'bowler': bowler,
        'runs_off_bat': runsOffBat,
        'extra_type': extraType.name,
        'extra_runs': extraRuns,
        'is_wicket': isWicket ? 1 : 0,
        'wicket_type': wicketType?.name,
        'dismissed_batter': dismissedBatter,
        'fielder': fielder,
        'next_batter': nextBatter,
        'synced': synced ? 1 : 0,
        'voided': voided ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static bool _decodeBool(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    return false;
  }

  static BallEvent fromMap(Map<String, Object?> map) => BallEvent(
        id: map['id']! as String,
        matchId: map['match_id']! as String,
        inningsNumber: (map['innings_number']! as num).toInt(),
        sequenceNumber: (map['sequence_number']! as num).toInt(),
        striker: map['striker']! as String,
        nonStriker: map['non_striker']! as String,
        bowler: map['bowler']! as String,
        runsOffBat: ((map['runs_off_bat'] as num?) ?? 0).toInt(),
        extraType: ExtraType.fromName((map['extra_type'] as String?) ?? 'none'),
        extraRuns: ((map['extra_runs'] as num?) ?? 0).toInt(),
        isWicket: _decodeBool(map['is_wicket']),
        wicketType: WicketType.fromNullableName(map['wicket_type'] as String?),
        dismissedBatter: map['dismissed_batter'] as String?,
        fielder: map['fielder'] as String?,
        nextBatter: map['next_batter'] as String?,
        synced: _decodeBool(map['synced']),
        voided: _decodeBool(map['voided']),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at']! as num).toInt(),
        ),
      );
}

@immutable
class BatterLine {
  const BatterLine({
    required this.name,
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
    required this.isOut,
    this.dismissalText,
  });

  final String name;
  final int runs;
  final int balls;
  final int fours;
  final int sixes;
  final bool isOut;
  final String? dismissalText;

  double get strikeRate => balls == 0 ? 0.0 : (runs / balls) * 100.0;
}

@immutable
class BowlerLine {
  const BowlerLine({
    required this.name,
    required this.legalBalls,
    required this.maidens,
    required this.runsConceded,
    required this.wickets,
  });

  final String name;
  final int legalBalls;
  final int maidens;
  final int runsConceded;
  final int wickets;

  String get oversText => '${legalBalls ~/ 6}.${legalBalls % 6}';
  String get figuresText => '$oversText-$maidens-$runsConceded-$wickets';
  double get economy =>
      legalBalls == 0 ? 0.0 : runsConceded / (legalBalls / 6.0);
}

@immutable
class OverSummary {
  const OverSummary({
    required this.overNumber, // 1-based
    required this.bowler,
    required this.balls,
    required this.runsInOver,
    required this.wicketsInOver,
    required this.legalBallsInOver,
  });

  final int overNumber;
  final String bowler;
  final List<BallEvent> balls;
  final int runsInOver;
  final int wicketsInOver;
  final int legalBallsInOver;

  bool get isComplete => legalBallsInOver >= 6;
}

@immutable
class FallOfWicket {
  const FallOfWicket({
    required this.wicketNumber,
    required this.runsAtFall,
    required this.oversAtFall,
    required this.batterName,
  });

  final int wicketNumber;
  final int runsAtFall;
  final String oversAtFall;
  final String batterName;
}

@immutable
class DerivedInningsState {
  const DerivedInningsState({
    required this.inningsNumber,
    required this.battingTeam,
    required this.bowlingTeam,
    this.battingSide = MatchSide.a,
    required this.totalRuns,
    required this.wickets,
    required this.legalBalls,
    required this.oversLimit,
    required this.playersPerSide,
    required this.striker,
    required this.nonStriker,
    required this.currentBowler,
    required this.batters,
    required this.bowlers,
    required this.overs,
    required this.fallOfWickets,
    required this.wides,
    required this.noBalls,
    required this.byes,
    required this.legByes,
    required this.isComplete,
    this.isDeclared = false,
    this.target,
  });

  final int inningsNumber;
  final String battingTeam;
  final String bowlingTeam;
  final MatchSide battingSide;
  final int totalRuns;

  MatchSide get bowlingSide =>
      battingSide == MatchSide.a ? MatchSide.b : MatchSide.a;
  final int wickets;
  final int legalBalls;
  final int oversLimit; // 0 = unlimited (Test)
  final int playersPerSide;
  final String striker;
  final String nonStriker;
  final String currentBowler;
  final List<BatterLine> batters;
  final List<BowlerLine> bowlers;
  final List<OverSummary> overs;
  final List<FallOfWicket> fallOfWickets;
  final int wides;
  final int noBalls;
  final int byes;
  final int legByes;
  final bool isComplete;
  final bool isDeclared;
  final int? target;

  int get extrasTotal => wides + noBalls + byes + legByes;
  bool get needsNextBatter =>
      !isComplete && (striker.isEmpty || nonStriker.isEmpty);
  String get scoreText =>
      '$totalRuns/$wickets${isDeclared ? 'd' : ''}';
  String get oversText => '${legalBalls ~/ 6}.${legalBalls % 6}';
  double get currentRunRate =>
      legalBalls == 0 ? 0.0 : totalRuns / (legalBalls / 6.0);

  int get maxBalls => oversLimit <= 0 ? 0 : oversLimit * 6;
  int get ballsRemaining =>
      oversLimit <= 0 ? 0 : (maxBalls - legalBalls).clamp(0, maxBalls);
  int? get runsNeeded =>
      target == null ? null : (target! - totalRuns).clamp(0, 9999);
  double? get requiredRunRate {
    if (oversLimit <= 0) return null;
    final needed = runsNeeded;
    if (needed == null || needed <= 0) return 0.0;
    if (ballsRemaining == 0) return null;
    return needed / (ballsRemaining / 6.0);
  }

  BatterLine batterByName(String name) => batters.firstWhere(
        (b) => b.name == name,
        orElse: () => BatterLine(
          name: name,
          runs: 0,
          balls: 0,
          fours: 0,
          sixes: 0,
          isOut: false,
        ),
      );

  BowlerLine bowlerByName(String name) => bowlers.firstWhere(
        (b) => b.name == name,
        orElse: () => BowlerLine(
          name: name,
          legalBalls: 0,
          maidens: 0,
          runsConceded: 0,
          wickets: 0,
        ),
      );
}

@immutable
class DerivedMatchState {
  const DerivedMatchState({
    required this.config,
    required this.innings1,
    this.innings2,
    this.innings3,
    this.innings4,
    required this.activeInningsNumber,
    required this.status,
    this.winnerSide,
    this.resultSummary,
    this.leadTrailText,
    this.canEnforceFollowOn = false,
    required this.unsyncedCount,
  });

  final MatchConfig config;
  final DerivedInningsState innings1;
  final DerivedInningsState? innings2;
  final DerivedInningsState? innings3;
  final DerivedInningsState? innings4;
  final int activeInningsNumber;
  final MatchStatus status;
  final MatchSide? winnerSide;
  final String? resultSummary;
  final String? leadTrailText;
  final bool canEnforceFollowOn;
  final int unsyncedCount;

  List<DerivedInningsState> get allInnings => [
        innings1,
        ?innings2,
        ?innings3,
        ?innings4,
      ];

  DerivedInningsState inningsByNumber(int n) => switch (n) {
        4 => innings4 ?? innings3 ?? innings2 ?? innings1,
        3 => innings3 ?? innings2 ?? innings1,
        2 => innings2 ?? innings1,
        _ => innings1,
      };

  DerivedInningsState get activeInnings => inningsByNumber(activeInningsNumber);
}

