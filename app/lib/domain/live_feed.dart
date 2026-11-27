import 'package:flutter/foundation.dart';

import 'models.dart';
import 'tournament_engine.dart';

/// Compact server-projected live/recent match card returned by `get_live_feed`.
/// Stays strictly in memory so spectators never pollute local SQLite.
@immutable
class LiveFeedMatch {
  const LiveFeedMatch({
    required this.id,
    required this.teamA,
    required this.teamB,
    this.teamAId,
    this.teamBId,
    this.teamALogoUrl,
    this.teamBLogoUrl,
    required this.formatLabel,
    required this.oversLimit,
    required this.isTestMatch,
    this.tournamentId,
    this.tournamentName,
    this.venue,
    required this.status,
    required this.activeInnings,
    required this.battingSide,
    required this.inn1BattingSide,
    required this.inn1Runs,
    required this.inn1Wickets,
    required this.inn1Overs,
    required this.inn2Started,
    this.inn2BattingSide,
    required this.inn2Runs,
    required this.inn2Wickets,
    required this.inn2Overs,
    this.statusLine,
    this.lastBallLabel,
    this.lastBallKind = 'normal',
    required this.ballsCount,
    required this.lastEventAt,
  });

  final String id;
  final String teamA;
  final String teamB;
  final String? teamAId;
  final String? teamBId;
  final String? teamALogoUrl;
  final String? teamBLogoUrl;
  final String formatLabel;
  final int oversLimit;
  final bool isTestMatch;
  final String? tournamentId;
  final String? tournamentName;
  final String? venue;
  final String status; // live | inningsBreak | completed | abandoned
  final int activeInnings;
  final MatchSide battingSide;
  final MatchSide inn1BattingSide;
  final int inn1Runs;
  final int inn1Wickets;
  final String inn1Overs;
  final bool inn2Started;
  final MatchSide? inn2BattingSide;
  final int inn2Runs;
  final int inn2Wickets;
  final String inn2Overs;
  final String? statusLine;
  final String? lastBallLabel;
  final String lastBallKind; // normal | boundary | wicket | extra
  final int ballsCount;
  final DateTime lastEventAt;

  bool get isLive => status == 'live';
  bool get isInningsBreak => status == 'inningsBreak';
  bool get isCompleted => status == 'completed' || status == 'abandoned';

  String get inn1TeamName => inn1BattingSide == MatchSide.a ? teamA : teamB;
  String get inn2TeamName => inn1BattingSide == MatchSide.a ? teamB : teamA;
  String? get inn1TeamId => inn1BattingSide == MatchSide.a ? teamAId : teamBId;
  String? get inn2TeamId => inn1BattingSide == MatchSide.a ? teamBId : teamAId;
  String? get inn1LogoUrl =>
      inn1BattingSide == MatchSide.a ? teamALogoUrl : teamBLogoUrl;
  String? get inn2LogoUrl =>
      inn1BattingSide == MatchSide.a ? teamBLogoUrl : teamALogoUrl;

  String get inn1ScoreText => '$inn1Runs/$inn1Wickets';
  String get inn2ScoreText => '$inn2Runs/$inn2Wickets';

  MatchSide get resolvedInn2Side =>
      inn2BattingSide ??
      (inn1BattingSide == MatchSide.a ? MatchSide.b : MatchSide.a);

  static String? _cleanString(Object? raw) {
    final s = (raw as String?)?.trim();
    return (s != null && s.isNotEmpty) ? s : null;
  }

  static LiveFeedMatch fromMap(Map<String, Object?> map) {
    final inn1Side = MatchSide.fromName(map['inn1_batting_side'] as String?);
    final rawInn2Side = map['inn2_batting_side'] as String?;
    return LiveFeedMatch(
      id: (map['id'] ?? '').toString(),
      teamA: (map['team_a'] ?? 'Team A').toString(),
      teamB: (map['team_b'] ?? 'Team B').toString(),
      teamAId: _cleanString(map['team_a_id']),
      teamBId: _cleanString(map['team_b_id']),
      teamALogoUrl: _cleanString(map['team_a_logo_url']),
      teamBLogoUrl: _cleanString(map['team_b_logo_url']),
      formatLabel: (map['format_label'] ?? 'T20').toString(),
      oversLimit: ((map['overs_limit'] as num?) ?? 20).toInt(),
      isTestMatch: map['is_test_match'] == true,
      tournamentId: _cleanString(map['tournament_id']),
      tournamentName: _cleanString(map['tournament_name']),
      venue: _cleanString(map['venue']),
      status: (map['status'] ?? 'live').toString(),
      activeInnings: ((map['active_innings'] as num?) ?? 1).toInt(),
      battingSide: MatchSide.fromName(map['batting_side'] as String?),
      inn1BattingSide: inn1Side,
      inn1Runs: ((map['inn1_runs'] as num?) ?? 0).toInt(),
      inn1Wickets: ((map['inn1_wickets'] as num?) ?? 0).toInt(),
      inn1Overs: (map['inn1_overs'] ?? '0.0').toString(),
      inn2Started: map['inn2_started'] == true,
      inn2BattingSide:
          rawInn2Side != null ? MatchSide.fromName(rawInn2Side) : null,
      inn2Runs: ((map['inn2_runs'] as num?) ?? 0).toInt(),
      inn2Wickets: ((map['inn2_wickets'] as num?) ?? 0).toInt(),
      inn2Overs: (map['inn2_overs'] ?? '0.0').toString(),
      statusLine: _cleanString(map['status_line']),
      lastBallLabel: _cleanString(map['last_ball_label']),
      lastBallKind: (map['last_ball_kind'] ?? 'normal').toString(),
      ballsCount: ((map['balls_count'] as num?) ?? 0).toInt(),
      lastEventAt: DateTime.fromMillisecondsSinceEpoch(
        ((map['last_event_at'] as num?) ??
                DateTime.now().millisecondsSinceEpoch)
            .toInt(),
      ),
    );
  }
}

