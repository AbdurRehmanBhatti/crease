import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../data/local_event_store.dart';
import '../../domain/cricket_engine.dart';
import '../../domain/models.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/glass_surface.dart';
import '../scorecard/match_summary_poster.dart';
import '../scorecard/scorecard_screen.dart';
import 'scorer_handover_sheets.dart';

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
    final updatedEvents = await LocalEventStore.instance.getBallEvents(widget.matchId);
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
    final config = _config;
    final controller = TextEditingController();
    final rosterSet = <String>{
      if (config != null) ...config.rosterForTeam(inn.bowlingTeam),
      ...inn.bowlers.map((b) => b.name),
    }..remove(inn.currentBowler);
    final availableBowlers = rosterSet.toList();

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: GlassSurface(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            fillColor: c.surfaceSheet,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Select next bowler · ${inn.bowlingTeam}',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (availableBowlers.isNotEmpty) ...[
                  Text(
                    'Available bowlers',
                    style: Theme.of(ctx).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final name in availableBowlers)
                        ActionChip(
                          label: Text(name),
                          backgroundColor: c.surfaceKey,
                          side: BorderSide(color: c.pitchGreen, width: 1),
                          labelStyle: TextStyle(
                            color: c.inkPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                          onPressed: () => Navigator.pop(ctx, name),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                // Show who just bowled as muted/disabled so it's clear why they can't bowl back-to-back overs
                if (inn.legalBalls > 0 && inn.currentBowler.isNotEmpty) ...[
                  Text(
                    'Bowled previous over',
                    style: Theme.of(ctx).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Opacity(
                      opacity: 0.45,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: c.pillMutedBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: c.hairline),
                        ),
                        child: Text(
                          '${inn.currentBowler} · ${inn.bowlerByName(inn.currentBowler).figuresText}',
                          style: Theme.of(ctx).textTheme.labelMedium,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: '+ Add new bowler',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onSubmitted: (val) {
                    if (val.trim().isNotEmpty) Navigator.pop(ctx, val.trim());
                  },
                ),
                const SizedBox(height: 14),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.pitchGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    final text = controller.text.trim();
                    Navigator.pop(
                      ctx,
                      text.isEmpty ? 'Bowler ${inn.bowlers.length + 1}' : text,
                    );
                  },
                  child: const Text('Confirm bowler'),
                ),
              ],
            ),
          ),
        );
      },
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
    final isPenaltyExtra = type == ExtraType.wide || type == ExtraType.noBall;
    final options = switch (type) {
      ExtraType.noBall => [0, 1, 2, 3, 4, 6],
      ExtraType.wide => [0, 1, 2, 3, 4],
      _ => [1, 2, 3, 4],
    };

    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return GlassSurface(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          fillColor: c.surfaceSheet,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                isPenaltyExtra
                    ? '${type.displayLabel} (+1 penalty) — additional runs?'
                    : '${type.displayLabel} — how many runs?',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              if (options.length <= 5)
                Row(
                  children: [
                    for (final r in options)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _KeypadButton(
                            label: isPenaltyExtra ? '+$r' : '$r',
                            isAccent: r == 4 || r == 6,
                            onTap: () => Navigator.pop(ctx, r),
                          ),
                        ),
                      ),
                  ],
                )
              else
                Column(
                  children: [
                    Row(
                      children: [
                        for (final r in options.take(3))
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: _KeypadButton(
                                label: '+$r',
                                onTap: () => Navigator.pop(ctx, r),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (final r in options.skip(3))
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: _KeypadButton(
                                label: '+$r',
                                isAccent: r == 4 || r == 6,
                                onTap: () => Navigator.pop(ctx, r),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );

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

  Future<void> _openWicketSheet({WicketType initialType = WicketType.caught}) async {
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

    WicketType selectedType = initialType;
    ExtraType deliveryExtra = ExtraType.none;
    int completedRuns = 0;
    String dismissed = inn.striker;
    String? selectedFielder;
    final customFielderCtrl = TextEditingController();

    final fieldingRoster = <String>{
      ...state.config.rosterForTeam(inn.bowlingTeam),
      ...inn.bowlers.map((b) => b.name),
    }.toList();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final needsFielder = selectedType == WicketType.caught ||
                selectedType == WicketType.runOut ||
                selectedType == WicketType.stumped;
            final canPickBatter = selectedType == WicketType.runOut ||
                selectedType == WicketType.retiredHurt;
            final canHaveExtra = selectedType == WicketType.stumped ||
                selectedType == WicketType.runOut ||
                selectedType == WicketType.hitWicket;
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: GlassSurface(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                fillColor: c.surfaceSheet,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: c.hairline,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        selectedType == WicketType.retiredHurt
                            ? 'Retire batter (hurt)'
                            : 'Record wicket',
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final wt in WicketType.values)
                            ChoiceChip(
                              label: Text(wt.label),
                              selected: selectedType == wt,
                              selectedColor: wt == WicketType.retiredHurt
                                  ? c.pitchGreen
                                  : c.wicketRed,
                              checkmarkColor: Colors.white,
                              labelStyle: TextStyle(
                                color: selectedType == wt
                                    ? Colors.white
                                    : c.inkPrimary,
                                fontWeight: selectedType == wt
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                              side: BorderSide(
                                color: selectedType == wt
                                    ? (wt == WicketType.retiredHurt
                                        ? c.pitchGreen
                                        : c.wicketRed)
                                    : c.hairline,
                              ),
                              onSelected: (_) => setModalState(() {
                                selectedType = wt;
                                if (wt != WicketType.stumped &&
                                    wt != WicketType.runOut &&
                                    wt != WicketType.hitWicket) {
                                  deliveryExtra = ExtraType.none;
                                }
                                if (wt != WicketType.runOut) {
                                  completedRuns = 0;
                                }
                              }),
                            ),
                        ],
                      ),
                      if (canPickBatter) ...[
                        const SizedBox(height: 14),
                        SegmentedButton<String>(
                          segments: [
                            ButtonSegment(
                              value: inn.striker,
                              label: Text(inn.striker),
                            ),
                            ButtonSegment(
                              value: inn.nonStriker,
                              label: Text(inn.nonStriker),
                            ),
                          ],
                          selected: {dismissed},
                          onSelectionChanged: (s) =>
                              setModalState(() => dismissed = s.first),
                        ),
                      ],
                      if (canHaveExtra) ...[
                        const SizedBox(height: 14),
                        Text(
                          'Delivery type',
                          style: Theme.of(ctx).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final ex in [
                              ExtraType.none,
                              ExtraType.wide,
                              ExtraType.noBall,
                            ])
                              ChoiceChip(
                                label: Text(
                                  ex == ExtraType.none
                                      ? 'Fair ball'
                                      : '${ex.displayLabel} (+1)',
                                ),
                                selected: deliveryExtra == ex,
                                selectedColor: c.pitchGreen,
                                checkmarkColor: Colors.white,
                                labelStyle: TextStyle(
                                  color: deliveryExtra == ex
                                      ? Colors.white
                                      : c.inkPrimary,
                                  fontWeight: deliveryExtra == ex
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                                side: BorderSide(
                                  color: deliveryExtra == ex
                                      ? c.pitchGreen
                                      : c.hairline,
                                ),
                                onSelected: (_) =>
                                    setModalState(() => deliveryExtra = ex),
                              ),
                          ],
                        ),
                      ],
                      if (selectedType == WicketType.runOut) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Runs completed before run out',
                          style: Theme.of(ctx).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final r in [0, 1, 2, 3])
                              ChoiceChip(
                                label: Text('$r'),
                                selected: completedRuns == r,
                                selectedColor: c.pitchGreen,
                                checkmarkColor: Colors.white,
                                labelStyle: TextStyle(
                                  color: completedRuns == r
                                      ? Colors.white
                                      : c.inkPrimary,
                                ),
                                side: BorderSide(
                                  color: completedRuns == r
                                      ? c.pitchGreen
                                      : c.hairline,
                                ),
                                onSelected: (_) =>
                                    setModalState(() => completedRuns = r),
                              ),
                          ],
                        ),
                      ],
                      if (needsFielder) ...[
                        const SizedBox(height: 14),
                        Text(
                          'Fielder · ${inn.bowlingTeam} (optional)',
                          style: Theme.of(ctx).textTheme.labelMedium,
                        ),
                        if (fieldingRoster.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final player in fieldingRoster)
                                ChoiceChip(
                                  label: Text(player),
                                  selected: selectedFielder == player,
                                  selectedColor: c.pitchGreen,
                                  checkmarkColor: Colors.white,
                                  labelStyle: TextStyle(
                                    color: selectedFielder == player
                                        ? Colors.white
                                        : c.inkPrimary,
                                    fontWeight: selectedFielder == player
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                  side: BorderSide(
                                    color: selectedFielder == player
                                        ? c.pitchGreen
                                        : c.hairline,
                                  ),
                                  onSelected: (sel) => setModalState(() {
                                    selectedFielder = sel ? player : null;
                                    if (sel) customFielderCtrl.clear();
                                  }),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        TextField(
                          controller: customFielderCtrl,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (val) {
                            if (val.trim().isNotEmpty &&
                                selectedFielder != null) {
                              setModalState(() => selectedFielder = null);
                            }
                          },
                          decoration: InputDecoration(
                            hintText: '+ Add new fielder (optional)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: c.wicketRed,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Confirm wicket'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != true) return;
    final customFielder = customFielderCtrl.text.trim();
    final finalFielder =
        customFielder.isNotEmpty ? customFielder : selectedFielder;

    if (customFielder.isNotEmpty) {
      final updatedCfg = await LocalEventStore.instance.addPlayerToTeam(
        widget.matchId,
        inn.bowlingTeam,
        customFielder,
      );
      if (updatedCfg != null && mounted) {
        setState(() => _config = updatedCfg);
      }
    }

    final int extraRuns = switch (deliveryExtra) {
      ExtraType.wide => 1 + completedRuns,
      ExtraType.noBall => 1,
      _ => 0,
    };
    final int runsOffBat =
        deliveryExtra == ExtraType.wide ? 0 : completedRuns;

    await _recordBall(
      runsOffBat: runsOffBat,
      extraType: deliveryExtra,
      extraRuns: extraRuns,
      isWicket: true,
      wicketType: selectedType,
      dismissedBatter: dismissed,
      fielder: finalFielder,
      nextBatter: null,
    );
  }

  Future<void> _openReviseMatchSheet(DerivedMatchState state) async {
    if (state.config.isTestMatch) {
      _showSnack('Revised overs/target applies to limited-overs matches.');
      return;
    }
    final oversCtrl =
        TextEditingController(text: '${state.config.oversLimit}');
    final currentTarget = state.innings2?.target ??
        state.config.firstInningsTargetOverride ??
        (state.innings1.isComplete ? state.innings1.totalRuns + 1 : null);
    final targetCtrl = TextEditingController(
      text: currentTarget != null ? '$currentTarget' : '',
    );

    final updated = await showModalBottomSheet<MatchConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: GlassSurface(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            fillColor: c.surfaceSheet,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Revise overs / target (Rain / DLS)',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Adjust overs limit or set a revised 2nd-innings target if rain shortens the match.',
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: oversCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Overs per innings',
                    hintText: 'e.g. 12',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: targetCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Revised target (optional)',
                    hintText: 'Leave blank to use 1st innings + 1',
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.pitchGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () {
                    final newOvers = int.tryParse(oversCtrl.text.trim()) ??
                        state.config.oversLimit;
                    final newTarget = int.tryParse(targetCtrl.text.trim());
                    final safeOvers = newOvers.clamp(1, 50);
                    Navigator.pop(
                      ctx,
                      state.config.copyWith(
                        oversLimit: safeOvers,
                        formatLabel: '${safeOvers}OV',
                        firstInningsTargetOverride: newTarget,
                        clearTargetOverride: newTarget == null,
                      ),
                    );
                  },
                  child: const Text('Apply revised rules'),
                ),
              ],
            ),
          ),
        );
      },
    );

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
    final innNum = state.activeInningsNumber;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('End Innings $innNum?'),
        content: Text(
          'Close ${state.activeInnings.battingTeam}\'s innings at ${state.activeInnings.scoreText} (${state.activeInnings.oversText} ov)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End innings'),
          ),
        ],
      ),
    );
    if (ok != true) return;
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abandon match?'),
        content: const Text(
          'Marks this match as Abandoned (No result). In a tournament, both teams receive 1 point with no NRR impact.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.crease.wicketRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Abandon match'),
          ),
        ],
      ),
    );
    if (ok != true) return;
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
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return GlassSurface(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          fillColor: c.surfaceSheet,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Match options',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.35,
                children: [
                  _OptionTile(
                    icon: Icons.looks_5_outlined,
                    title: '5 runs',
                    subtitle: 'Overthrow',
                    onTap: () {
                      Navigator.pop(ctx);
                      _recordBall(runsOffBat: 5);
                    },
                  ),
                  _OptionTile(
                    icon: Icons.flag_outlined,
                    title: '+5 Penalty',
                    subtitle: 'Dead-ball award',
                    onTap: () {
                      Navigator.pop(ctx);
                      _recordBall(extraType: ExtraType.penalty, extraRuns: 5);
                    },
                  ),
                  _OptionTile(
                    icon: Icons.healing_outlined,
                    title: 'Retired hurt',
                    subtitle: 'No wicket lost',
                    onTap: () {
                      Navigator.pop(ctx);
                      _openWicketSheet(initialType: WicketType.retiredHurt);
                    },
                  ),
                  _OptionTile(
                    icon: Icons.stop_circle_outlined,
                    title: 'End innings',
                    subtitle: 'Close / declare',
                    onTap: () {
                      Navigator.pop(ctx);
                      _endCurrentInnings(state);
                    },
                  ),
                  _OptionTile(
                    icon: Icons.thunderstorm_outlined,
                    title: 'Revise rules',
                    subtitle: 'Rain / target',
                    onTap: () {
                      Navigator.pop(ctx);
                      _openReviseMatchSheet(state);
                    },
                  ),
                  _OptionTile(
                    icon: Icons.swap_horiz_rounded,
                    title: 'Hand over',
                    subtitle: 'Switch scorer',
                    onTap: () {
                      Navigator.pop(ctx);
                      showHandOverScoringSheet(context, state);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.wicketRed,
                  side: BorderSide(color: c.wicketRed.withValues(alpha: 0.35)),
                  minimumSize: const Size.fromHeight(44),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _abandonMatch(state);
                },
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Abandon match (No result)'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openSelectNextBatterSheet(DerivedMatchState state) async {
    final inn = state.activeInnings;
    final roster = <String>{
      ...state.config.rosterForTeam(inn.battingTeam),
      ...inn.batters.map((b) => b.name),
    }.toList();

    final batterMap = {for (final b in inn.batters) b.name: b};
    final unavailable = <String>{
      for (final b in inn.batters)
        if (b.isOut) b.name,
      if (inn.striker.isNotEmpty) inn.striker,
      if (inn.nonStriker.isNotEmpty) inn.nonStriker,
    };

    final availablePlayers =
        roster.where((p) => !unavailable.contains(p)).toList();
    final disabledPlayers =
        roster.where((p) => unavailable.contains(p)).toList();

    final newBatterCtrl = TextEditingController();

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: GlassSurface(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            fillColor: c.surfaceSheet,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: c.hairline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Select next batter · ${inn.battingTeam}',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if (availablePlayers.isNotEmpty) ...[
                    Text(
                      'Available squad',
                      style: Theme.of(ctx).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final player in availablePlayers)
                          ActionChip(
                            label: Text(player),
                            backgroundColor: c.surfaceKey,
                            side: BorderSide(color: c.pitchGreen, width: 1),
                            labelStyle: TextStyle(
                              color: c.inkPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                            onPressed: () => Navigator.pop(ctx, player),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (disabledPlayers.isNotEmpty) ...[
                    Text(
                      'Already batted',
                      style: Theme.of(ctx).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final player in disabledPlayers)
                          Opacity(
                            opacity: 0.45,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: c.pillMutedBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: c.hairline),
                              ),
                              child: Text(
                                () {
                                  final stats = batterMap[player];
                                  if (stats == null) return player;
                                  if (!stats.isOut) return '$player · At crease';
                                  return '$player · Out ${stats.runs} (${stats.balls})';
                                }(),
                                style: Theme.of(ctx).textTheme.labelMedium,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: newBatterCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            hintText: '+ Add new batter',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onSubmitted: (val) {
                            if (val.trim().isNotEmpty) {
                              Navigator.pop(ctx, val.trim());
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: c.pitchGreen,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          final text = newBatterCtrl.text.trim();
                          if (text.isNotEmpty) Navigator.pop(ctx, text);
                        },
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

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
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return GlassSurface(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          fillColor: c.surfaceSheet,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Edit ball · ${ball.striker} off ${ball.bowler}',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              if (ball.dismissalSummary != null) ...[
                const SizedBox(height: 4),
                Text(
                  ball.dismissalSummary!,
                  style: Theme.of(ctx)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: c.wicketRed),
                ),
              ],
              const SizedBox(height: 14),
              Text('Change runs off bat:',
                  style: Theme.of(ctx).textTheme.labelMedium),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final r in [0, 1, 2, 3, 4, 6])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _KeypadButton(
                          label: '$r',
                          isAccent: r == 4 || r == 6,
                          onTap: () => Navigator.pop(ctx, 'runs:$r'),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.wicketRed,
                  side: BorderSide(color: c.wicketRed),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, 'delete'),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                label: const Text('Remove this ball from log'),
              ),
            ],
          ),
        );
      },
    );

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
    final innNum = state.activeInnings.inningsNumber;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Declare innings?'),
        content: Text(
          'Declare ${state.activeInnings.battingTeam} at ${state.activeInnings.scoreText} (${state.activeInnings.oversText} ov)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Declare'),
          ),
        ],
      ),
    );
    if (ok != true) return;
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
              _TopMatchBar(
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
                                  _ChaseOrRateStack(
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
                            _LiveCreaseCard(
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
                            _OverTimeline(
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
                                  onPressed: () => _declareCurrentInnings(state),
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
                _HandedOverSheet(
                  reclaiming: _reclaiming,
                  onReclaim: _reclaimScoring,
                )
              else
                _GlassScoringSheet(
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

class _TopMatchBar extends StatelessWidget {
  const _TopMatchBar({
    required this.title,
    required this.formatLabel,
    required this.isLive,
    required this.onBack,
    required this.onOptions,
    required this.onScorecard,
  });

  final String title;
  final String formatLabel;
  final bool isLive;
  final VoidCallback onBack;
  final VoidCallback onOptions;
  final VoidCallback onScorecard;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
            onPressed: onBack,
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onScorecard,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isLive) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: c.pitchGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.pillMutedBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        formatLabel,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontSize: 11,
                              color: c.inkPrimary,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Scorecard & charts',
            icon: const Icon(Icons.bar_chart_rounded, size: 22),
            onPressed: onScorecard,
          ),
          IconButton(
            tooltip: 'Match options',
            icon: const Icon(Icons.more_horiz_rounded, size: 22),
            onPressed: onOptions,
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Material(
      color: c.surfaceKey,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.hairlineSubtle),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: c.pitchGreen),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: c.inkPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: c.inkSecondary,
                            fontSize: 11,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HandedOverSheet extends StatelessWidget {
  const _HandedOverSheet({
    required this.reclaiming,
    required this.onReclaim,
  });

  final bool reclaiming;
  final VoidCallback onReclaim;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return GlassSurface(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      fillColor: c.surfaceSheet,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: c.pitchGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Scoring on another device',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Live balls are syncing automatically. Take back scoring anytime when your team is ready.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: c.pitchGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: reclaiming ? null : onReclaim,
            icon: reclaiming
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.swap_horiz_rounded, size: 20),
            label: Text(reclaiming ? 'Syncing latest balls…' : 'Take back scoring'),
          ),
        ],
      ),
    );
  }
}

