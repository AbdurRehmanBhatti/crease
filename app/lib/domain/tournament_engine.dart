import 'package:flutter/foundation.dart';

import 'models.dart';

enum TournamentStructure {
  leagueKnockout,
  knockout,
  open;

  String get label => switch (this) {
        TournamentStructure.leagueKnockout => 'League + Knockouts',
        TournamentStructure.knockout => 'Knockout',
        TournamentStructure.open => 'Open series',
      };

  String get shortLabel => switch (this) {
        TournamentStructure.leagueKnockout => 'League + KO',
        TournamentStructure.knockout => 'Knockout',
        TournamentStructure.open => 'Open',
      };

  static TournamentStructure fromName(String? value) {
    for (final s in TournamentStructure.values) {
      if (s.name == value) return s;
    }
    return TournamentStructure.open;
  }
}

enum MatchStage {
  league,
  quarterFinal,
  semiFinal,
  finalMatch;

  String get label => switch (this) {
        MatchStage.league => 'League',
        MatchStage.quarterFinal => 'Quarter-Final',
        MatchStage.semiFinal => 'Semi-Final',
        MatchStage.finalMatch => 'Final',
      };

  bool get countsInStandings => this == MatchStage.league;

  static MatchStage fromName(String? value) {
    for (final s in MatchStage.values) {
      if (s.name == value) return s;
    }
    return MatchStage.league;
  }
}

/// Normalized join row (`public.tournament_teams` / SQLite `tournament_teams`).
@immutable
class TournamentTeamEntry {
  const TournamentTeamEntry({
    required this.id,
    required this.tournamentId,
    this.teamId,
    this.adHocName,
    this.resolvedTeamName,
    this.seedOrder = 0,
    required this.createdAt,
  });

  final String id;
  final String tournamentId;
  final String? teamId;
  final String? adHocName;

  /// Live club name resolved from `teams` when [teamId] is non-null.
  final String? resolvedTeamName;
  final int seedOrder;
  final DateTime createdAt;

  String get displayName {
    final resolved = resolvedTeamName?.trim();
    if (resolved != null && resolved.isNotEmpty) return resolved;
    final adHoc = adHocName?.trim();
    if (adHoc != null && adHoc.isNotEmpty) return adHoc;
    return 'Team';
  }