/// Public tournament card returned by `get_live_feed`.
@immutable
class LiveFeedTournament {
  const LiveFeedTournament({
    required this.id,
    required this.name,
    this.location,
    required this.formatLabel,
    required this.structure,
    this.startDate,
    this.endDate,
    required this.teamCount,
    required this.liveMatchCount,
    required this.completedMatchCount,
    required this.latestActivity,
  });

  final String id;
  final String name;
  final String? location;
  final String formatLabel;
  final TournamentStructure structure;
  final DateTime? startDate;
  final DateTime? endDate;
  final int teamCount;
  final int liveMatchCount;
  final int completedMatchCount;
  final DateTime latestActivity;

  bool get hasLiveMatches => liveMatchCount > 0;

  String? get dateRangeLabel {
    if (startDate != null && endDate != null) {
      if (startDate!.year == endDate!.year &&
          startDate!.month == endDate!.month &&
          startDate!.day == endDate!.day) {
        return Tournament.formatShortDate(startDate!);
      }
      return '${Tournament.formatShortDate(startDate!)} – ${Tournament.formatShortDate(endDate!)}';
    }
    if (startDate != null) return 'Starts ${Tournament.formatShortDate(startDate!)}';
    if (endDate != null) return 'Ends ${Tournament.formatShortDate(endDate!)}';
    return null;
  }

  static LiveFeedTournament fromMap(Map<String, Object?> map) {
    final rawLoc = (map['location'] as String?)?.trim();
    final rawStart = map['start_date'] as num?;
    final rawEnd = map['end_date'] as num?;
    return LiveFeedTournament(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? 'Tournament').toString(),
      location: (rawLoc != null && rawLoc.isNotEmpty) ? rawLoc : null,
      formatLabel: (map['format_label'] ?? 'T20').toString(),
      structure: TournamentStructure.fromName(map['structure'] as String?),
      startDate: rawStart != null
          ? DateTime.fromMillisecondsSinceEpoch(rawStart.toInt())
          : null,
      endDate: rawEnd != null
          ? DateTime.fromMillisecondsSinceEpoch(rawEnd.toInt())
          : null,
      teamCount: ((map['team_count'] as num?) ?? 0).toInt(),
      liveMatchCount: ((map['live_match_count'] as num?) ?? 0).toInt(),
      completedMatchCount: ((map['completed_match_count'] as num?) ?? 0).toInt(),
      latestActivity: DateTime.fromMillisecondsSinceEpoch(
        ((map['latest_activity'] as num?) ??
                DateTime.now().millisecondsSinceEpoch)
            .toInt(),
      ),
    );
  }
}

/// Complete snapshot returned in one round-trip by `get_live_feed`.
@immutable
class LiveFeedSnapshot {
  const LiveFeedSnapshot({
    required this.serverNow,
    required this.fetchedAt,
    required this.liveMatches,
    required this.recentMatches,
    required this.tournaments,
  });

  final DateTime serverNow;
  final DateTime fetchedAt;
  final List<LiveFeedMatch> liveMatches;
  final List<LiveFeedMatch> recentMatches;
  final List<LiveFeedTournament> tournaments;

  bool get isEmpty =>
      liveMatches.isEmpty && recentMatches.isEmpty && tournaments.isEmpty;

  static LiveFeedSnapshot fromMap(Map<String, dynamic> map) {
    final serverNowMs =
        ((map['server_now_ms'] as num?) ?? DateTime.now().millisecondsSinceEpoch)
            .toInt();
    final rawLive = (map['live_matches'] as List?) ?? const [];
    final rawRecent = (map['recent_matches'] as List?) ?? const [];
    final rawTournaments = (map['tournaments'] as List?) ?? const [];
    return LiveFeedSnapshot(
      serverNow: DateTime.fromMillisecondsSinceEpoch(serverNowMs),
      fetchedAt: DateTime.now(),
      liveMatches: [
        for (final r in rawLive)
          if (r is Map) LiveFeedMatch.fromMap(Map<String, Object?>.from(r)),
      ],
      recentMatches: [
        for (final r in rawRecent)
          if (r is Map) LiveFeedMatch.fromMap(Map<String, Object?>.from(r)),
      ],
      tournaments: [
        for (final r in rawTournaments)
          if (r is Map)
            LiveFeedTournament.fromMap(Map<String, Object?>.from(r)),
      ],
    );
  }
}
