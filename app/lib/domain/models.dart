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
enum MatchSide {
  a,
  b;

  static MatchSide fromName(String? value) =>
      value == 'b' ? MatchSide.b : MatchSide.a;
}

/// Controls whether a match or tournament is link-only (`unlisted`, default)
/// or listed publicly on Crease's Live discovery tab (`public`).
enum BroadcastVisibility {
  unlisted,
  public;

  bool get isPublic => this == BroadcastVisibility.public;

  static BroadcastVisibility fromName(String? value) =>
      value?.trim().toLowerCase() == 'public'
          ? BroadcastVisibility.public
          : BroadcastVisibility.unlisted;
}

/// Returns true if [name] is a generic placeholder label like "Batter 1" or "Bowler 2".
bool isPlaceholderPlayerName(String name) {
  final t = name.trim();
  if (t.isEmpty) return true;
  return RegExp(r'^(batter|bowler|opener)\s*\d+$', caseSensitive: false)
      .hasMatch(t);
}

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
    this.battingFirstSide = MatchSide.a,
    this.openingStriker1Id,
    this.openingNonStriker1Id,
    this.openingBowler1Id,
    this.openingStriker2Id,
    this.openingNonStriker2Id,
    this.openingBowler2Id,
    this.teamAPlayerIds = const [],
    this.teamBPlayerIds = const [],
    this.adHocPlayers = const {},
    this.tournamentId,
    this.tournamentStage,
    this.fixtureIndex,
    this.isTestMatch = false,
    this.declaredInnings = const [],
    this.followOnEnforced = false,
    this.firstInningsTargetOverride,
    this.visibility = BroadcastVisibility.unlisted,
    this.venue,
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
  final MatchSide battingFirstSide;
  final String? openingStriker1Id;
  final String? openingNonStriker1Id;
  final String? openingBowler1Id;
  final String? openingStriker2Id;
  final String? openingNonStriker2Id;
  final String? openingBowler2Id;
  final List<String> teamAPlayerIds;
  final List<String> teamBPlayerIds;

  /// Map of `<uuid> -> displayName` ONLY for temporary/match-only players
  /// (e.g. "Batter 1", "Bowler 1", or a one-off opposition sub).
  final Map<String, String> adHocPlayers;

  final String? tournamentId;
  final String? tournamentStage; // league | quarterFinal | semiFinal | finalMatch
  final int? fixtureIndex; // 1-based scheduled slot within tournament
  final bool isTestMatch;
  final List<int> declaredInnings;
  final bool followOnEnforced;
  final int? firstInningsTargetOverride;
  final BroadcastVisibility visibility;
  final String? venue;
  final bool isDemo;
  final DateTime createdAt;

  bool get isPublicLive => visibility.isPublic;

  MatchSide get battingSecondSide =>
      battingFirstSide == MatchSide.a ? MatchSide.b : MatchSide.a;

  String get battingFirstTeam => teamNameForSide(battingFirstSide);
  String get battingSecondTeam => teamNameForSide(battingSecondSide);

  bool get hasSameTeamNames =>
      teamA.trim().toLowerCase() == teamB.trim().toLowerCase();

  String get title => '$teamA v $teamB';

  /// Matches abandoned due to rain / mutual agreement encode `-1` in `declaredInnings`.
  bool get isAbandoned => declaredInnings.contains(-1);

  String teamNameForSide(MatchSide side) =>
      side == MatchSide.a ? teamA : teamB;

  String? teamIdForSide(MatchSide side) =>
      side == MatchSide.a ? teamAId : teamBId;

  List<String> rosterIdsForSide(MatchSide side) =>
      side == MatchSide.a ? teamAPlayerIds : teamBPlayerIds;

  String resolvePlayerName(
    String? playerId, [
    Map<String, String> playerNamesById = const {},
  ]) {
    if (playerId == null || playerId.isEmpty) return '';
    return playerNamesById[playerId] ?? adHocPlayers[playerId] ?? '';
  }

  /// Finds an existing ad-hoc player UUID in [adHocPlayers] matching [name]
  /// (case-insensitive), or returns null.
  String? findAdHocPlayerId(String name) {
    final lower = name.trim().toLowerCase();
    if (lower.isEmpty) return null;
    for (final entry in adHocPlayers.entries) {
      if (entry.value.trim().toLowerCase() == lower) return entry.key;
    }
    return null;
  }

  /// Ensures [name] has a UUID in [adHocPlayers] (reusing an existing one if
  /// present) and returns the updated [MatchConfig] and resolved `playerId`.
  ({MatchConfig config, String playerId}) ensureAdHocPlayer(
    String name,
    String Function() generateUuid, {
    MatchSide? addToSide,
  }) {
    final clean = name.trim();
    final existingId = findAdHocPlayerId(clean);
    final pid = existingId ?? generateUuid();
    final nextAdHoc = existingId != null
        ? adHocPlayers
        : {...adHocPlayers, pid: clean};
    var nextA = teamAPlayerIds;
    var nextB = teamBPlayerIds;
    if (addToSide == MatchSide.a && !nextA.contains(pid)) {
      nextA = [...nextA, pid];
    } else if (addToSide == MatchSide.b && !nextB.contains(pid)) {
      nextB = [...nextB, pid];
    }
    return (
      config: copyWith(
        adHocPlayers: nextAdHoc,
        teamAPlayerIds: nextA,
        teamBPlayerIds: nextB,
      ),
      playerId: pid,
    );
  }

  /// Returns which side (`MatchSide.a` or `MatchSide.b`) corresponds to
  /// [teamId] (preferred) or [teamName] (fallback for ad-hoc matches without IDs).
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

  String? sideNameForTeam({String? teamId, String? teamName}) {
    final side = sideForTeam(teamId: teamId, teamName: teamName);
    return side == null ? null : teamNameForSide(side);
  }

  bool involvesTeam({String? teamId, String? teamName}) =>
      sideForTeam(teamId: teamId, teamName: teamName) != null;

  MatchConfig copyWith({
    String? teamA,
    String? teamB,
    String? teamAId,
    String? teamBId,
    int? oversLimit,
    String? formatLabel,
    MatchSide? battingFirstSide,
    String? openingStriker1Id,
    String? openingNonStriker1Id,
    String? openingBowler1Id,
    String? openingStriker2Id,
    String? openingNonStriker2Id,
    String? openingBowler2Id,
    List<String>? teamAPlayerIds,
    List<String>? teamBPlayerIds,
    Map<String, String>? adHocPlayers,
    List<int>? declaredInnings,
    bool? followOnEnforced,
    int? firstInningsTargetOverride,
    bool clearTargetOverride = false,
    BroadcastVisibility? visibility,
    String? venue,
    bool clearVenue = false,
  }) =>
      MatchConfig(
        id: id,
        teamA: teamA ?? this.teamA,
        teamB: teamB ?? this.teamB,
        teamAId: teamAId ?? this.teamAId,
        teamBId: teamBId ?? this.teamBId,
        oversLimit: oversLimit ?? this.oversLimit,
        playersPerSide: playersPerSide,
        formatLabel: formatLabel ?? this.formatLabel,
        battingFirstSide: battingFirstSide ?? this.battingFirstSide,
        openingStriker1Id: openingStriker1Id ?? this.openingStriker1Id,
        openingNonStriker1Id: openingNonStriker1Id ?? this.openingNonStriker1Id,
        openingBowler1Id: openingBowler1Id ?? this.openingBowler1Id,
        openingStriker2Id: openingStriker2Id ?? this.openingStriker2Id,
        openingNonStriker2Id: openingNonStriker2Id ?? this.openingNonStriker2Id,
        openingBowler2Id: openingBowler2Id ?? this.openingBowler2Id,
        teamAPlayerIds: teamAPlayerIds ?? this.teamAPlayerIds,
        teamBPlayerIds: teamBPlayerIds ?? this.teamBPlayerIds,
        adHocPlayers: adHocPlayers ?? this.adHocPlayers,
        tournamentId: tournamentId,
        tournamentStage: tournamentStage,
        fixtureIndex: fixtureIndex,
        isTestMatch: isTestMatch,
        declaredInnings: declaredInnings ?? this.declaredInnings,
        followOnEnforced: followOnEnforced ?? this.followOnEnforced,
        firstInningsTargetOverride: clearTargetOverride
            ? null
            : (firstInningsTargetOverride ?? this.firstInningsTargetOverride),
        visibility: visibility ?? this.visibility,
        venue: clearVenue ? null : (venue ?? this.venue),
        isDemo: isDemo,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'team_a': teamA,
        'team_b': teamB,
        'team_a_id': teamAId,
        'team_b_id': teamBId,
        'batting_first_side': battingFirstSide.name,
        'overs_limit': oversLimit,
        'players_per_side': playersPerSide,
        'format_label': formatLabel,
        'opening_striker_1_id': openingStriker1Id,
        'opening_non_striker_1_id': openingNonStriker1Id,
        'opening_bowler_1_id': openingBowler1Id,
        'opening_striker_2_id': openingStriker2Id,
        'opening_non_striker_2_id': openingNonStriker2Id,
        'opening_bowler_2_id': openingBowler2Id,
        'team_a_player_ids': jsonEncode(teamAPlayerIds),
        'team_b_player_ids': jsonEncode(teamBPlayerIds),
        'ad_hoc_players': jsonEncode(adHocPlayers),
        'tournament_id': tournamentId,
        'tournament_stage': tournamentStage,
        'fixture_index': fixtureIndex,
        'is_test_match': isTestMatch ? 1 : 0,
        'declared_innings': jsonEncode(declaredInnings),
        'follow_on_enforced': followOnEnforced ? 1 : 0,
        'first_innings_target_override': firstInningsTargetOverride,
        'visibility': visibility.name,
        'venue': (venue != null && venue!.trim().isNotEmpty)
            ? venue!.trim()
            : null,
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

  static List<String> _decodeIds(Object? raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        return list.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}
    return const [];
  }

  static Map<String, String> _decodeStringMap(Object? raw) {
    if (raw is Map) {
      return {
        for (final e in raw.entries)
          if (e.key.toString().isNotEmpty && e.value != null)
            e.key.toString(): e.value.toString(),
      };
    }
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          for (final e in decoded.entries)
            if (e.key.toString().isNotEmpty && e.value != null)
              e.key.toString(): e.value.toString(),
        };
      }
    } catch (_) {}
    return const {};
  }

  static String? _cleanNullableId(Object? raw) {
    final s = (raw as String?)?.trim();
    return (s != null && s.isNotEmpty) ? s : null;
  }

  static MatchConfig fromMap(Map<String, Object?> map) => MatchConfig(
        id: map['id']! as String,
        teamA: map['team_a']! as String,
        teamB: map['team_b']! as String,
        teamAId: _cleanNullableId(map['team_a_id']),
        teamBId: _cleanNullableId(map['team_b_id']),
        battingFirstSide: MatchSide.fromName(map['batting_first_side'] as String?),
        oversLimit: (map['overs_limit']! as num).toInt(),
        playersPerSide: ((map['players_per_side'] as num?) ?? 11).toInt(),
        formatLabel: map['format_label']! as String,
        openingStriker1Id: _cleanNullableId(map['opening_striker_1_id']),
        openingNonStriker1Id: _cleanNullableId(map['opening_non_striker_1_id']),
        openingBowler1Id: _cleanNullableId(map['opening_bowler_1_id']),
        openingStriker2Id: _cleanNullableId(map['opening_striker_2_id']),
        openingNonStriker2Id: _cleanNullableId(map['opening_non_striker_2_id']),
        openingBowler2Id: _cleanNullableId(map['opening_bowler_2_id']),
        teamAPlayerIds: _decodeIds(map['team_a_player_ids']),
        teamBPlayerIds: _decodeIds(map['team_b_player_ids']),
        adHocPlayers: _decodeStringMap(map['ad_hoc_players']),
        tournamentId: _cleanNullableId(map['tournament_id']),
        tournamentStage: map['tournament_stage'] as String?,
        fixtureIndex: (map['fixture_index'] as num?)?.toInt(),
        isTestMatch: _decodeBool(map['is_test_match']),
        declaredInnings: _decodeInts(map['declared_innings']),
        followOnEnforced: _decodeBool(map['follow_on_enforced']),
        firstInningsTargetOverride:
            (map['first_innings_target_override'] as num?)?.toInt(),
        visibility: BroadcastVisibility.fromName(map['visibility'] as String?),
        venue: _cleanNullableId(map['venue']),
        isDemo: _decodeBool(map['is_demo']),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at']! as num).toInt(),
        ),
      );
}

