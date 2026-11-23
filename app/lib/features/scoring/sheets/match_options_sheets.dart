import 'package:flutter/material.dart';

import '../../../domain/models.dart';
import '../../../theme/crease_theme.dart';
import '../../../widgets/glass_surface.dart';

Future<MatchConfig?> showReviseMatchSheet(
  BuildContext context,
  DerivedMatchState state,
) {
  final oversCtrl = TextEditingController(text: '${state.config.oversLimit}');
  final currentTarget = state.innings2?.target ??
      state.config.firstInningsTargetOverride ??
      (state.innings1.isComplete ? state.innings1.totalRuns + 1 : null);
  final targetCtrl = TextEditingController(
    text: currentTarget != null ? '$currentTarget' : '',
  );

  return showModalBottomSheet<MatchConfig>(
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
}

Future<void> showMatchOptionsSheet(
  BuildContext context, {
  required VoidCallback onFiveRuns,
  required VoidCallback onPenaltyRuns,
  required VoidCallback onRetiredHurt,
  required VoidCallback onEndInnings,
  required VoidCallback onReviseRules,
  required VoidCallback onHandOver,
  required VoidCallback onAbandonMatch,
}) {
  return showModalBottomSheet<void>(
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
                    onFiveRuns();
                  },
                ),
                _OptionTile(
                  icon: Icons.flag_outlined,
                  title: '+5 Penalty',
                  subtitle: 'Dead-ball award',
                  onTap: () {
                    Navigator.pop(ctx);
                    onPenaltyRuns();
                  },
                ),
                _OptionTile(
                  icon: Icons.healing_outlined,
                  title: 'Retired hurt',
                  subtitle: 'No wicket lost',
                  onTap: () {
                    Navigator.pop(ctx);
                    onRetiredHurt();
                  },
                ),
                _OptionTile(
                  icon: Icons.stop_circle_outlined,
                  title: 'End innings',
                  subtitle: 'Close / declare',
                  onTap: () {
                    Navigator.pop(ctx);
                    onEndInnings();
                  },
                ),
                _OptionTile(
                  icon: Icons.thunderstorm_outlined,
                  title: 'Revise rules',
                  subtitle: 'Rain / target',
                  onTap: () {
                    Navigator.pop(ctx);
                    onReviseRules();
                  },
                ),
                _OptionTile(
                  icon: Icons.swap_horiz_rounded,
                  title: 'Hand over',
                  subtitle: 'Switch scorer',
                  onTap: () {
                    Navigator.pop(ctx);
                    onHandOver();
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
                onAbandonMatch();
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

Future<bool> confirmEndInningsDialog(
  BuildContext context,
  DerivedMatchState state,
) async {
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
  return ok == true;
}

Future<bool> confirmAbandonMatchDialog(BuildContext context) async {
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
  return ok == true;
}

Future<bool> confirmDeclareInningsDialog(
  BuildContext context,
  DerivedMatchState state,
) async {
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
  return ok == true;
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
