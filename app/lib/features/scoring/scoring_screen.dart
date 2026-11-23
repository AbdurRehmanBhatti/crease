import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../data/local_event_store.dart';
import '../../domain/cricket_engine.dart';
import '../../domain/models.dart';
import '../../theme/crease_theme.dart';
import '../scorecard/match_summary_poster.dart';
import '../scorecard/scorecard_screen.dart';
import 'scorer_handover_sheets.dart';
import 'sheets/match_options_sheets.dart';
import 'sheets/scoring_action_sheets.dart';
import 'widgets/live_crease_card.dart';
import 'widgets/scoring_header_widgets.dart';
import 'widgets/scoring_keypad_sheet.dart';

class ScoringScreen extends StatefulWidget {
  const ScoringScreen({super.key, required this.matchId});

  final String matchId;

  @override
  State<ScoringScreen> createState() => _ScoringScreenState();
}

class _ScoringScreenState extends State<ScoringScreen> {
  static const _uuid = Uuid();

  MatchConfig? _config;
  List<BallEvent> _events = [];
  bool _loading = true;

  int? _forcedInnings;
  String? _manualStriker;
  String? _manualNonStriker;
  String? _manualBowler;

  bool _handedOverToOther = false;
  bool _reclaiming = false;
  RealtimeChannel? _handoverChannel;

  @override
  void initState() {
    super.initState();
    _load();
    _initHandoverWatcher();
  }

