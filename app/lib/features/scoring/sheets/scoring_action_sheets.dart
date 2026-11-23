import 'package:flutter/material.dart';

import '../../../domain/models.dart';
import '../../../theme/crease_theme.dart';
import '../../../widgets/glass_surface.dart';
import '../widgets/scoring_keypad_sheet.dart';

class WicketSheetResult {
  const WicketSheetResult({
    required this.wicketType,
    required this.deliveryExtra,
    required this.completedRuns,
    required this.dismissedBatter,
    required this.selectedFielder,
    required this.customFielder,
  });

  final WicketType wicketType;
  final ExtraType deliveryExtra;
  final int completedRuns;
  final String dismissedBatter;
  final String? selectedFielder;
  final String customFielder;

  String? get finalFielder =>
      customFielder.isNotEmpty ? customFielder : selectedFielder;
}

Future<String?> showNextBowlerSheet(
  BuildContext context, {
  required DerivedInningsState innings,
  required MatchConfig? config,
}) async {
  final controller = TextEditingController();
  final rosterSet = <String>{
    if (config != null) ...config.rosterForTeam(innings.bowlingTeam),
    ...innings.bowlers.map((b) => b.name),
  }..remove(innings.currentBowler);
  final availableBowlers = rosterSet.toList();

  return showModalBottomSheet<String>(
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
                'Select next bowler · ${innings.bowlingTeam}',
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
              if (innings.legalBalls > 0 && innings.currentBowler.isNotEmpty) ...[
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
                        '${innings.currentBowler} · ${innings.bowlerByName(innings.currentBowler).figuresText}',
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
                    text.isEmpty ? 'Bowler ${innings.bowlers.length + 1}' : text,
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
}

Future<int?> showExtrasRunsSheet(BuildContext context, ExtraType type) {
  final isPenaltyExtra = type == ExtraType.wide || type == ExtraType.noBall;
  final options = switch (type) {
    ExtraType.noBall => [0, 1, 2, 3, 4, 6],
    ExtraType.wide => [0, 1, 2, 3, 4],
    _ => [1, 2, 3, 4],
  };

  return showModalBottomSheet<int>(
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
                        child: KeypadButton(
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
                            child: KeypadButton(
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
                            child: KeypadButton(
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
}

Future<WicketSheetResult?> showRecordWicketSheet(
  BuildContext context,
  DerivedMatchState state, {
  WicketType initialType = WicketType.caught,
}) {
  final inn = state.activeInnings;
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

  return showModalBottomSheet<WicketSheetResult>(
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
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: GlassSurface(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
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
                      onPressed: () => Navigator.pop(
                        ctx,
                        WicketSheetResult(
                          wicketType: selectedType,
                          deliveryExtra: deliveryExtra,
                          completedRuns: completedRuns,
                          dismissedBatter: dismissed,
                          selectedFielder: selectedFielder,
                          customFielder: customFielderCtrl.text.trim(),
                        ),
                      ),
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
}

Future<String?> showNextBatterSheet(
  BuildContext context,
  DerivedMatchState state,
) {
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
  final disabledPlayers = roster.where((p) => unavailable.contains(p)).toList();

  final newBatterCtrl = TextEditingController();

  return showModalBottomSheet<String>(
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
}

Future<String?> showEditBallSheet(BuildContext context, BallEvent ball) {
  return showModalBottomSheet<String>(
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
            Text(
              'Change runs off bat:',
              style: Theme.of(ctx).textTheme.labelMedium,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final r in [0, 1, 2, 3, 4, 6])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: KeypadButton(
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
}