/// Strict 3NF append-only ball event storing native player UUIDs only.
/// Display names are resolved dynamically via `PlayerDirectory` + `MatchConfig.adHocPlayers`.
@immutable
class BallEvent {
  const BallEvent({
    required this.id,
    required this.matchId,
    required this.inningsNumber,
    required this.sequenceNumber,
    required this.strikerId,
    required this.nonStrikerId,
    required this.bowlerId,
    this.runsOffBat = 0,
    this.extraType = ExtraType.none,
    this.extraRuns = 0,
    this.isWicket = false,
    this.wicketType,
    this.dismissedBatterId,
    this.fielderId,
    this.nextBatterId,
    this.synced = false,
    this.voided = false,
    required this.createdAt,
  });

  final String id;
  final String matchId;
  final int inningsNumber; // 1..4
  final int sequenceNumber;
  final String strikerId;
  final String nonStrikerId;
  final String bowlerId;
  final int runsOffBat;
  final ExtraType extraType;
  final int extraRuns;
  final bool isWicket;
  final WicketType? wicketType;
  final String? dismissedBatterId;
  final String? fielderId;
  final String? nextBatterId;
  final bool synced;
  final bool voided;
  final DateTime createdAt;

  int get totalRuns => runsOffBat + extraRuns;
  bool get isLegalDelivery =>
      extraType.isLegalDelivery && wicketType != WicketType.retiredHurt;