  @override
  void dispose() {
    final ch = _handoverChannel;
    if (ch != null) {
      try {
        Supabase.instance.client.removeChannel(ch);
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _initHandoverWatcher() async {
    try {
      final client = Supabase.instance.client;
      final myUid = client.auth.currentUser?.id;
      final activeId =
          await LocalEventStore.instance.fetchActiveScorerId(widget.matchId);
      if (mounted &&
          activeId != null &&
          myUid != null &&
          activeId != myUid) {
        setState(() => _handedOverToOther = true);
        await LocalEventStore.instance.pullRemoteMatchToLocal(widget.matchId);
        await _load();
      }

      _handoverChannel = client
          .channel('scoring-baton-${widget.matchId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'matches',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: widget.matchId,
            ),
            callback: (payload) async {
              final nextActive =
                  payload.newRecord['active_scorer_id'] as String?;
              final currentUid = client.auth.currentUser?.id;
              if (nextActive == null || currentUid == null || !mounted) return;
              final otherHasBaton = nextActive != currentUid;
              if (otherHasBaton != _handedOverToOther) {
                setState(() => _handedOverToOther = otherHasBaton);
              }
              if (otherHasBaton) {
                await LocalEventStore.instance
                    .pullRemoteMatchToLocal(widget.matchId);
                await _load();
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'ball_events',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'match_id',
              value: widget.matchId,
            ),
            callback: (_) async {
              if (!_handedOverToOther || !mounted) return;
              await LocalEventStore.instance
                  .pullRemoteMatchToLocal(widget.matchId);
              await _load();
            },
          )
          .subscribe();
    } catch (_) {
      // Offline or Supabase not initialized — local scoring continues seamlessly.
    }
  }

  Future<void> _reclaimScoring() async {
    setState(() => _reclaiming = true);
    try {
      await LocalEventStore.instance.reclaimScorerBaton(widget.matchId);
      await _load();
      if (!mounted) return;
      setState(() {
        _handedOverToOther = false;
        _reclaiming = false;
      });
      _showSnack('Scoring is back on this device.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _reclaiming = false);
      _showSnack('Could not reclaim scoring right now. Check connection.');
    }
  }

  Future<void> _load() async {
    final store = LocalEventStore.instance;
    final config = await store.getMatch(widget.matchId);
    final events = await store.getBallEvents(widget.matchId);
    if (!mounted) return;
    setState(() {
      _config = config;
      _events = events;
      _loading = false;
    });
  }

  DerivedMatchState? get _matchState {
    final config = _config;
    if (config == null) return null;
    return CricketEngine.derive(
      config,
      _events,
      forcedInnings: _forcedInnings,
      manualStrikerOverride: _manualStriker,
      manualNonStrikerOverride: _manualNonStriker,
      manualBowlerOverride: _manualBowler,
    );
  }

  int get _nextSequenceNumber {
    if (_events.isEmpty) return 1;
    var maxSeq = 0;
    for (final e in _events) {
      if (e.sequenceNumber > maxSeq) maxSeq = e.sequenceNumber;
    }
    return maxSeq + 1;
  }

  bool _needsNewBowler(DerivedInningsState inn) {
    final curBalls =
        inn.overs.isNotEmpty ? inn.overs.last.balls : const <BallEvent>[];
    final overHasDelivery = curBalls.any(
      (b) =>
          b.extraType != ExtraType.penalty &&
          b.wicketType != WicketType.retiredHurt,
    );
    return !inn.isComplete &&
        inn.legalBalls > 0 &&
        inn.legalBalls % 6 == 0 &&
        !overHasDelivery &&
        _manualBowler == null;
  }

  Future<void> _recordBall({
    int runsOffBat = 0,
    ExtraType extraType = ExtraType.none,
    int extraRuns = 0,
    bool isWicket = false,
    WicketType? wicketType,
    String? dismissedBatter,
    String? fielder,
    String? nextBatter,
  }) async {
    final state = _matchState;
    if (state == null) return;
    final inn = state.activeInnings;
    if (inn.isComplete) {
      _showSnack('Innings is complete. Start next innings or open Match Center.');
      return;
    }
    if (inn.needsNextBatter) {
      await _openSelectNextBatterSheet(state);
      return;
    }
    if (_needsNewBowler(inn)) {
      await _promptNewBowler(inn);
      return;
    }

    if (isWicket) {
      HapticFeedback.heavyImpact();
    } else if (runsOffBat == 4 || runsOffBat == 6) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }

    final event = BallEvent(
      id: _uuid.v4(),
      matchId: state.config.id,
      inningsNumber: inn.inningsNumber,
      sequenceNumber: _nextSequenceNumber,
      striker: inn.striker,
      nonStriker: inn.nonStriker,
      bowler: inn.currentBowler,
      runsOffBat: runsOffBat,
      extraType: extraType,
      extraRuns: extraRuns,
      isWicket: isWicket,
      wicketType: wicketType,
      dismissedBatter: dismissedBatter,
      fielder: fielder,
      nextBatter: nextBatter,
      synced: false,
      createdAt: DateTime.now(),
    );

    final prevLegal = inn.legalBalls;
    await LocalEventStore.instance.appendBallEvent(event);
    final updatedEvents =
        await LocalEventStore.instance.getBallEvents(widget.matchId);
    if (!mounted) return;

    setState(() {
      _events = updatedEvents;
      _manualStriker = null;
      _manualNonStriker = null;
      _manualBowler = null;
    });

    // Fire-and-forget idempotent Supabase sync
    LocalEventStore.instance.syncPendingToSupabase(widget.matchId);

    // Check if an over just completed and innings is still live
    final nextState = _matchState;
    if (nextState != null &&
        !nextState.activeInnings.isComplete &&
        event.isLegalDelivery &&
        (prevLegal + 1) % 6 == 0) {
      _promptNewBowler(nextState.activeInnings);
    }
  }

  Future<void> _undoLastBall() async {
    final state = _matchState;
    if (state == null) return;
    HapticFeedback.selectionClick();
    final undone = await LocalEventStore.instance.undoLastBall(
      state.config.id,
      state.activeInnings.inningsNumber,
    );
    if (undone == null) {
      _showSnack('No balls to undo in this innings.');
      return;
    }
    final updated = await LocalEventStore.instance.getBallEvents(widget.matchId);
    if (!mounted) return;
    setState(() {
      _events = updated;
      _manualStriker = null;
      _manualNonStriker = null;
      _manualBowler = null;
    });
    _showSnack('Undid last ball (${undone.shortMark})');
  }

  void _swapStrike() {
    final state = _matchState;
    if (state == null) return;
    final inn = state.activeInnings;
    if (inn.needsNextBatter) {
      _openSelectNextBatterSheet(state);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _manualStriker = inn.nonStriker;
      _manualNonStriker = inn.striker;
    });
  }

  Future<void> _promptNewBowler(DerivedInningsState inn) async {
    final picked = await showNextBowlerSheet(
      context,
      innings: inn,
      config: _config,
    );
    if (picked != null && picked.isNotEmpty && mounted) {
      final updatedCfg = await LocalEventStore.instance.addPlayerToTeam(
        widget.matchId,
        inn.bowlingTeam,
        picked,
      );
      if (!mounted) return;
      setState(() {
        if (updatedCfg != null) _config = updatedCfg;
        _manualBowler = picked;
      });
    }
  }

  Future<void> _openExtrasSheet(ExtraType type) async {
    final state = _matchState;
    if (state != null) {
      if (state.activeInnings.needsNextBatter) {
        await _openSelectNextBatterSheet(state);
        return;
      }
      if (_needsNewBowler(state.activeInnings)) {
        await _promptNewBowler(state.activeInnings);
        return;
      }
    }
    HapticFeedback.selectionClick();
    final chosen = await showExtrasRunsSheet(context, type);
    if (chosen == null) return;
    if (type == ExtraType.wide) {
      await _recordBall(extraType: ExtraType.wide, extraRuns: 1 + chosen);
    } else if (type == ExtraType.noBall) {
      await _recordBall(
        runsOffBat: chosen,
        extraType: ExtraType.noBall,
        extraRuns: 1,
      );
    } else {
      await _recordBall(extraType: type, extraRuns: chosen);
    }
  }

  Future<void> _openWicketSheet({
    WicketType initialType = WicketType.caught,
  }) async {
    final state = _matchState;
    if (state == null) return;
    final inn = state.activeInnings;
    if (inn.needsNextBatter) {
      await _openSelectNextBatterSheet(state);
      return;
    }
    if (_needsNewBowler(inn)) {
      await _promptNewBowler(inn);
      return;
    }

    final result = await showRecordWicketSheet(
      context,
      state,
      initialType: initialType,
    );
    if (result == null) return;

    if (result.customFielder.isNotEmpty) {
      final updatedCfg = await LocalEventStore.instance.addPlayerToTeam(
        widget.matchId,
        inn.bowlingTeam,
        result.customFielder,
      );
      if (updatedCfg != null && mounted) {
        setState(() => _config = updatedCfg);
      }
    }

    final int extraRuns = switch (result.deliveryExtra) {
      ExtraType.wide => 1 + result.completedRuns,
      ExtraType.noBall => 1,
      _ => 0,
    };
    final int runsOffBat =
        result.deliveryExtra == ExtraType.wide ? 0 : result.completedRuns;

    await _recordBall(
      runsOffBat: runsOffBat,
      extraType: result.deliveryExtra,
      extraRuns: extraRuns,
      isWicket: true,
      wicketType: result.wicketType,
      dismissedBatter: result.dismissedBatter,
      fielder: result.finalFielder,
      nextBatter: null,
    );
  }

  Future<void> _openReviseMatchSheet(DerivedMatchState state) async {
    if (state.config.isTestMatch) {
      _showSnack('Revised overs/target applies to limited-overs matches.');
      return;
    }
    final updated = await showReviseMatchSheet(context, state);
    if (updated == null) return;
    await LocalEventStore.instance.saveMatch(updated);
    if (!mounted) return;
    setState(() => _config = updated);
    _showSnack('Updated match to ${updated.oversLimit} overs.');
    try {
      await LocalEventStore.instance.ensureMatchSyncedToSupabase(updated.id);
    } catch (_) {}
  }

  Future<void> _endCurrentInnings(DerivedMatchState state) async {
    final ok = await confirmEndInningsDialog(context, state);
    if (!ok) return;
    final innNum = state.activeInningsNumber;
    final nextDeclared = {...state.config.declaredInnings, innNum}.toList();
    final updated = state.config.copyWith(declaredInnings: nextDeclared);
    await LocalEventStore.instance.saveMatch(updated);
    if (!mounted) return;
    setState(() => _config = updated);
    _showSnack('Innings $innNum ended.');
    try {
      await LocalEventStore.instance.ensureMatchSyncedToSupabase(updated.id);
    } catch (_) {}
  }

  Future<void> _abandonMatch(DerivedMatchState state) async {
    final ok = await confirmAbandonMatchDialog(context);
    if (!ok) return;
    final nextDeclared = {...state.config.declaredInnings, -1}.toList();
    final updated = state.config.copyWith(declaredInnings: nextDeclared);
    await LocalEventStore.instance.saveMatch(updated);
    if (!mounted) return;
    setState(() => _config = updated);
    _showSnack('Match marked as Abandoned (No result).');
    try {
      await LocalEventStore.instance.ensureMatchSyncedToSupabase(updated.id);
    } catch (_) {}
  }

  Future<void> _openMatchOptionsSheet(DerivedMatchState state) async {
    HapticFeedback.selectionClick();
    await showMatchOptionsSheet(
      context,
      onFiveRuns: () => _recordBall(runsOffBat: 5),
      onPenaltyRuns: () =>
          _recordBall(extraType: ExtraType.penalty, extraRuns: 5),
      onRetiredHurt: () =>
          _openWicketSheet(initialType: WicketType.retiredHurt),
      onEndInnings: () => _endCurrentInnings(state),
      onReviseRules: () => _openReviseMatchSheet(state),
      onHandOver: () => showHandOverScoringSheet(context, state),
      onAbandonMatch: () => _abandonMatch(state),
    );
  }

  Future<void> _openSelectNextBatterSheet(DerivedMatchState state) async {
    final inn = state.activeInnings;
    final picked = await showNextBatterSheet(context, state);
    if (picked == null || picked.isEmpty) return;

    // Persist new batter to team roster and onto the latest wicket event so
    // it survives restarts and integrates cleanly with Undo.
    final updatedCfg = await LocalEventStore.instance.addPlayerToTeam(
      widget.matchId,
      inn.battingTeam,
      picked,
    );

    final activeInningsEvents = _events
        .where((e) => !e.voided && e.inningsNumber == inn.inningsNumber)
        .toList();
    BallEvent? lastWicket;
    for (final e in activeInningsEvents.reversed) {
      if (e.isWicket && (e.nextBatter == null || e.nextBatter!.isEmpty)) {
        lastWicket = e;
        break;
      }
    }
    if (lastWicket != null) {
      await LocalEventStore.instance.updateBallEvent(
        lastWicket.copyWith(nextBatter: picked),
      );
    }

    final updatedEvents =
        await LocalEventStore.instance.getBallEvents(widget.matchId);
    if (!mounted) return;
    setState(() {
      if (updatedCfg != null) _config = updatedCfg;
      _events = updatedEvents;
    });
  }

  Future<void> _openEditBallSheet(BallEvent ball) async {
    HapticFeedback.selectionClick();
    final action = await showEditBallSheet(context, ball);
    if (action == null) return;
    if (action == 'delete') {
      await LocalEventStore.instance.voidBallById(ball.id);
    } else if (action.startsWith('runs:')) {
      final newRuns = int.parse(action.split(':')[1]);
      await LocalEventStore.instance.updateBallEvent(
        ball.copyWith(
          runsOffBat: newRuns,
          extraType: ExtraType.none,
          extraRuns: 0,
          isWicket: false,
        ),
      );
    }
    final updated = await LocalEventStore.instance.getBallEvents(widget.matchId);
    if (!mounted) return;
    setState(() => _events = updated);
    _showSnack('Ball updated — scorecard recalculated');
  }

  Future<void> _shareMatchSummary(DerivedMatchState state) async {
    await MatchSummaryPoster.shareMatch(state);
  }

  Future<void> _declareCurrentInnings(DerivedMatchState state) async {
    final ok = await confirmDeclareInningsDialog(context, state);
    if (!ok) return;
    final innNum = state.activeInnings.inningsNumber;
    final updatedDeclared = {...state.config.declaredInnings, innNum}.toList();
    final updated = state.config.copyWith(declaredInnings: updatedDeclared);
    await LocalEventStore.instance.saveMatch(updated);
    if (!mounted) return;
    setState(() => _config = updated);
    LocalEventStore.instance.syncPendingToSupabase(widget.matchId);
  }

  Future<void> _enforceFollowOn(DerivedMatchState state) async {
    final updated = state.config.copyWith(followOnEnforced: true);
    await LocalEventStore.instance.saveMatch(updated);
    if (!mounted) return;
    setState(() {
      _config = updated;
      _forcedInnings = 3;
    });
    LocalEventStore.instance.syncPendingToSupabase(widget.matchId);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;

    if (_loading) {
      return Scaffold(
        backgroundColor: c.ground,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final state = _matchState;
    if (state == null) {
      return Scaffold(
        backgroundColor: c.ground,
        appBar: AppBar(title: const Text('Match not found')),
        body: const Center(child: Text('Could not load match.')),
      );
    }

    final inn = state.activeInnings;
    final strikerStats = inn.batterByName(inn.striker);
    final nonStrikerStats = inn.batterByName(inn.nonStriker);
    final bowlerStats = inn.bowlerByName(inn.currentBowler);

    final currentOver = inn.overs.isNotEmpty ? inn.overs.last : null;
    final previousOver =
        inn.overs.length >= 2 ? inn.overs[inn.overs.length - 2] : null;

    // Last wicket in current over (borrowed from Comp C for instant context)
    BallEvent? recentWicket;
    if (currentOver != null) {
      for (final b in currentOver.balls.reversed) {
        if (b.isWicket) {
          recentWicket = b;
          break;
        }
      }
    }

    return Scaffold(
      backgroundColor: c.ground,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: const Alignment(0, -0.25),
            colors: [c.sageWashTop, c.ground],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 1. Top App Bar
              TopMatchBar(
                title: state.config.title,
                formatLabel: state.config.formatLabel,
                isLive: state.status == MatchStatus.live,
                onBack: () => Navigator.of(context).maybePop(),
                onOptions: () => _openMatchOptionsSheet(state),
                onScorecard: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ScorecardScreen(matchId: widget.matchId),
                    ),
                  );
                  _load();
                },
              ),

              // 2. Open Scoreboard Area (scrollable safeguard for large font scales)
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Open monumental score + right-aligned chase stack
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          inn.battingTeam.toUpperCase(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: c.pitchGreen,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.9,
                                              ),
                                        ),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: '${inn.totalRuns}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .displayLarge
                                                      ?.copyWith(
                                                        fontSize: 58,
                                                        fontWeight:
                                                            FontWeight.w300,
                                                      ),
                                                ),
                                                TextSpan(
                                                  text: '/${inn.wickets}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .displayLarge
                                                      ?.copyWith(
                                                        fontSize: 58,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${inn.oversText}${inn.oversLimit > 0 ? ' / ${inn.oversLimit}' : ''} ov · Extras ${inn.wides + inn.noBalls + inn.byes + inn.legByes}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(fontSize: 13.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ChaseOrRateStack(
                                    innings: inn,
                                    status: state.status,
                                    isTestMatch: state.config.isTestMatch,
                                    leadTrailText: state.leadTrailText,
                                    resultSummary: state.resultSummary,
                                    onShare: () => _shareMatchSummary(state),
                                  ),
                                ],
                              ),
                            ),

                            // Daylight Glass Live Crease Card (Batters + Bowler tables)
                            LiveCreaseCard(
                              strikerEmpty: inn.striker.isEmpty,
                              nonStrikerEmpty: inn.nonStriker.isEmpty,
                              striker: strikerStats,
                              nonStriker: nonStrikerStats,
                              bowler: bowlerStats,
                              needsNewBowler: _needsNewBowler(inn),
                              onSwapStrike: _swapStrike,
                              onSelectNextBatter: () =>
                                  _openSelectNextBatterSheet(state),
                              onSelectNextBowler: () => _promptNewBowler(inn),
                            ),

                            // Horizontal over timeline (previous faded + current over)
                            OverTimeline(
                              previousOver: previousOver,
                              currentOver: currentOver,
                              recentWicket: recentWicket,
                              onBallTap: _openEditBallSheet,
                            ),

                            if (state.config.isTestMatch &&
                                state.status == MatchStatus.live &&
                                inn.inningsNumber < 4)
                              Align(
                                alignment: Alignment.center,
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () =>
                                      _declareCurrentInnings(state),
                                  child: Text(
                                    'Declare innings',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(color: c.pitchGreen),
                                  ),
                                ),
                              ),

