part of 'local_event_store.dart';

extension LocalEventStoreLiveFeed on LocalEventStore {
  // ── CQRS Live Summary Projection ──────────────────────────────────────────

  static ({String label, String kind})? describeLastBall(BallEvent? e) {
    if (e == null) return null;
    if (e.isWicket) {
      final total = e.runsOffBat + e.extraRuns;
      return (
        label: total > 0 ? 'W+$total' : 'W',
        kind: 'wicket',
      );
    }
    switch (e.extraType) {
      case ExtraType.wide:
        return (
          label: e.extraRuns > 1 ? '${e.extraRuns}WD' : 'WD',
          kind: 'extra',
        );
      case ExtraType.noBall:
        final total = e.runsOffBat + e.extraRuns;
        return (
          label: total > 1 ? '${total}NB' : 'NB',
          kind: 'extra',
        );
      case ExtraType.bye:
        return (label: '${e.extraRuns}B', kind: 'extra');
      case ExtraType.legBye:
        return (label: '${e.extraRuns}LB', kind: 'extra');
      case ExtraType.penalty:
        return (label: '+${e.extraRuns}', kind: 'extra');
      case ExtraType.none:
        final r = e.runsOffBat;
        return (
          label: '$r',
          kind: (r == 4 || r == 6) ? 'boundary' : 'normal',
        );
    }
  }

  /// Pure projection builder for `public.match_live_summary` derived strictly
  /// from `ball_events`.
  static Map<String, Object?> buildLiveSummaryPayload(
    MatchConfig cfg,
    List<BallEvent> evs,
    DerivedMatchState derived, {
    int? nowMs,
  }) {
    final activeBalls = evs.where((e) => !e.voided).toList();
    final lastBall = activeBalls.isNotEmpty ? activeBalls.last : null;
    final lastBallInfo = describeLastBall(lastBall);

    final inn1 = derived.innings1;
    final inn2 = derived.innings2;
    final inn2Started = inn2 != null &&
        (inn2.legalBalls > 0 ||
            inn2.isDeclared ||
            derived.activeInningsNumber >= 2);

    final statusStr = cfg.isAbandoned ? 'abandoned' : derived.status.name;

    String? statusLine;
    if (derived.resultSummary != null) {
      statusLine = derived.resultSummary;
    } else if (derived.leadTrailText != null) {
      statusLine = derived.leadTrailText;
    } else if (derived.activeInnings.runsNeeded != null &&
        derived.status == MatchStatus.live) {
      final rem = derived.activeInnings.ballsRemaining;
      statusLine =
          '${derived.activeInnings.battingTeam} need ${derived.activeInnings.runsNeeded} from $rem ball${rem == 1 ? '' : 's'}';
    } else if (derived.status == MatchStatus.inningsBreak) {
      statusLine = 'Innings break';
    } else if (derived.activeInnings.legalBalls > 0) {
      statusLine =
          'CRR ${derived.activeInnings.currentRunRate.toStringAsFixed(2)}';
    }

    final resolvedNowMs = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final lastEventMs = lastBall?.createdAt.millisecondsSinceEpoch ??
        cfg.createdAt.millisecondsSinceEpoch;

    return {
      'match_id': cfg.id,
      'status': statusStr,
      'active_innings': derived.activeInningsNumber,
      'batting_side': derived.activeInnings.battingSide.name,
      'inn1_batting_side': inn1.battingSide.name,
      'inn1_runs': inn1.totalRuns,
      'inn1_wickets': inn1.wickets,
      'inn1_overs': inn1.oversText,
      'inn2_started': inn2Started,
      'inn2_batting_side': inn2?.battingSide.name,
      'inn2_runs': inn2?.totalRuns ?? 0,
      'inn2_wickets': inn2?.wickets ?? 0,
      'inn2_overs': inn2?.oversText ?? '0.0',
      'status_line': statusLine,
      'last_ball_label': lastBallInfo?.label,
      'last_ball_kind': lastBallInfo?.kind ?? 'normal',
      'balls_count': activeBalls.length,
      'last_event_at': lastEventMs,
      'updated_at': resolvedNowMs,
    };
  }

