import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../data/local_event_store.dart';
import '../../domain/models.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/crease_ui.dart';
import '../auth/auth_sheet.dart';
import '../profile/player_profile_screen.dart';
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
  bool _syncing = false;
  bool _syncOffline = false;
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
    final hasUnsynced = events.any((e) => !e.synced);
    setState(() {
      _config = config;
      _events = events;
      _loading = false;
      if (!hasUnsynced) _syncOffline = false;
    });
    if (hasUnsynced && !_syncing) {
      _syncInBackground();
    }
  }

  Future<void> _syncInBackground({bool showFeedback = false}) async {
    if (_syncing) return;
    if (mounted) {
      setState(() => _syncing = true);
    }
    var totalSynced = 0;
    List<BallEvent> refreshed;
    int stillPending;
    while (true) {
      final synced =
          await LocalEventStore.instance.syncPendingToSupabase(widget.matchId);
      totalSynced += synced;
      refreshed = await LocalEventStore.instance.getBallEvents(widget.matchId);
      stillPending = refreshed.where((e) => !e.synced).length;
      // If new balls were recorded while a successful sync was in flight,
      // drain them right away instead of flagging offline.
      if (synced > 0 && stillPending > 0) {
        continue;
      }
      break;
    }
    if (!mounted) return;
    setState(() {
      _events = refreshed;
      _syncing = false;
      _syncOffline = stillPending > 0;
    });
    if (showFeedback) {
      if (stillPending == 0 && totalSynced > 0) {
        _showSnack(
          'Synced $totalSynced ball${totalSynced == 1 ? '' : 's'} to cloud.',
        );
      } else if (stillPending == 0) {
        _showSnack('Match is up to date.');
      } else {
        _showSnack('Still offline — saved locally, will sync when connected.');
      }
    }
  }

  DerivedMatchState? get _matchState {
    final config = _config;
    if (config == null) return null;
    return LocalEventStore.instance.deriveMatch(
      config,
      _events,
      forcedInnings: _forcedInnings,
      manualStrikerIdOverride: _manualStriker,
      manualNonStrikerIdOverride: _manualNonStriker,
      manualBowlerIdOverride: _manualBowler,
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
    if (inn.isComplete) return false;
    if (inn.currentBowler.isEmpty) return true;
    final curBalls =
        inn.overs.isNotEmpty ? inn.overs.last.balls : const <BallEvent>[];
    final overHasDelivery = curBalls.any(
      (b) =>
          b.extraType != ExtraType.penalty &&
          b.wicketType != WicketType.retiredHurt,
    );
    return inn.legalBalls > 0 &&
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
    String? dismissedBatterId,
    String? fielderId,
    String? nextBatterId,
  }) async {
    final state = _matchState;
    if (state == null) return;
    final inn = state.activeInnings;
    if (inn.isComplete) {
      _showSnack('Innings is complete. Start next innings or open Match Center.');
      return;
    }
    if (inn.strikerId.isEmpty) {
      await _openSelectNextBatterSheet(state, forNonStriker: false);
      return;
    }
    if (inn.nonStrikerId.isEmpty) {
      await _openSelectNextBatterSheet(state, forNonStriker: true);
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
      strikerId: inn.strikerId,
      nonStrikerId: inn.nonStrikerId,
      bowlerId: inn.currentBowlerId,
      runsOffBat: runsOffBat,
      extraType: extraType,
      extraRuns: extraRuns,
      isWicket: isWicket,
      wicketType: wicketType,
      dismissedBatterId: dismissedBatterId,
      fielderId: fielderId,
      nextBatterId: nextBatterId,
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
    _syncInBackground();

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
    _syncInBackground();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text('Undid last ball (${undone.shortMark})'),
          action: SnackBarAction(
            label: 'Redo',
            onPressed: () async {
              await LocalEventStore.instance.updateBallEvent(
                undone.copyWith(voided: false),
              );
              final restored =
                  await LocalEventStore.instance.getBallEvents(widget.matchId);
              if (!mounted) return;
              setState(() => _events = restored);
              _syncInBackground();
            },
          ),
        ),
      );
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
      _manualStriker = inn.nonStrikerId;
      _manualNonStriker = inn.strikerId;
    });
  }

  Future<void> _promptNewBowler(DerivedInningsState inn) async {
    final isOpeningBowler = inn.currentBowlerId.isEmpty;
    final picked = await showNextBowlerSheet(
      context,
      innings: inn,
      config: _config,
      playerNamesById: LocalEventStore.instance.directory.playerNamesById,
      title: isOpeningBowler
          ? 'Select opening bowler · ${inn.bowlingTeam}'
          : null,
      placeholderFallback: isOpeningBowler ? 'Bowler 1' : null,
    );
    if (picked != null && picked.isNotEmpty && mounted) {
      final res = await LocalEventStore.instance.addPlayerToMatchSide(
        widget.matchId,
        side: inn.bowlingSide,
        playerName: picked,
        addToOwnedSquad: !LocalEventStore.isPlaceholderPlayerName(picked),
      );
      var updatedCfg = res?.config;
      final pickedId = res?.playerId;
      if (pickedId != null &&
          isOpeningBowler &&
          (inn.inningsNumber == 1 || inn.inningsNumber == 2)) {
        final base = updatedCfg ?? _config;
        if (base != null) {
          updatedCfg = inn.inningsNumber == 1
              ? base.copyWith(openingBowler1Id: pickedId)
              : base.copyWith(openingBowler2Id: pickedId);
          await LocalEventStore.instance.saveMatch(updatedCfg);
        }
      }
      if (!mounted) return;
      setState(() {
        if (updatedCfg != null) _config = updatedCfg;
        _manualBowler = pickedId;
      });
    }
  }

  Future<void> _handleExtraTap(ExtraType type) async {
    await _openExtrasSheet(type);
  }

  Future<void> _openExtrasSheet(ExtraType type) async {
    final state = _matchState;
    if (state != null) {
      final inn = state.activeInnings;
      if (inn.needsNextBatter) {
        await _openSelectNextBatterSheet(
          state,
          forNonStriker: inn.striker.isNotEmpty && inn.nonStriker.isEmpty,
        );
        return;
      }
      if (_needsNewBowler(inn)) {
        await _promptNewBowler(inn);
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
      await _openSelectNextBatterSheet(
        state,
        forNonStriker: inn.striker.isNotEmpty && inn.nonStriker.isEmpty,
      );
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

    String? fielderId;
    final fielderName = result.finalFielder?.trim() ?? '';
    if (fielderName.isNotEmpty) {
      final res = await LocalEventStore.instance.addPlayerToMatchSide(
        widget.matchId,
        side: inn.bowlingSide,
        playerName: fielderName,
        addToOwnedSquad:
            result.customFielder.isNotEmpty &&
            !LocalEventStore.isPlaceholderPlayerName(fielderName),
      );
      fielderId = res?.playerId;
      if (res != null && mounted) {
        setState(() => _config = res.config);
      }
    }

    final dismissedBatterId =
        result.dismissedBatter == inn.nonStriker
            ? inn.nonStrikerId
            : inn.strikerId;

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
      dismissedBatterId: dismissedBatterId,
      fielderId: fielderId,
      nextBatterId: null,
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

  Future<bool> _togglePublicLive(DerivedMatchState state, bool goPublic) async {
    if (goPublic && !isSignedInAccount()) {
      final ok = await requireSignedInAccount(
        context,
        title: 'Sign in to broadcast live',
        subtitle:
            'Public matches sync live to the Crease Live tab under your account.',
      );
      if (!ok || !mounted) return state.config.isPublicLive;
    }
    final nextVis = goPublic
        ? BroadcastVisibility.public
        : BroadcastVisibility.unlisted;
    final updated = await LocalEventStore.instance.setMatchVisibility(
      state.config.id,
      nextVis,
    );
    if (!mounted) return goPublic;
    if (updated != null) {
      setState(() => _config = updated);
      _showSnack(
        goPublic
            ? 'Match is now public on the Live tab.'
            : 'Match switched to Unlisted (link only).',
      );
      return updated.isPublicLive;
    }
    return state.config.isPublicLive;
  }

  Future<void> _openMatchOptionsSheet(DerivedMatchState state) async {
    HapticFeedback.selectionClick();
    await showMatchOptionsSheet(
      context,
      isPublicLive: state.config.isPublicLive,
      onTogglePublicLive: (goPublic) => _togglePublicLive(state, goPublic),
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

  Future<void> _openSelectNextBatterSheet(
    DerivedMatchState state, {
    bool forNonStriker = false,
  }) async {
    final inn = state.activeInnings;
    final activeInningsEvents = _events
        .where((e) => !e.voided && e.inningsNumber == inn.inningsNumber)
        .toList();
    BallEvent? lastWicket;
    for (final e in activeInningsEvents.reversed) {
      if (e.isWicket && (e.nextBatterId == null || e.nextBatterId!.isEmpty)) {
        lastWicket = e;
        break;
      }
    }
    final isOpeningSlot = lastWicket == null && activeInningsEvents.isEmpty;
    final picked = await showNextBatterSheet(
      context,
      state,
      title: isOpeningSlot
          ? (forNonStriker
              ? 'Select non-striker · ${inn.battingTeam}'
              : 'Select striker · ${inn.battingTeam}')
          : null,
      placeholderFallback:
          isOpeningSlot ? (forNonStriker ? 'Batter 2' : 'Batter 1') : null,
    );
    if (picked == null || picked.isEmpty) return;

    final res = await LocalEventStore.instance.addPlayerToMatchSide(
      widget.matchId,
      side: inn.battingSide,
      playerName: picked,
      addToOwnedSquad: !LocalEventStore.isPlaceholderPlayerName(picked),
    );
    var updatedCfg = res?.config;
    final pickedId = res?.playerId;
    if (pickedId == null || pickedId.isEmpty) return;

    if (lastWicket != null) {
      await LocalEventStore.instance.updateBallEvent(
        lastWicket.copyWith(nextBatterId: pickedId),
      );
    } else if (isOpeningSlot &&
        (inn.inningsNumber == 1 || inn.inningsNumber == 2)) {
      final base = updatedCfg ?? _config;
      if (base != null) {
        if (inn.inningsNumber == 1) {
          updatedCfg = forNonStriker
              ? base.copyWith(openingNonStriker1Id: pickedId)
              : base.copyWith(openingStriker1Id: pickedId);
        } else {
          updatedCfg = forNonStriker
              ? base.copyWith(openingNonStriker2Id: pickedId)
              : base.copyWith(openingStriker2Id: pickedId);
        }
        await LocalEventStore.instance.saveMatch(updatedCfg);
      }
    }

    final updatedEvents =
        await LocalEventStore.instance.getBallEvents(widget.matchId);
    if (!mounted) return;
    setState(() {
      if (updatedCfg != null) _config = updatedCfg;
      _events = updatedEvents;
      if (isOpeningSlot && inn.inningsNumber >= 3) {
        if (forNonStriker) {
          _manualNonStriker = pickedId;
        } else {
          _manualStriker = pickedId;
        }
      }
    });
    _syncInBackground();
  }

  Future<void> _openEditBallSheet(BallEvent ball) async {
    HapticFeedback.selectionClick();
    final names = _matchState?.resolvedPlayerNames ??
        LocalEventStore.instance.directory.playerNamesById;
    final action = await showEditBallSheet(
      context,
      ball,
      playerNamesById: names,
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
    _syncInBackground();
    _showSnack('Ball updated. Scorecard recalculated.');
  }

  Future<void> _startSuperOver(
    DerivedMatchState state, {
    int targetInnings = 3,
  }) async {
    final cfg = state.config;
    // ICC Super Over rule: team that batted 2nd in regulation bats 1st (inn 3);
    // team that batted 1st in regulation chases (inn 4).
    final batFirstSide =
        targetInnings == 3 ? cfg.battingSecondSide : cfg.battingFirstSide;
    final batSecondSide =
        targetInnings == 3 ? cfg.battingFirstSide : cfg.battingSecondSide;
    final batFirst = cfg.teamNameForSide(batFirstSide);
    final batSecond = cfg.teamNameForSide(batSecondSide);

    List<String> mergeTeamPlayers(MatchSide side) {
      final seen = <String>{};
      final out = <String>[];
      void add(String name) {
        final t = name.trim();
        if (t.isEmpty || LocalEventStore.isPlaceholderPlayerName(t)) return;
        if (seen.add(t.toLowerCase())) out.add(t);
      }
      for (final id in cfg.rosterIdsForSide(side)) {
        add(state.resolvedPlayerNames[id] ?? '');
      }
      for (final inn in state.allInnings) {
        if (inn.battingSide == side) {
          for (final b in inn.batters) {
            add(b.name);
          }
        }
        if (inn.bowlingSide == side) {
          for (final bw in inn.bowlers) {
            add(bw.name);
          }
        }
      }
      return out;
    }

    final batFirstRoster = mergeTeamPlayers(batFirstSide);
    final batSecondRoster = mergeTeamPlayers(batSecondSide);

    var striker =
        batFirstRoster.isNotEmpty ? batFirstRoster[0] : 'Batter 1';
    var nonStriker =
        batFirstRoster.length > 1 ? batFirstRoster[1] : 'Batter 2';
    var bowler =
        batSecondRoster.isNotEmpty ? batSecondRoster[0] : 'Bowler 1';

    Future<String?> pickPlayer({
      required BuildContext sheetCtx,
      required String title,
      required String current,
      required List<String> roster,
      String? excludeName,
    }) async {
      final candidates = roster
          .where(
            (p) =>
                excludeName == null ||
                p.toLowerCase() != excludeName.toLowerCase(),
          )
          .toList();
      if (candidates.isEmpty) {
        return _promptCustomSuperOverPlayer(sheetCtx, title, current);
      }
      const customSentinel = '__custom__';
      final picked = await showCreaseOptionPicker<String>(
        sheetCtx,
        title: title,
        selectedValue: candidates.contains(current) ? current : '',
        options: [
          for (final p in candidates) (value: p, label: p, subtitle: null),
          const (
            value: customSentinel,
            label: '+ Add player',
            subtitle: 'Someone not in this squad',
          ),
        ],
      );
      if (picked == null) return null;
      if (picked == customSentinel) {
        if (!sheetCtx.mounted) return null;
        return _promptCustomSuperOverPlayer(sheetCtx, title, '');
      }
      return picked;
    }

    final targetRuns =
        targetInnings == 4 && state.innings3 != null ? state.innings3!.totalRuns + 1 : null;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Widget selectorRow({
              required String label,
              required String value,
              required VoidCallback onTap,
            }) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                          color: c.inkSecondary,
                        ),
                  ),
                  const SizedBox(height: 6),
                  CreasePressable(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(CreaseRadius.control),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: c.surfaceKey,
                        borderRadius:
                            BorderRadius.circular(CreaseRadius.control),
                        border: Border.all(color: c.hairline),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(ctx).textTheme.bodyLarge,
                            ),
                          ),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: c.inkSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            return Container(
              decoration: BoxDecoration(
                color: c.surfaceSheet,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(CreaseRadius.sheet),
                ),
                border: Border.all(color: c.hairline),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                14,
                20,
                20 + MediaQuery.paddingOf(ctx).bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CreaseSheetHeader(
                      title: targetInnings == 3
                          ? 'Super Over'
                          : 'Super Over Chase',
                      subtitle: targetInnings == 3
                          ? '1 over · 2 wickets all-out · $batFirst bats first'
                          : '$batFirst need ${targetRuns ?? 1} in 1 over · 2 wickets',
                    ),
                    const SizedBox(height: 14),
                    selectorRow(
                      label: '$batFirst — Striker',
                      value: striker,
                      onTap: () async {
                        final chosen = await pickPlayer(
                          sheetCtx: ctx,
                          title: '$batFirst — Striker',
                          current: striker,
                          roster: batFirstRoster,
                          excludeName: nonStriker,
                        );
                        if (chosen != null) {
                          setModalState(() => striker = chosen);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    selectorRow(
                      label: '$batFirst — Non-striker',
                      value: nonStriker,
                      onTap: () async {
                        final chosen = await pickPlayer(
                          sheetCtx: ctx,
                          title: '$batFirst — Non-striker',
                          current: nonStriker,
                          roster: batFirstRoster,
                          excludeName: striker,
                        );
                        if (chosen != null) {
                          setModalState(() => nonStriker = chosen);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    selectorRow(
                      label: '$batSecond — Bowler',
                      value: bowler,
                      onTap: () async {
                        final chosen = await pickPlayer(
                          sheetCtx: ctx,
                          title: '$batSecond — Bowler',
                          current: bowler,
                          roster: batSecondRoster,
                        );
                        if (chosen != null) {
                          setModalState(() => bowler = chosen);
                        }
                      },
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: c.pitchGreen,
                        foregroundColor: c.onPitchGreen,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.bolt_rounded, size: 19),
                      label: Text(
                        targetInnings == 3
                            ? 'Start Super Over'
                            : 'Start Super Over chase',
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final sRes = await LocalEventStore.instance.addPlayerToMatchSide(
      widget.matchId,
      side: batFirstSide,
      playerName: striker,
      addToOwnedSquad: !LocalEventStore.isPlaceholderPlayerName(striker),
    );
    final nsRes = await LocalEventStore.instance.addPlayerToMatchSide(
      widget.matchId,
      side: batFirstSide,
      playerName: nonStriker,
      addToOwnedSquad: !LocalEventStore.isPlaceholderPlayerName(nonStriker),
    );
    final bwRes = await LocalEventStore.instance.addPlayerToMatchSide(
      widget.matchId,
      side: batSecondSide,
      playerName: bowler,
      addToOwnedSquad: !LocalEventStore.isPlaceholderPlayerName(bowler),
    );
    if (!mounted) return;
    setState(() {
      if (bwRes != null) _config = bwRes.config;
      _forcedInnings = targetInnings;
      _manualStriker = sRes?.playerId;
      _manualNonStriker = nsRes?.playerId;
      _manualBowler = bwRes?.playerId;
    });
  }

  Future<String?> _promptCustomSuperOverPlayer(
    BuildContext context,
    String title,
    String initial,
  ) async {
    final ctrl = TextEditingController(text: initial);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Player name'),
          onSubmitted: (v) {
            final t = v.trim();
            if (t.isNotEmpty) Navigator.pop(ctx, t);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return res;
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
    _syncInBackground();
  }

  Future<void> _enforceFollowOn(DerivedMatchState state) async {
    final updated = state.config.copyWith(followOnEnforced: true);
    await LocalEventStore.instance.saveMatch(updated);
    if (!mounted) return;
    setState(() {
      _config = updated;
      _forcedInnings = 3;
    });
    _syncInBackground();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _isGuestAccount => !isSignedInAccount();

  Future<void> _openProfileToBackup() async {
    final done = await showCreaseAuthSheet(
      context,
      title: 'Back up your match',
      subtitle:
          'Sign in to save this scorecard, get a live share link, and keep your career stats.',
    );
    if (done != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;

    if (_loading) {
      return Scaffold(
        backgroundColor: c.ground,
        body: const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CreaseSkeletonBox(height: 44),
                SizedBox(height: 24),
                CreaseSkeletonBox(height: 92),
                SizedBox(height: 18),
                CreaseSkeletonBox(height: 160),
                Spacer(),
                CreaseSkeletonBox(height: 240),
              ],
            ),
          ),
        ),
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
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 1. Top App Bar
            TopMatchBar(
              title: state.config.title,
              formatLabel: state.config.formatLabel,
              isLive: state.status == MatchStatus.live,
              isPublicLive: state.config.isPublicLive,
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

            // 1b. Offline / pending-sync status pill (signed-in accounts only)
            ScoringSyncPill(
              unsyncedCount: state.unsyncedCount,
              isSyncing: _syncing,
              showOffline: !_isGuestAccount && _syncOffline,
              onRetry: () => _syncInBackground(showFeedback: true),
            ),

            // 2. Scoreboard Area (scrollable safeguard for large font scales)
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
                          // Monumental scoreboard + right-aligned chase stack
                          Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          CreaseTeamBadge(
                                            name: inn.battingTeam,
                                            teamId: _config?.teamIdForSide(
                                              inn.battingSide,
                                            ),
                                            size: 22,
                                            highlighted: true,
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              inn.battingTeam,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    color: c.pitchGreen,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ),
                                          if (!state.config.isTestMatch &&
                                              inn.inningsNumber >= 3) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: c.pitchGreenSoft,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'SUPER OVER',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelMedium
                                                    ?.copyWith(
                                                      fontSize: 9.5,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: 0.5,
                                                      color: c.pitchGreen,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: AnimatedSwitcher(
                                          duration: MediaQuery
                                                  .disableAnimationsOf(context)
                                              ? Duration.zero
                                              : const Duration(
                                                  milliseconds: 140,
                                                ),
                                          child: Text.rich(
                                            key: ValueKey(
                                              '${inn.totalRuns}/${inn.wickets}',
                                            ),
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: '${inn.totalRuns}',
                                                  style: creaseNumeralStyle(
                                                    fontSize: 60,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: -1.6,
                                                    height: 0.98,
                                                    color: c.inkPrimary,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: '/${inn.wickets}',
                                                  style: creaseNumeralStyle(
                                                    fontSize: 46,
                                                    fontWeight: FontWeight.w500,
                                                    letterSpacing: -0.8,
                                                    height: 0.98,
                                                    color: c.inkSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${inn.oversText}${inn.oversLimit > 0 ? ' / ${inn.oversLimit}' : ''} ov · Extras ${inn.wides + inn.noBalls + inn.byes + inn.legByes}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(fontSize: 13),
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

                          // Live Crease Table (Batters + Bowler)
                          LiveCreaseCard(
                            strikerEmpty: inn.striker.isEmpty,
                            nonStrikerEmpty: inn.nonStriker.isEmpty,
                            striker: strikerStats,
                            nonStriker: nonStrikerStats,
                            bowler: bowlerStats,
                            needsNewBowler: _needsNewBowler(inn),
                            isOpeningSelection:
                                inn.legalBalls == 0 && inn.wickets == 0,
                            onSwapStrike: _swapStrike,
                            onSelectNextBatter: () =>
                                _openSelectNextBatterSheet(
                              state,
                              forNonStriker: false,
                            ),
                            onSelectNonStriker: () =>
                                _openSelectNextBatterSheet(
                              state,
                              forNonStriker: true,
                            ),
                            onSelectNextBowler: () => _promptNewBowler(inn),
                          ),

                          // Horizontal over timeline
                          OverTimeline(
                            previousOver: previousOver,
                            currentOver: currentOver,
                            recentWicket: recentWicket,
                            hideEmptySlots:
                                state.status == MatchStatus.completed,
                            playerNamesById: state.resolvedPlayerNames,
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

                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // 3. Raised Scoring Pad / Innings Break / Match Complete / Handed Over
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _handedOverToOther
                  ? HandedOverSheet(
                      key: const ValueKey('handed-over'),
                      reclaiming: _reclaiming,
                      onReclaim: _reclaimScoring,
                    )
                  : state.status == MatchStatus.inningsBreak
                      ? InningsBreakSheet(
                          key: const ValueKey('innings-break'),
                          state: state,
                          onStartNextInnings: () {
                            if (!state.config.isTestMatch &&
                                state.activeInningsNumber == 3) {
                              _startSuperOver(state, targetInnings: 4);
                              return;
                            }
                            setState(
                              () => _forcedInnings =
                                  state.activeInningsNumber + 1,
                            );
                          },
                          onHandOver: () =>
                              showHandOverScoringSheet(context, state),
                          onEnforceFollowOn: state.canEnforceFollowOn
                              ? () => _enforceFollowOn(state)
                              : null,
                          onUndoLastBall: _undoLastBall,
                        )
                  : state.status == MatchStatus.completed
                      ? MatchCompleteSheet(
                          key: const ValueKey('match-complete'),
                          state: state,
                          onPlaySuperOver: !state.config.isTestMatch &&
                                  state.innings3 == null &&
                                  (state.resultSummary?.toLowerCase() ==
                                      'match tied')
                              ? () => _startSuperOver(state, targetInnings: 3)
                              : null,
                          onShare: () => _shareMatchSummary(state),
                          onViewScorecard: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ScorecardScreen(matchId: widget.matchId),
                              ),
                            );
                            _load();
                          },
                          onUndoLastBall: _undoLastBall,
                          onDone: () => Navigator.of(context).maybePop(),
                          onPlayerTap: (name) {
                            String? tappedPid;
                            for (final e in state.resolvedPlayerNames.entries) {
                              if (e.value == name) {
                                tappedPid = e.key;
                                break;
                              }
                            }
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PlayerProfileScreen(
                                  playerName: name,
                                  playerId: tappedPid,
                                ),
                              ),
                            );
                          },
                          onSignInToBackup:
                              _isGuestAccount ? _openProfileToBackup : null,
                        )
                      : GlassScoringSheet(
                          key: const ValueKey('keypad'),
                          onRunTap: (runs) => _recordBall(runsOffBat: runs),
                          onExtraTap: _handleExtraTap,
                          onExtraLongPress: _openExtrasSheet,
                          onWicketTap: () => _openWicketSheet(),
                          onRunOutTap: () => _openWicketSheet(
                            initialType: WicketType.runOut,
                          ),
                          onUndoTap: _undoLastBall,
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