                            if (state.status == MatchStatus.inningsBreak &&
                                !_handedOverToOther)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: c.pitchGreen,
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: () {
                                          setState(
                                            () => _forcedInnings =
                                                state.activeInningsNumber + 1,
                                          );
                                        },
                                        child: Text(
                                          'Start Innings ${state.activeInningsNumber + 1}',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: () => showHandOverScoringSheet(
                                        context,
                                        state,
                                      ),
                                      icon: const Icon(
                                        Icons.swap_horiz_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Hand over'),
                                    ),
                                    if (state.canEnforceFollowOn) ...[
                                      const SizedBox(width: 8),
                                      OutlinedButton(
                                        onPressed: () =>
                                            _enforceFollowOn(state),
                                        child: const Text('Follow-on'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // 3. Raised Frosted-Glass Bottom Sheet Scoring Pad (or Live Viewer Banner)
              if (_handedOverToOther)
                HandedOverSheet(
                  reclaiming: _reclaiming,
                  onReclaim: _reclaimScoring,
                )
              else
                GlassScoringSheet(
                  onRunTap: (runs) => _recordBall(runsOffBat: runs),
                  onExtraTap: _openExtrasSheet,
                  onWicketTap: () => _openWicketSheet(),
                  onRunOutTap: () =>
                      _openWicketSheet(initialType: WicketType.runOut),
                  onUndoTap: _undoLastBall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