  /// Upserts a lightweight ~200-byte summary row in `public.match_live_summary`
  /// derived strictly from `ball_events` so the public Live tab never scans
  /// ball-by-ball rows. Best-effort: silently skips if offline or unmigrated.
  Future<void> syncMatchLiveSummary(
    String matchId, {
    MatchConfig? config,
    List<BallEvent>? events,
  }) async {
    try {
      if (!isSignedInAccount) return;
      final cfg = config ?? await getMatch(matchId);
      if (cfg == null || cfg.isDemo) return;
      final evs = events ?? await getBallEvents(matchId);
      final derived = deriveMatch(cfg, evs);
      final payload = buildLiveSummaryPayload(cfg, evs, derived);

      await Supabase.instance.client.from('match_live_summary').upsert(
        payload,
        onConflict: 'match_id',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('syncMatchLiveSummary skipped: $e');
    }
  }

  // ── Visibility Controls (Unlisted by Default) ─────────────────────────────

  /// Updates match visibility locally and syncs to Supabase (including pending
  /// balls and live summary so going public takes effect immediately).
  Future<MatchConfig?> setMatchVisibility(
    String matchId,
    BroadcastVisibility visibility,
  ) async {
    final existing = await getMatch(matchId);
    if (existing == null) return null;
    final updated = existing.copyWith(visibility: visibility);
    await saveMatch(updated);
    if (isSignedInAccount && !updated.isDemo) {
      try {
        await ensureMatchSyncedToSupabase(matchId);
        await syncPendingToSupabase(matchId);
        await syncMatchLiveSummary(matchId, config: updated);
      } catch (e) {
        if (kDebugMode) debugPrint('setMatchVisibility cloud sync skipped: $e');
      }
    }
    return updated;
  }

  /// Updates tournament visibility locally and cascades to all matches in that
  /// tournament, both locally and atomically via `set_tournament_visibility`.
  Future<Tournament?> setTournamentVisibility(
    String tournamentId,
    BroadcastVisibility visibility,
  ) async {
    final existing = await getTournament(tournamentId);
    if (existing == null) return null;
    final updated = existing.copyWith(visibility: visibility);
    await saveTournament(updated);

    final db = await database;
    await db.update(
      'matches',
      {'visibility': visibility.name, 'synced': 0},
      where: 'tournament_id = ?',
      whereArgs: [tournamentId],
    );

    if (isSignedInAccount) {
      try {
        await syncTournamentToSupabase(tournamentId);
        await Supabase.instance.client.rpc(
          'set_tournament_visibility',
          params: {
            'p_tournament_id': tournamentId,
            'p_visibility': visibility.name,
          },
        );
        final tMatches = await listMatchesForTournament(tournamentId);
        for (final m in tMatches) {
          if (m.isDemo) continue;
          await syncPendingToSupabase(m.id);
          await syncMatchLiveSummary(m.id, config: m);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('setTournamentVisibility cloud sync skipped: $e');
        }
      }
    }
    return updated;
  }

  // ── Public Live Feed Queries (Anon + Authenticated, In-Memory Only) ───────

  Future<LiveFeedSnapshot?> fetchLiveFeed({
    int liveLimit = 30,
    int recentLimit = 20,
  }) async {
    try {
      final raw = await Supabase.instance.client.rpc(
        'get_live_feed',
        params: {
          'p_live_limit': liveLimit,
          'p_recent_limit': recentLimit,
        },
      );
      if (raw == null || raw is! Map) return null;
      return LiveFeedSnapshot.fromMap(Map<String, dynamic>.from(raw));
    } catch (e) {
      if (kDebugMode) debugPrint('fetchLiveFeed error: $e');
      return null;
    }
  }

  Future<int> fetchPublicLiveCount() async {
    try {
      final raw = await Supabase.instance.client.rpc('get_public_live_count');
      if (raw is num) return raw.toInt();
      return 0;
    } catch (_) {
      return 0;
    }
  }
}
