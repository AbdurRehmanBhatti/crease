import 'package:flutter/material.dart';

import '../../../domain/models.dart';
import '../../../theme/crease_theme.dart';
import '../../../widgets/glass_surface.dart';

class HandedOverSheet extends StatelessWidget {
  const HandedOverSheet({
    super.key,
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

class GlassScoringSheet extends StatelessWidget {
  const GlassScoringSheet({
    super.key,
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
              Expanded(child: KeypadButton(label: '0', onTap: () => onRunTap(0))),
              const SizedBox(width: 10),
              Expanded(child: KeypadButton(label: '1', onTap: () => onRunTap(1))),
              const SizedBox(width: 10),
              Expanded(child: KeypadButton(label: '2', onTap: () => onRunTap(2))),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: 3, 4 (green), 6 (green)
          Row(
            children: [
              Expanded(child: KeypadButton(label: '3', onTap: () => onRunTap(3))),
              const SizedBox(width: 10),
              Expanded(
                child: KeypadButton(
                  label: '4',
                  isAccent: true,
                  onTap: () => onRunTap(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: KeypadButton(
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

class KeypadButton extends StatelessWidget {
  const KeypadButton({
    super.key,
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
