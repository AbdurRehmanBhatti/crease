import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'models.dart';

@immutable
class Tournament {
  const Tournament({
    required this.id,
    required this.name,
    required this.oversLimit,
    this.playersPerSide = 11,
    required this.formatLabel,
    required this.teamRosters,
    this.pointsForWin = 2,
    this.pointsForTie = 1,
    this.synced = false,
    required this.createdAt,
  });

  final String id;
  final String name;
  final int oversLimit;
  final int playersPerSide;
  final String formatLabel;
  final Map<String, List<String>> teamRosters;
  final int pointsForWin;
  final int pointsForTie;
  final bool synced;
  final DateTime createdAt;

  List<String> get teams => teamRosters.keys.toList();

  Tournament copyWith({
    String? name,
    int? oversLimit,
    int? playersPerSide,
    String? formatLabel,
    Map<String, List<String>>? teamRosters,
    int? pointsForWin,
    int? pointsForTie,
    bool? synced,
  }) =>
      Tournament(
        id: id,
        name: name ?? this.name,
        oversLimit: oversLimit ?? this.oversLimit,
        playersPerSide: playersPerSide ?? this.playersPerSide,
        formatLabel: formatLabel ?? this.formatLabel,
        teamRosters: teamRosters ?? this.teamRosters,
        pointsForWin: pointsForWin ?? this.pointsForWin,
        pointsForTie: pointsForTie ?? this.pointsForTie,
        synced: synced ?? this.synced,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'overs_limit': oversLimit,
        'players_per_side': playersPerSide,
        'format_label': formatLabel,
        'team_rosters': jsonEncode(teamRosters),
        'points_for_win': pointsForWin,
        'points_for_tie': pointsForTie,
        'synced': synced ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static Map<String, List<String>> _decodeRosters(Object? raw) {
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          for (final entry in decoded.entries)
            entry.key.toString(): (entry.value is List)
                ? (entry.value as List).map((e) => e.toString()).toList()
                : <String>[],
        };
      }
    } catch (_) {}
    return const {};
  }

  static Tournament fromMap(Map<String, Object?> map) => Tournament(
        id: map['id']! as String,
        name: map['name']! as String,
        oversLimit: map['overs_limit']! as int,
        playersPerSide: (map['players_per_side'] as int?) ?? 11,
        formatLabel: map['format_label']! as String,
        teamRosters: _decodeRosters(map['team_rosters']),
        pointsForWin: (map['points_for_win'] as int?) ?? 2,
        pointsForTie: (map['points_for_tie'] as int?) ?? 1,
        synced: ((map['synced'] as int?) ?? 0) == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
      );
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

/// Deterministic Tournament Points Table & Net Run Rate (NRR) engine.
/// Always derives standings straight from completed [DerivedMatchState]s so
/// points and NRR can never fail to update or drift out of sync.
class TournamentEngine {
  TournamentEngine._();

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