  /// Runs that rotate strike between batters (excludes 1-run penalty for wide/no-ball and penalty runs).
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

  /// Cricket-standard scorecard dismissal line resolved against current player names.
  String? scorecardDismissalText(Map<String, String> namesById) {
    if (!isWicket) return null;
    final bowlerName = namesById[bowlerId] ?? 'Bowler';
    final fielderName =
        (fielderId != null && fielderId!.isNotEmpty) ? namesById[fielderId!] : null;
    return switch (wicketType) {
      WicketType.caught =>
        fielderName != null && fielderName.isNotEmpty
            ? 'c $fielderName b $bowlerName'
            : 'c & b $bowlerName',
      WicketType.bowled => 'b $bowlerName',
      WicketType.lbw => 'lbw b $bowlerName',
      WicketType.runOut =>
        fielderName != null && fielderName.isNotEmpty
            ? 'run out ($fielderName)'
            : 'run out',
      WicketType.stumped =>
        fielderName != null && fielderName.isNotEmpty
            ? 'st $fielderName b $bowlerName'
            : 'stumped b $bowlerName',
      WicketType.hitWicket => 'hit wkt b $bowlerName',
      WicketType.retiredHurt => 'retired hurt',
      WicketType.retired => 'retired out',
      null => 'out',
    };
  }