  TournamentTeamEntry copyWith({
    String? teamId,
    String? adHocName,
    String? resolvedTeamName,
    int? seedOrder,
  }) =>
      TournamentTeamEntry(
        id: id,
        tournamentId: tournamentId,
        teamId: teamId ?? this.teamId,
        adHocName: adHocName ?? this.adHocName,
        resolvedTeamName: resolvedTeamName ?? this.resolvedTeamName,
        seedOrder: seedOrder ?? this.seedOrder,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'tournament_id': tournamentId,
        'team_id': teamId,
        'ad_hoc_name': adHocName,
        'seed_order': seedOrder,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static TournamentTeamEntry fromMap(
    Map<String, Object?> map, {
    Map<String, String> teamNamesById = const {},
  }) {
    final tid = (map['team_id'] as String?)?.trim();
    final cleanTid = (tid != null && tid.isNotEmpty) ? tid : null;
    final rawAdHoc = (map['ad_hoc_name'] as String?)?.trim();
    final rawName = (map['name'] as String?)?.trim();
    return TournamentTeamEntry(
      id: map['id']! as String,
      tournamentId: (map['tournament_id'] as String?) ?? '',
      teamId: cleanTid,
      adHocName: (rawAdHoc != null && rawAdHoc.isNotEmpty)
          ? rawAdHoc
          : (cleanTid == null ? rawName : null),
      resolvedTeamName: cleanTid != null
          ? (teamNamesById[cleanTid] ?? rawName)
          : rawName,
      seedOrder: ((map['seed_order'] as num?) ?? 0).toInt(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        ((map['created_at'] as num?) ?? DateTime.now().millisecondsSinceEpoch)
            .toInt(),
      ),
    );
  }
}

@immutable
class Tournament {
  const Tournament({
    required this.id,
    required this.name,
    this.location,
    this.startDate,
    this.endDate,
    required this.oversLimit,
    this.playersPerSide = 11,
    required this.formatLabel,
    this.entries = const [],
    this.pointsForWin = 2,
    this.pointsForTie = 1,
    this.structure = TournamentStructure.open,
    this.roundsPerPair = 1,
    this.knockoutQualifiers = 2,
    this.synced = false,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? location;
  final DateTime? startDate;
  final DateTime? endDate;
  final int oversLimit;
  final int playersPerSide;
  final String formatLabel;
  final List<TournamentTeamEntry> entries;
  final int pointsForWin;
  final int pointsForTie;
  final TournamentStructure structure;
  final int roundsPerPair; // 1 = single round-robin, 2 = double round-robin
  final int knockoutQualifiers; // 0 = league only, 2 = Final, 4 = Semi-Finals + Final
  final bool synced;
  final DateTime createdAt;

  List<String> get teams => entries.map((e) => e.displayName).toList();

  TournamentTeamEntry? entryForName(String teamName) {
    final lower = teamName.trim().toLowerCase();
    for (final e in entries) {
      if (e.displayName.trim().toLowerCase() == lower) return e;
    }
    return null;
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String formatShortDate(DateTime d) =>
      '${_months[d.month - 1]} ${d.day}';

  /// Compact human-readable schedule window (e.g. "Nov 24 – Dec 8" or "Starts Nov 24").
  String? get dateRangeLabel {
    if (startDate != null && endDate != null) {
      if (startDate!.year == endDate!.year &&
          startDate!.month == endDate!.month &&
          startDate!.day == endDate!.day) {
        return formatShortDate(startDate!);
      }
      return '${formatShortDate(startDate!)} – ${formatShortDate(endDate!)}';
    }
    if (startDate != null) return 'Starts ${formatShortDate(startDate!)}';
    if (endDate != null) return 'Ends ${formatShortDate(endDate!)}';
    return null;
  }

  Tournament copyWith({
    String? name,
    String? location,
    bool clearLocation = false,
    DateTime? startDate,
    bool clearStartDate = false,
    DateTime? endDate,
    bool clearEndDate = false,
    int? oversLimit,
    int? playersPerSide,
    String? formatLabel,
    List<TournamentTeamEntry>? entries,
    int? pointsForWin,
    int? pointsForTie,
    TournamentStructure? structure,
    int? roundsPerPair,
    int? knockoutQualifiers,
    bool? synced,
  }) =>
      Tournament(
        id: id,
        name: name ?? this.name,
        location: clearLocation ? null : (location ?? this.location),
        startDate: clearStartDate ? null : (startDate ?? this.startDate),
        endDate: clearEndDate ? null : (endDate ?? this.endDate),
        oversLimit: oversLimit ?? this.oversLimit,
        playersPerSide: playersPerSide ?? this.playersPerSide,
        formatLabel: formatLabel ?? this.formatLabel,
        entries: entries ?? this.entries,
        pointsForWin: pointsForWin ?? this.pointsForWin,
        pointsForTie: pointsForTie ?? this.pointsForTie,
        structure: structure ?? this.structure,
        roundsPerPair: roundsPerPair ?? this.roundsPerPair,
        knockoutQualifiers: knockoutQualifiers ?? this.knockoutQualifiers,
        synced: synced ?? this.synced,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'location': (location != null && location!.trim().isNotEmpty)
            ? location!.trim()
            : null,
        'start_date': startDate?.millisecondsSinceEpoch,
        'end_date': endDate?.millisecondsSinceEpoch,
        'overs_limit': oversLimit,
        'players_per_side': playersPerSide,
        'format_label': formatLabel,
        'points_for_win': pointsForWin,
        'points_for_tie': pointsForTie,
        'structure': structure.name,
        'rounds_per_pair': roundsPerPair,
        'knockout_qualifiers': knockoutQualifiers,
        'synced': synced ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static Tournament fromMap(
    Map<String, Object?> map, {
    List<TournamentTeamEntry> entries = const [],
  }) {
    final rawLoc = (map['location'] as String?)?.trim();
    final rawStart = map['start_date'] as num?;
    final rawEnd = map['end_date'] as num?;
    return Tournament(
      id: map['id']! as String,
      name: map['name']! as String,
      location: (rawLoc != null && rawLoc.isNotEmpty) ? rawLoc : null,
      startDate: rawStart != null
          ? DateTime.fromMillisecondsSinceEpoch(rawStart.toInt())
          : null,
      endDate: rawEnd != null
          ? DateTime.fromMillisecondsSinceEpoch(rawEnd.toInt())
          : null,
      oversLimit: (map['overs_limit']! as num).toInt(),
      playersPerSide: ((map['players_per_side'] as num?) ?? 11).toInt(),
      formatLabel: map['format_label']! as String,
      entries: entries,
      pointsForWin: ((map['points_for_win'] as num?) ?? 2).toInt(),
      pointsForTie: ((map['points_for_tie'] as num?) ?? 1).toInt(),
      structure: TournamentStructure.fromName(map['structure'] as String?),
      roundsPerPair: ((map['rounds_per_pair'] as num?) ?? 1).toInt(),
      knockoutQualifiers: ((map['knockout_qualifiers'] as num?) ?? 2).toInt(),
      synced: ((map['synced'] as num?) ?? 0) != 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at']! as num).toInt(),
      ),
    );
  }
}

@immutable
class PointsTableRow {
  const PointsTableRow({
    required this.teamName,
    required this.played,
    required this.won,
    required this.lost,
    required this.tied,
    required this.points,
    required this.nrr,
    required this.runsFor,
    required this.oversFor,
    required this.runsAgainst,
    required this.oversAgainst,
  });

  final String teamName;
  final int played;
  final int won;
  final int lost;
  final int tied;
  final int points;
  final double nrr;
  final int runsFor;
  final double oversFor;
  final int runsAgainst;
  final double oversAgainst;

  String get nrrText {
    final sign = nrr > 0.0005 ? '+' : '';
    return '$sign${nrr.toStringAsFixed(3)}';
  }
}

@immutable
class ScheduledFixture {
  const ScheduledFixture({
    required this.fixtureIndex,
    required this.stage,
    required this.label,
    required this.roundNumber,
    this.teamA,
    this.teamB,
    this.teamAPlaceholder,
    this.teamBPlaceholder,
    this.match,
    this.lockedReason,
  });

  final int fixtureIndex; // 1-based stable slot ID within tournament
  final MatchStage stage;
  final String label; // e.g. 'Match 1', 'Semi-Final 1', 'Final'
  final int roundNumber;
  final String? teamA;
  final String? teamB;
  final String? teamAPlaceholder; // e.g. '1st Place', 'Winner SF 1'
  final String? teamBPlaceholder;
  final DerivedMatchState? match;
  final String? lockedReason;

  String get displayTeamA => teamA ?? teamAPlaceholder ?? 'TBD';
  String get displayTeamB => teamB ?? teamBPlaceholder ?? 'TBD';

  bool get isCompleted => match?.status == MatchStatus.completed;
  bool get isLive => match != null && match!.status != MatchStatus.completed;
  bool get isReadyToStart =>
      match == null && teamA != null && teamB != null && lockedReason == null;
}

@immutable
class TournamentOverview {
  const TournamentOverview({
    required this.standings,
    required this.leagueFixtures,
    required this.knockoutFixtures,
    required this.extraMatches,
    required this.completedLeagueCount,
    required this.totalLeagueCount,
    required this.completedTotalCount,
    required this.totalPlannedMatches,
    required this.leagueComplete,
    required this.knockoutsUnlocked,
    required this.qualifiersCount,
    this.champion,
  });

  final List<PointsTableRow> standings;
  final List<ScheduledFixture> leagueFixtures;
  final List<ScheduledFixture> knockoutFixtures;
  final List<DerivedMatchState> extraMatches;
  final int completedLeagueCount;
  final int totalLeagueCount;
  final int completedTotalCount;
  final int totalPlannedMatches;
  final bool leagueComplete;
  final bool knockoutsUnlocked;
  final int qualifiersCount;
  final String? champion;

  List<ScheduledFixture> get allFixtures => [
        ...leagueFixtures,
        ...knockoutFixtures,
      ];
}

/// Deterministic Tournament Engine:
/// - Derives Points Table & ICC NRR strictly from completed League matches.
/// - Generates balanced Round-Robin schedules via the Circle Method (Berger rounds).
/// - Automatically seeds Knockouts (#1v#4, #2v#3 -> Final; or #1v#2 -> Final)
///   and pure Knockout brackets, advancing winners and crowning the Champion.
class TournamentEngine {
  TournamentEngine._();

  /// Computes total planned matches for preview during tournament creation.
  static ({int league, int knockout, int total}) plannedMatchCounts({
    required int teamCount,
    required TournamentStructure structure,
    int roundsPerPair = 1,
    int knockoutQualifiers = 2,
  }) {
    if (teamCount < 2) return (league: 0, knockout: 0, total: 0);
    if (structure == TournamentStructure.open) {
      return (league: 0, knockout: 0, total: 0);
    }
    if (structure == TournamentStructure.knockout) {
      final ko = teamCount - 1;
      return (league: 0, knockout: ko, total: ko);
    }
    final league = (teamCount * (teamCount - 1) ~/ 2) * roundsPerPair.clamp(1, 2);
    final effectiveQualifiers = _effectiveQualifiers(teamCount, knockoutQualifiers);
    final ko = switch (effectiveQualifiers) {
      4 => 3, // 2 Semi-Finals + Final
      2 => 1, // Final
      _ => 0,
    };
    return (league: league, knockout: ko, total: league + ko);
  }

  static int _effectiveQualifiers(int teamCount, int requested) {
    if (requested <= 0 || teamCount < 2) return 0;
    if (requested >= 4 && teamCount >= 4) return 4;
    return 2;
  }

  /// Returns the winning team name for a completed non-tied, non-abandoned match.
  static String? winnerOf(DerivedMatchState match) {
    if (match.status != MatchStatus.completed || match.config.isAbandoned) {
      return null;
    }
    final inn1 = match.innings1;
    final inn2 = match.innings2;
    if (inn2 == null) return null;

    final target = inn2.target ?? (inn1.totalRuns + 1);
    final firstInningsScore = target - 1;
    if (inn2.totalRuns >= target) return inn2.battingTeam;
    if (inn2.totalRuns == firstInningsScore) return null;
    return inn1.battingTeam;
  }

  /// Resolves the advancing team for a completed knockout match.
  /// If a knockout ends in a tie or washout (no outright winner), the higher
  /// seed ([higherSeedFallback]) advances per standard ICC tournament rules so
  /// the bracket never deadlocks.
  static String? knockoutWinnerOf(
    DerivedMatchState match, {
    String? higherSeedFallback,
  }) {
    if (match.status != MatchStatus.completed) return null;
    final outright = winnerOf(match);
    if (outright != null) return outright;
    return higherSeedFallback ?? match.config.teamA;
  }

  /// Generates a balanced Round-Robin fixture list using the Circle Method so
  /// teams don't play consecutive back-to-back matches when avoidable.
  static List<({int round, String teamA, String teamB})> generateRoundRobinPairs(
    List<String> teams, {
    int roundsPerPair = 1,
  }) {
    if (teams.length < 2) return const [];
    final list = List<String>.from(teams);
    final hasBye = list.length.isOdd;
    if (hasBye) list.add('__BYE__');

    final n = list.length;
    final half = n ~/ 2;
    final singleCycle = <({int round, String teamA, String teamB})>[];
    final rot = List<String>.from(list);

    for (var r = 0; r < n - 1; r++) {
      for (var i = 0; i < half; i++) {
        final a = rot[i];
        final b = rot[n - 1 - i];
        if (a == '__BYE__' || b == '__BYE__') continue;
        // Alternate home/first-listed order across rounds for balance
        final swap = r.isOdd && i == 0;
        singleCycle.add((
          round: r + 1,
          teamA: swap ? b : a,
          teamB: swap ? a : b,
        ));
      }
      // Rotate all elements except index 0 clockwise
      final last = rot.removeLast();
      rot.insert(1, last);
    }

    if (roundsPerPair <= 1) return singleCycle;

    final totalRoundsPerCycle = n - 1;
    final doubleCycle = List<({int round, String teamA, String teamB})>.from(
      singleCycle,
    );
    for (final p in singleCycle) {
      doubleCycle.add((
        round: p.round + totalRoundsPerCycle,
        teamA: p.teamB,
        teamB: p.teamA,
      ));
    }
    return doubleCycle;
  }

  static List<PointsTableRow> deriveStandings(
    Tournament tournament,
    List<DerivedMatchState> matches,
  ) {
    final acc = <String, _TeamAcc>{
      for (final team in tournament.teams) team: _TeamAcc(team),
    };

    _TeamAcc ensureTeam(String name) =>
        acc.putIfAbsent(name, () => _TeamAcc(name));

    for (final match in matches) {
      if (match.status != MatchStatus.completed) continue;
      // Knockout matches (QF / SF / Final) never distort league standings or NRR.
      final stage = MatchStage.fromName(match.config.tournamentStage);
      if (!stage.countsInStandings) continue;

      if (match.config.isAbandoned) {
        final t1 = ensureTeam(match.config.teamA);
        final t2 = ensureTeam(match.config.teamB);
        t1.played += 1;
        t2.played += 1;
        t1.tied += 1;
        t2.tied += 1;
        t1.points += tournament.pointsForTie;
        t2.points += tournament.pointsForTie;
        continue;
      }
      final inn1 = match.innings1;
      final inn2 = match.innings2;
      if (inn2 == null) continue;

      final t1 = ensureTeam(inn1.battingTeam);
      final t2 = ensureTeam(inn2.battingTeam);

      t1.played += 1;
      t2.played += 1;

      final maxWickets = (match.config.playersPerSide - 1).clamp(1, 10);

      // ICC NRR rule: if a team is all out, its overs faced count as the full oversLimit.
      final overs1 = inn1.wickets >= maxWickets
          ? inn1.oversLimit.toDouble()
          : inn1.legalBalls / 6.0;
      final overs2 = inn2.wickets >= maxWickets
          ? inn2.oversLimit.toDouble()
          : inn2.legalBalls / 6.0;

      t1.runsFor += inn1.totalRuns;
      t1.oversFor += overs1;
      t1.runsAgainst += inn2.totalRuns;
      t1.oversAgainst += overs2;

      t2.runsFor += inn2.totalRuns;
      t2.oversFor += overs2;
      t2.runsAgainst += inn1.totalRuns;
      t2.oversAgainst += overs1;

      final target = inn2.target ?? (inn1.totalRuns + 1);
      final firstInningsScore = target - 1;

      if (inn2.totalRuns >= target) {
        t2.won += 1;
        t2.points += tournament.pointsForWin;
        t1.lost += 1;
      } else if (inn2.totalRuns == firstInningsScore) {
        t1.tied += 1;
        t2.tied += 1;
        t1.points += tournament.pointsForTie;
        t2.points += tournament.pointsForTie;
      } else {
        t1.won += 1;
        t1.points += tournament.pointsForWin;
        t2.lost += 1;
      }
    }

    final rows = acc.values.map((t) => t.toRow()).toList()
      ..sort((a, b) {
        final ptsCmp = b.points.compareTo(a.points);
        if (ptsCmp != 0) return ptsCmp;
        final nrrCmp = b.nrr.compareTo(a.nrr);
        if (nrrCmp != 0) return nrrCmp;
        final winCmp = b.won.compareTo(a.won);
        if (winCmp != 0) return winCmp;
        return a.teamName.toLowerCase().compareTo(b.teamName.toLowerCase());
      });

    return rows;
  }

  /// Derives the complete tournament state: standings, scheduled fixtures,
  /// auto-seeded knockout bracket, and champion.
  static TournamentOverview deriveOverview(
    Tournament tournament,
    List<DerivedMatchState> matches, {
    bool forceUnlockKnockouts = false,
  }) {
    final standings = deriveStandings(tournament, matches);
    final teams = tournament.teams;

    if (tournament.structure == TournamentStructure.open || teams.length < 2) {
      final finalMatches = matches
          .where(
            (m) =>
                MatchStage.fromName(m.config.tournamentStage) ==
                MatchStage.finalMatch,
          )
          .toList();
      final champion =
          finalMatches.isNotEmpty ? winnerOf(finalMatches.first) : null;
      return TournamentOverview(
        standings: standings,
        leagueFixtures: const [],
        knockoutFixtures: const [],
        extraMatches: matches,
        completedLeagueCount: matches
            .where(
              (m) =>
                  m.status == MatchStatus.completed &&
                  MatchStage.fromName(m.config.tournamentStage)
                      .countsInStandings,
            )
            .length,
        totalLeagueCount: 0,
        completedTotalCount:
            matches.where((m) => m.status == MatchStatus.completed).length,
        totalPlannedMatches: 0,
        leagueComplete: false,
        knockoutsUnlocked: true,
        qualifiersCount: _effectiveQualifiers(
          teams.length,
          tournament.knockoutQualifiers,
        ),
        champion: champion,
      );
    }

    // Track matches claimed by a scheduled fixture slot
    final usedMatchIds = <String>{};
    final orderedMatches = List<DerivedMatchState>.from(matches)
      ..sort((a, b) => a.config.createdAt.compareTo(b.config.createdAt));

    DerivedMatchState? claimMatch({
      required int fixtureIndex,
      required MatchStage stage,
      String? teamA,
      String? teamB,
    }) {
      // 1. Exact fixtureIndex match first
      for (final m in orderedMatches) {
        if (usedMatchIds.contains(m.config.id)) continue;
        if (m.config.fixtureIndex == fixtureIndex) {
          usedMatchIds.add(m.config.id);
          return m;
        }
      }
      // 2. Fallback: stage + unordered team pair match (legacy / manual starts)
      if (teamA != null && teamB != null) {
        final aLow = teamA.toLowerCase();
        final bLow = teamB.toLowerCase();
        for (final m in orderedMatches) {
          if (usedMatchIds.contains(m.config.id)) continue;
          if (MatchStage.fromName(m.config.tournamentStage) != stage) continue;
          final mA = m.config.teamA.toLowerCase();
          final mB = m.config.teamB.toLowerCase();
          if ((mA == aLow && mB == bLow) || (mA == bLow && mB == aLow)) {
            usedMatchIds.add(m.config.id);
            return m;
          }
        }
      }
      return null;
    }

    if (tournament.structure == TournamentStructure.knockout) {
      return _derivePureKnockout(
        tournament: tournament,
        standings: standings,
        orderedMatches: orderedMatches,
        usedMatchIds: usedMatchIds,
        claimMatch: claimMatch,
      );
    }

    // League + Knockouts
    final pairs = generateRoundRobinPairs(
      teams,
      roundsPerPair: tournament.roundsPerPair,
    );
    final leagueFixtures = <ScheduledFixture>[];
    var completedLeague = 0;

    for (var i = 0; i < pairs.length; i++) {
      final slot = i + 1;
      final pair = pairs[i];
      final match = claimMatch(
        fixtureIndex: slot,
        stage: MatchStage.league,
        teamA: pair.teamA,
        teamB: pair.teamB,
      );
      if (match?.status == MatchStatus.completed) {
        completedLeague++;
      }
      leagueFixtures.add(
        ScheduledFixture(
          fixtureIndex: slot,
          stage: MatchStage.league,
          label: 'Match $slot',
          roundNumber: pair.round,
          teamA: pair.teamA,
          teamB: pair.teamB,
          match: match,
        ),
      );
    }

    final leagueComplete =
        leagueFixtures.isNotEmpty && completedLeague >= leagueFixtures.length;
    final hasAnyKnockoutStarted = orderedMatches.any(
      (m) => !MatchStage.fromName(m.config.tournamentStage).countsInStandings,
    );
    final knockoutsUnlocked =
        leagueComplete || forceUnlockKnockouts || hasAnyKnockoutStarted;

    final qualifiers = _effectiveQualifiers(
      teams.length,
      tournament.knockoutQualifiers,
    );
    final knockoutFixtures = <ScheduledFixture>[];
    var nextSlot = leagueFixtures.length + 1;
    String? champion;

    if (qualifiers == 4 && standings.length >= 4) {
      final seed1 = standings[0].teamName;
      final seed2 = standings[1].teamName;
      final seed3 = standings[2].teamName;
      final seed4 = standings[3].teamName;

      final sf1Slot = nextSlot++;
      final sf2Slot = nextSlot++;
      final finalSlot = nextSlot++;

      final sf1Match = claimMatch(
        fixtureIndex: sf1Slot,
        stage: MatchStage.semiFinal,
        teamA: knockoutsUnlocked ? seed1 : null,
        teamB: knockoutsUnlocked ? seed4 : null,
      );
      final sf2Match = claimMatch(
        fixtureIndex: sf2Slot,
        stage: MatchStage.semiFinal,
        teamA: knockoutsUnlocked ? seed2 : null,
        teamB: knockoutsUnlocked ? seed3 : null,
      );

      final sf1Winner = sf1Match != null
          ? knockoutWinnerOf(sf1Match, higherSeedFallback: seed1)
          : null;
      final sf2Winner = sf2Match != null
          ? knockoutWinnerOf(sf2Match, higherSeedFallback: seed2)
          : null;

      final finalMatch = claimMatch(
        fixtureIndex: finalSlot,
        stage: MatchStage.finalMatch,
        teamA: sf1Winner,
        teamB: sf2Winner,
      );

      final lockMsg = knockoutsUnlocked
          ? null
          : 'Finish league stage ($completedLeague/${leagueFixtures.length})';

      knockoutFixtures.addAll([
        ScheduledFixture(
          fixtureIndex: sf1Slot,
          stage: MatchStage.semiFinal,
          label: 'Semi-Final 1',
          roundNumber: 100,
          teamA: sf1Match?.config.teamA ?? (knockoutsUnlocked ? seed1 : null),
          teamB: sf1Match?.config.teamB ?? (knockoutsUnlocked ? seed4 : null),
          teamAPlaceholder: '1st Place',
          teamBPlaceholder: '4th Place',
          match: sf1Match,
          lockedReason: sf1Match == null ? lockMsg : null,
        ),
        ScheduledFixture(
          fixtureIndex: sf2Slot,
          stage: MatchStage.semiFinal,
          label: 'Semi-Final 2',
          roundNumber: 100,
          teamA: sf2Match?.config.teamA ?? (knockoutsUnlocked ? seed2 : null),
          teamB: sf2Match?.config.teamB ?? (knockoutsUnlocked ? seed3 : null),
          teamAPlaceholder: '2nd Place',
          teamBPlaceholder: '3rd Place',
          match: sf2Match,
          lockedReason: sf2Match == null ? lockMsg : null,
        ),
        ScheduledFixture(
          fixtureIndex: finalSlot,
          stage: MatchStage.finalMatch,
          label: 'Final',
          roundNumber: 101,
          teamA: finalMatch?.config.teamA ?? sf1Winner,
          teamB: finalMatch?.config.teamB ?? sf2Winner,
          teamAPlaceholder: 'Winner SF 1',
          teamBPlaceholder: 'Winner SF 2',
          match: finalMatch,
          lockedReason: (finalMatch == null && (sf1Winner == null || sf2Winner == null))
              ? 'Waiting for Semi-Final winners'
              : null,
        ),
      ]);

      if (finalMatch != null) {
        champion = knockoutWinnerOf(
          finalMatch,
          higherSeedFallback: sf1Winner ?? finalMatch.config.teamA,
        );
      }
    } else if (qualifiers == 2 && standings.length >= 2) {
      final seed1 = standings[0].teamName;
      final seed2 = standings[1].teamName;
      final finalSlot = nextSlot++;
      final finalMatch = claimMatch(
        fixtureIndex: finalSlot,
        stage: MatchStage.finalMatch,
        teamA: knockoutsUnlocked ? seed1 : null,
        teamB: knockoutsUnlocked ? seed2 : null,
      );
      final lockMsg = knockoutsUnlocked
          ? null
          : 'Finish league stage ($completedLeague/${leagueFixtures.length})';

      knockoutFixtures.add(
        ScheduledFixture(
          fixtureIndex: finalSlot,
          stage: MatchStage.finalMatch,
          label: 'Final',
          roundNumber: 101,
          teamA: finalMatch?.config.teamA ?? (knockoutsUnlocked ? seed1 : null),
          teamB: finalMatch?.config.teamB ?? (knockoutsUnlocked ? seed2 : null),
          teamAPlaceholder: '1st Place',
          teamBPlaceholder: '2nd Place',
          match: finalMatch,
          lockedReason: finalMatch == null ? lockMsg : null,
        ),
      );
      if (finalMatch != null) {
        champion = knockoutWinnerOf(finalMatch, higherSeedFallback: seed1);
      }
    } else if (qualifiers == 0 && leagueComplete && standings.isNotEmpty) {
      champion = standings.first.teamName;
    }

    final extraMatches =
        orderedMatches.where((m) => !usedMatchIds.contains(m.config.id)).toList();
    final completedTotal =
        orderedMatches.where((m) => m.status == MatchStatus.completed).length;

    return TournamentOverview(
      standings: standings,
      leagueFixtures: leagueFixtures,
      knockoutFixtures: knockoutFixtures,
      extraMatches: extraMatches,
      completedLeagueCount: completedLeague,
      totalLeagueCount: leagueFixtures.length,
      completedTotalCount: completedTotal,
      totalPlannedMatches: leagueFixtures.length + knockoutFixtures.length,
      leagueComplete: leagueComplete,
      knockoutsUnlocked: knockoutsUnlocked,
      qualifiersCount: qualifiers,
      champion: champion,
    );
  }

  static TournamentOverview _derivePureKnockout({
    required Tournament tournament,
    required List<PointsTableRow> standings,
    required List<DerivedMatchState> orderedMatches,
    required Set<String> usedMatchIds,
    required DerivedMatchState? Function({
      required int fixtureIndex,
      required MatchStage stage,
      String? teamA,
      String? teamB,
    }) claimMatch,
  }) {
    final teams = tournament.teams;
    final knockoutFixtures = <ScheduledFixture>[];
    var slot = 1;
    var round = 1;

    // Bracket size is next power of 2 (2, 4, 8, 16)
    var bracketSize = 2;
    while (bracketSize < teams.length) {
      bracketSize *= 2;
    }

    // Standard seeding: top (bracketSize - teams.length) teams receive Round 1 byes
    final byeCount = bracketSize - teams.length;
    final currentSlots = <({String? team, String placeholder})>[];

    // Teams with byes advance directly; remaining teams pair in Round 1
    final round1MatchesCount = (teams.length - byeCount) ~/ 2;
    final round1Stage = switch (bracketSize) {
      2 => MatchStage.finalMatch,
      4 => MatchStage.semiFinal,
      8 => MatchStage.quarterFinal,
      _ => MatchStage.quarterFinal,
    };

    // Place bye teams first into the next round's slots
    for (var i = 0; i < byeCount; i++) {
      currentSlots.add((team: teams[i], placeholder: teams[i]));
    }

    // Build Round 1 matches for remaining teams
    for (var i = 0; i < round1MatchesCount; i++) {
      final a = teams[byeCount + i * 2];
      final b = teams[byeCount + i * 2 + 1];
      final fSlot = slot++;
      final m = claimMatch(
        fixtureIndex: fSlot,
        stage: round1Stage,
        teamA: a,
        teamB: b,
      );
      final label = round1Stage == MatchStage.finalMatch
          ? 'Final'
          : '${round1Stage.label} ${i + 1}';
      knockoutFixtures.add(
        ScheduledFixture(
          fixtureIndex: fSlot,
          stage: round1Stage,
          label: label,
          roundNumber: round,
          teamA: m?.config.teamA ?? a,
          teamB: m?.config.teamB ?? b,
          match: m,
        ),
      );
      final w = m != null ? knockoutWinnerOf(m, higherSeedFallback: a) : null;
      currentSlots.add((team: w, placeholder: 'Winner $label'));
    }

    String? champion;
    if (bracketSize == 2 && knockoutFixtures.isNotEmpty) {
      final f = knockoutFixtures.last;
      if (f.match != null) {
        champion = knockoutWinnerOf(f.match!, higherSeedFallback: f.teamA);
      }
    } else {
      // Progress subsequent rounds until 1 winner remains
      var advancers = currentSlots;
      while (advancers.length > 1) {
        round++;
        final nextAdvancers = <({String? team, String placeholder})>[];
        final matchCount = advancers.length ~/ 2;
        final stage = switch (matchCount) {
          1 => MatchStage.finalMatch,
          2 => MatchStage.semiFinal,
          _ => MatchStage.quarterFinal,
        };
        for (var i = 0; i < matchCount; i++) {
          final left = advancers[i * 2];
          final right = advancers[i * 2 + 1];
          final fSlot = slot++;
          final label = stage == MatchStage.finalMatch
              ? 'Final'
              : '${stage.label} ${i + 1}';
          final m = claimMatch(
            fixtureIndex: fSlot,
            stage: stage,
            teamA: left.team,
            teamB: right.team,
          );
          final ready = left.team != null && right.team != null;
          knockoutFixtures.add(
            ScheduledFixture(
              fixtureIndex: fSlot,
              stage: stage,
              label: label,
              roundNumber: round,
              teamA: m?.config.teamA ?? left.team,
              teamB: m?.config.teamB ?? right.team,
              teamAPlaceholder: left.placeholder,
              teamBPlaceholder: right.placeholder,
              match: m,
              lockedReason:
                  (m == null && !ready) ? 'Waiting for previous round' : null,
            ),
          );
          final w = m != null
              ? knockoutWinnerOf(m, higherSeedFallback: left.team)
              : null;
          if (stage == MatchStage.finalMatch) {
            champion = w;
          }
          nextAdvancers.add((team: w, placeholder: 'Winner $label'));
        }
        advancers = nextAdvancers;
      }
    }

    final extraMatches =
        orderedMatches.where((m) => !usedMatchIds.contains(m.config.id)).toList();
    final completedTotal =
        orderedMatches.where((m) => m.status == MatchStatus.completed).length;

    return TournamentOverview(
      standings: standings,
      leagueFixtures: const [],
      knockoutFixtures: knockoutFixtures,
      extraMatches: extraMatches,
      completedLeagueCount: 0,
      totalLeagueCount: 0,
      completedTotalCount: completedTotal,
      totalPlannedMatches: knockoutFixtures.length,
      leagueComplete: true,
      knockoutsUnlocked: true,
      qualifiersCount: 0,
      champion: champion,
    );
  }
}

class _TeamAcc {
  _TeamAcc(this.teamName);
  final String teamName;
  int played = 0;
  int won = 0;
  int lost = 0;
  int tied = 0;
  int points = 0;
  int runsFor = 0;
  double oversFor = 0.0;
  int runsAgainst = 0;
  double oversAgainst = 0.0;

  PointsTableRow toRow() {
    final forRate = oversFor > 0 ? runsFor / oversFor : 0.0;
    final againstRate = oversAgainst > 0 ? runsAgainst / oversAgainst : 0.0;
    final nrr = (oversFor == 0 && oversAgainst == 0) ? 0.0 : forRate - againstRate;
    return PointsTableRow(
      teamName: teamName,
      played: played,
      won: won,
      lost: lost,
      tied: tied,
      points: points,
      nrr: nrr,
      runsFor: runsFor,
      oversFor: oversFor,
      runsAgainst: runsAgainst,
      oversAgainst: oversAgainst,
    );
  }
}