class _ChaseOrRateStack extends StatelessWidget {
  const _ChaseOrRateStack({
    required this.innings,
    required this.status,
    required this.isTestMatch,
    required this.leadTrailText,
    required this.resultSummary,
    required this.onShare,
  });

  final DerivedInningsState innings;
  final MatchStatus status;
  final bool isTestMatch;
  final String? leadTrailText;
  final String? resultSummary;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    if (status == MatchStatus.completed && resultSummary != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'FINAL',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: c.pitchGreen,
                  letterSpacing: 0.8,
                ),
          ),
          const SizedBox(height: 2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 145),
            child: Text(
              resultSummary!,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onShare,
            icon: const Icon(Icons.share_rounded, size: 15),
            label: const Text('Share'),
          ),
        ],
      );
    }

    if (isTestMatch) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'Inn ${innings.inningsNumber}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 2),
          if (leadTrailText != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 145),
              child: Text(
                leadTrailText!,
                textAlign: TextAlign.right,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 2),
          Text(
            'CRR ${innings.currentRunRate.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      );
    }

    if (innings.target != null && innings.runsNeeded != null) {
      final rrr = innings.requiredRunRate;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Need ',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                TextSpan(
                  text: '${innings.runsNeeded}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'from ',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                TextSpan(
                  text: '${innings.ballsRemaining}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: ' balls',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            rrr == null ? 'RRR —' : 'RRR ${rrr.toStringAsFixed(1)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '1st Innings',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 2),
        Text(
          'CRR ${innings.currentRunRate.toStringAsFixed(2)}',
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          '${innings.ballsRemaining} balls left',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _OverTimeline extends StatelessWidget {
  const _OverTimeline({
    required this.previousOver,
    required this.currentOver,
    required this.recentWicket,
    required this.onBallTap,
  });

  final OverSummary? previousOver;
  final OverSummary? currentOver;
  final BallEvent? recentWicket;
  final ValueChanged<BallEvent> onBallTap;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final currentBalls = currentOver?.balls ?? const <BallEvent>[];
    final legalCount = currentOver?.legalBallsInOver ?? 0;
    final emptySlots = (6 - legalCount).clamp(0, 6);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            children: [
              if (previousOver != null) ...[
                Opacity(
                  opacity: 0.4,
                  child: Row(
                    children: [
                      Text(
                        '${previousOver!.overNumber}',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(width: 6),
                      for (final b in previousOver!.balls.length > 2
                          ? previousOver!.balls
                              .sublist(previousOver!.balls.length - 2)
                          : previousOver!.balls)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _BallCircle(
                            ball: b,
                            onTap: () => onBallTap(b),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (currentOver != null) ...[
                Text(
                  '${currentOver!.overNumber}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(width: 10),
              ],
              for (final b in currentBalls)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _BallCircle(
                    ball: b,
                    onTap: () => onBallTap(b),
                  ),
                ),
              for (var i = 0; i < emptySlots; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: c.hairline, width: 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (recentWicket?.dismissalSummary != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: c.pillMutedBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              recentWicket!.dismissalSummary!,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: c.inkPrimary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}

class _BallCircle extends StatelessWidget {
  const _BallCircle({required this.ball, required this.onTap});

  final BallEvent ball;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final isBoundary =
        !ball.isWicket && (ball.runsOffBat == 4 || ball.runsOffBat == 6);

    Color bg = c.surfaceGlass;
    Color border = c.hairline;
    Color fg = c.inkPrimary;

    if (ball.isWicket) {
      bg = c.wicketRed;
      border = c.wicketRed;
      fg = Colors.white;
    } else if (isBoundary) {
      bg = c.pitchGreenSoft;
      border = c.pitchGreen;
      fg = c.pitchGreen;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: border, width: 1),
        ),
        child: Text(
          ball.shortMark,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: fg,
                fontSize: ball.shortMark.length > 2 ? 10 : 13,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

class _GlassScoringSheet extends StatelessWidget {
  const _GlassScoringSheet({
    required this.onRunTap,
    required this.onExtraTap,
    required this.onWicketTap,
    required this.onRunOutTap,
    required this.onUndoTap,
  });

  final ValueChanged<int> onRunTap;
  final ValueChanged<ExtraType> onExtraTap;
  final VoidCallback onWicketTap;
  final VoidCallback onRunOutTap;
  final VoidCallback onUndoTap;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;

    return GlassSurface(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      fillColor: c.surfaceSheet,
      borderColor: c.hairline,
      blurSigma: 14,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grab handle
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: c.hairline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Row 1: 0, 1, 2
          Row(
            children: [
              Expanded(child: _KeypadButton(label: '0', onTap: () => onRunTap(0))),
              const SizedBox(width: 10),
              Expanded(child: _KeypadButton(label: '1', onTap: () => onRunTap(1))),
              const SizedBox(width: 10),
              Expanded(child: _KeypadButton(label: '2', onTap: () => onRunTap(2))),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: 3, 4 (green), 6 (green)
          Row(
            children: [
              Expanded(child: _KeypadButton(label: '3', onTap: () => onRunTap(3))),
              const SizedBox(width: 10),
              Expanded(
                child: _KeypadButton(
                  label: '4',
                  isAccent: true,
                  onTap: () => onRunTap(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _KeypadButton(
                  label: '6',
                  isAccent: true,
                  onTap: () => onRunTap(6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 3: 4-segment extras bar (Wide | No ball | Bye | Leg bye)
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: c.surfaceKey,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: c.hairline, width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(23),
              child: Row(
                children: [
                  _ExtraSegment(
                    label: 'Wide',
                    onTap: () => onExtraTap(ExtraType.wide),
                  ),
                  VerticalDivider(width: 1, color: c.hairline),
                  _ExtraSegment(
                    label: 'No ball',
                    onTap: () => onExtraTap(ExtraType.noBall),
                  ),
                  VerticalDivider(width: 1, color: c.hairline),
                  _ExtraSegment(
                    label: 'Bye',
                    onTap: () => onExtraTap(ExtraType.bye),
                  ),
                  VerticalDivider(width: 1, color: c.hairline),
                  _ExtraSegment(
                    label: 'Leg bye',
                    onTap: () => onExtraTap(ExtraType.legBye),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Row 4: Wicket (red) + Run out? + Undo (in thumb zone!)
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Material(
                  color: c.wicketRed,
                  borderRadius: BorderRadius.circular(26),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(26),
                    onTap: onWicketTap,
                    child: Container(
                      height: 52,
                      alignment: Alignment.center,
                      child: const Text(
                        'Wicket',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onRunOutTap,
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    child: Text(
                      'Run out?',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: c.inkSecondary,
                            fontWeight: FontWeight.w500,
                            fontSize: 14.5,
                          ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Material(
                color: c.surfaceKey,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                  side: BorderSide(color: c.hairline, width: 1),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(26),
                  onTap: onUndoTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.undo_rounded,
                          size: 18,
                          color: c.inkPrimary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Undo',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({
    required this.label,
    required this.onTap,
    this.isAccent = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool isAccent;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isAccent ? c.pitchGreen : c.surfaceKey;
    final fg = isAccent ? Colors.white : c.inkPrimary;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0xFF0A0C0C))
                .withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: -2,
          ),
        ],
      ),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isAccent ? c.pitchGreen : c.hairline,
            width: 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            height: 64,
            alignment: Alignment.center,
            child: Text(
              label,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.w400,
                    color: fg,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExtraSegment extends StatelessWidget {
  const _ExtraSegment({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
      ),
    );
  }
}



/// Single-layer Daylight Glass live crease table showing full batter names
/// (R, B, 4s, 6s, SR) and active bowler figures (O, M, R, W, Eco) with zero
/// truncation and tabular alignment.
class _LiveCreaseCard extends StatelessWidget {
  const _LiveCreaseCard({
    required this.strikerEmpty,
    required this.nonStrikerEmpty,
    required this.striker,
    required this.nonStriker,
    required this.bowler,
    required this.needsNewBowler,
    required this.onSwapStrike,
    required this.onSelectNextBatter,
    required this.onSelectNextBowler,
  });

  final bool strikerEmpty;
  final bool nonStrikerEmpty;
  final BatterLine striker;
  final BatterLine nonStriker;
  final BowlerLine bowler;
  final bool needsNewBowler;
  final VoidCallback onSwapStrike;
  final VoidCallback onSelectNextBatter;
  final VoidCallback onSelectNextBowler;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final headerStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          fontSize: 11,
          color: c.inkSecondary,
          fontWeight: FontWeight.w600,
        );

    return GlassSurface(
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Batters header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              children: [
                Expanded(child: Text('Batter', style: headerStyle)),
                _ColHeader('R', width: 30, style: headerStyle),
                _ColHeader('B', width: 30, style: headerStyle),
                _ColHeader('4s', width: 26, style: headerStyle),
                _ColHeader('6s', width: 26, style: headerStyle),
                _ColHeader('SR', width: 44, style: headerStyle),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (strikerEmpty)
            _ActionCreaseRow(
              icon: Icons.person_add_alt_1_rounded,
              label: 'Select next batter',
              onTap: onSelectNextBatter,
            )
          else
            _BatterTableRow(
              batter: striker,
              isStriker: true,
              onTap: onSwapStrike,
            ),
          const SizedBox(height: 2),
          if (nonStrikerEmpty)
            _ActionCreaseRow(
              icon: Icons.person_add_alt_1_rounded,
              label: 'Select next batter',
              onTap: onSelectNextBatter,
            )
          else
            _BatterTableRow(
              batter: nonStriker,
              isStriker: false,
              onTap: onSwapStrike,
            ),
          Divider(height: 14, color: c.hairlineSubtle),
          // Bowler header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              children: [
                Expanded(child: Text('Bowler', style: headerStyle)),
                _ColHeader('O', width: 30, style: headerStyle),
                _ColHeader('M', width: 26, style: headerStyle),
                _ColHeader('R', width: 30, style: headerStyle),
                _ColHeader('W', width: 26, style: headerStyle),
                _ColHeader('Eco', width: 44, style: headerStyle),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (needsNewBowler)
            _ActionCreaseRow(
              icon: Icons.sports_baseball_outlined,
              label: 'Select next bowler',
              onTap: onSelectNextBowler,
            )
          else
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onSelectNextBowler,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        bowler.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: c.inkPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ),
                    _NumCell(bowler.oversText, width: 30),
                    _NumCell('${bowler.maidens}', width: 26, muted: true),
                    _NumCell('${bowler.runsConceded}', width: 30),
                    _NumCell('${bowler.wickets}', width: 26, bold: true),
                    _NumCell(
                      bowler.economy.toStringAsFixed(1),
                      width: 44,
                      muted: true,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BatterTableRow extends StatelessWidget {
  const _BatterTableRow({
    required this.batter,
    required this.isStriker,
    required this.onTap,
  });

  final BatterLine batter;
  final bool isStriker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Material(
      color: isStriker ? c.pitchGreenSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        batter.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: c.inkPrimary,
                              fontWeight:
                                  isStriker ? FontWeight.w600 : FontWeight.w500,
                            ),
                      ),
                    ),
                    if (isStriker)
                      Text(
                        ' *',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: c.pitchGreen,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                  ],
                ),
              ),
              _NumCell('${batter.runs}', width: 30, bold: true),
              _NumCell('${batter.balls}', width: 30, muted: true),
              _NumCell('${batter.fours}', width: 26, muted: true),
              _NumCell('${batter.sixes}', width: 26, muted: true),
              _NumCell(
                batter.strikeRate.toStringAsFixed(1),
                width: 44,
                muted: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCreaseRow extends StatelessWidget {
  const _ActionCreaseRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Material(
      color: c.pitchGreen,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColHeader extends StatelessWidget {
  const _ColHeader(this.text, {required this.width, required this.style});
  final String text;
  final double width;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(text, textAlign: TextAlign.right, style: style),
    );
  }
}

class _NumCell extends StatelessWidget {
  const _NumCell(
    this.text, {
    required this.width,
    this.bold = false,
    this.muted = false,
  });

  final String text;
  final double width;
  final bool bold;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              color: muted ? c.inkSecondary : c.inkPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
      ),
    );
  }
}