  String? dismissalSummary(Map<String, String> namesById) {
    if (!isWicket) return null;
    final whoId = dismissedBatterId ?? strikerId;
    final who = namesById[whoId] ?? 'Batter';
    return '$who ${scorecardDismissalText(namesById) ?? 'out'}';
  }

  BallEvent copyWith({
    String? strikerId,
    String? nonStrikerId,
    String? bowlerId,
    int? runsOffBat,
    ExtraType? extraType,
    int? extraRuns,
    bool? isWicket,
    WicketType? wicketType,
    String? dismissedBatterId,
    String? fielderId,
    String? nextBatterId,
    bool? synced,
    bool? voided,
  }) {
    return BallEvent(
      id: id,
      matchId: matchId,
      inningsNumber: inningsNumber,
      sequenceNumber: sequenceNumber,
      strikerId: strikerId ?? this.strikerId,
      nonStrikerId: nonStrikerId ?? this.nonStrikerId,
      bowlerId: bowlerId ?? this.bowlerId,
      runsOffBat: runsOffBat ?? this.runsOffBat,
      extraType: extraType ?? this.extraType,
      extraRuns: extraRuns ?? this.extraRuns,
      isWicket: isWicket ?? this.isWicket,
      wicketType: wicketType ?? this.wicketType,
      dismissedBatterId: dismissedBatterId ?? this.dismissedBatterId,
      fielderId: fielderId ?? this.fielderId,
      nextBatterId: nextBatterId ?? this.nextBatterId,
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
        'striker_id': strikerId,
        'non_striker_id': nonStrikerId,
        'bowler_id': bowlerId,
        'runs_off_bat': runsOffBat,
        'extra_type': extraType.name,
        'extra_runs': extraRuns,
        'is_wicket': isWicket ? 1 : 0,
        'wicket_type': wicketType?.name,
        'dismissed_batter_id': dismissedBatterId,
        'fielder_id': fielderId,
        'next_batter_id': nextBatterId,
        'synced': synced ? 1 : 0,
        'voided': voided ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static bool _decodeBool(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    return false;
  }

  static String? _cleanNullableId(Object? raw) {
    final s = (raw as String?)?.trim();
    return (s != null && s.isNotEmpty) ? s : null;
  }

  static BallEvent fromMap(Map<String, Object?> map) => BallEvent(
        id: map['id']! as String,
        matchId: map['match_id']! as String,
        inningsNumber: (map['innings_number']! as num).toInt(),
        sequenceNumber: (map['sequence_number']! as num).toInt(),
        strikerId: map['striker_id']! as String,
        nonStrikerId: map['non_striker_id']! as String,
        bowlerId: map['bowler_id']! as String,
        runsOffBat: ((map['runs_off_bat'] as num?) ?? 0).toInt(),
        extraType: ExtraType.fromName((map['extra_type'] as String?) ?? 'none'),
        extraRuns: ((map['extra_runs'] as num?) ?? 0).toInt(),
        isWicket: _decodeBool(map['is_wicket']),
        wicketType: WicketType.fromNullableName(map['wicket_type'] as String?),
        dismissedBatterId: _cleanNullableId(map['dismissed_batter_id']),
        fielderId: _cleanNullableId(map['fielder_id']),
        nextBatterId: _cleanNullableId(map['next_batter_id']),
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
    required this.playerId,
    required this.name,
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
    required this.isOut,
    this.dismissalText,
  });

  final String playerId;
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
    required this.playerId,
    required this.name,
    required this.legalBalls,
    required this.maidens,
    required this.runsConceded,
    required this.wickets,
  });

  final String playerId;
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
    required this.bowlerId,
    required this.bowler,
    required this.balls,
    required this.runsInOver,
    required this.wicketsInOver,
    required this.legalBallsInOver,
  });

  final int overNumber;
  final String bowlerId;
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
    required this.batterId,
    required this.batterName,
  });

  final int wicketNumber;
  final int runsAtFall;
  final String oversAtFall;
  final String batterId;
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
    required this.strikerId,
    required this.nonStrikerId,
    required this.currentBowlerId,
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
  final String strikerId;
  final String nonStrikerId;
  final String currentBowlerId;
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
      !isComplete && (strikerId.isEmpty || nonStrikerId.isEmpty);
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

  BatterLine batterById(String id, {String fallbackName = ''}) =>
      batters.firstWhere(
        (b) => b.playerId == id,
        orElse: () => BatterLine(
          playerId: id,
          name: fallbackName,
          runs: 0,
          balls: 0,
          fours: 0,
          sixes: 0,
          isOut: false,
        ),
      );

  BatterLine batterByName(String name) => batters.firstWhere(
        (b) => b.name == name,
        orElse: () => BatterLine(
          playerId: '',
          name: name,
          runs: 0,
          balls: 0,
          fours: 0,
          sixes: 0,
          isOut: false,
        ),
      );

  BowlerLine bowlerById(String id, {String fallbackName = ''}) =>
      bowlers.firstWhere(
        (b) => b.playerId == id,
        orElse: () => BowlerLine(
          playerId: id,
          name: fallbackName,
          legalBalls: 0,
          maidens: 0,
          runsConceded: 0,
          wickets: 0,
        ),
      );

  BowlerLine bowlerByName(String name) => bowlers.firstWhere(
        (b) => b.name == name,
        orElse: () => BowlerLine(
          playerId: '',
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
    this.resolvedPlayerNames = const {},
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

  /// Combined map (`config.adHocPlayers` overridden by `players.display_name`)
  /// used when deriving this match state.
  final Map<String, String> resolvedPlayerNames;

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
