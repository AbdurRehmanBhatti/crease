import 'package:flutter/material.dart';

import '../../../domain/models.dart';
import '../../../theme/crease_theme.dart';
import '../../../widgets/crease_ui.dart';
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
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(CreaseRadius.sheet),
      ),
      fillColor: c.surfaceSheet,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const CreaseLiveDot(size: 8),
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
            'Deliveries are syncing live. Reclaim control here whenever you want to take over.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final padBg = isDark ? const Color(0xFF121619) : const Color(0xFFEEF1F4);
    final keyBg = isDark ? const Color(0xFF1D2227) : Colors.white;

    return GlassSurface(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(CreaseRadius.sheet),
      ),
      fillColor: padBg,
      borderColor: c.hairline,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: 0, 1, 2
          Row(
            children: [
              Expanded(child: KeypadButton(label: '0', onTap: () => onRunTap(0))),
              const SizedBox(width: 8),
              Expanded(child: KeypadButton(label: '1', onTap: () => onRunTap(1))),
              const SizedBox(width: 8),
              Expanded(child: KeypadButton(label: '2', onTap: () => onRunTap(2))),
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: 3, 4 (green), 6 (green)
          Row(
            children: [
              Expanded(child: KeypadButton(label: '3', onTap: () => onRunTap(3))),
              const SizedBox(width: 8),
              Expanded(
                child: KeypadButton(
                  label: '4',
                  isAccent: true,
                  onTap: () => onRunTap(4),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: KeypadButton(
                  label: '6',
                  isAccent: true,
                  onTap: () => onRunTap(6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 3: 4-segment extras bar (Wide | No ball | Bye | Leg bye)
          Container(
            height: 46,
            decoration: BoxDecoration(
              color: keyBg,
              borderRadius: BorderRadius.circular(CreaseRadius.control),
              border: Border.all(color: c.hairline, width: 1),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: const Color(0xFF101315).withValues(alpha: 0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 1.5),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CreaseRadius.control - 1),
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
          const SizedBox(height: 10),

          // Row 4: Balanced tactile action bar (Wicket | Run out | Undo)
          Row(
            children: [
              Expanded(
                flex: 3,
                child: CreasePressable(
                  onTap: onWicketTap,
                  borderRadius: BorderRadius.circular(CreaseRadius.control),
                  scale: 0.96,
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.wicketRed,
                      borderRadius: BorderRadius.circular(CreaseRadius.control),
                    ),
                    child: const Text(
                      'Wicket',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: CreasePressable(
                  onTap: onRunOutTap,
                  borderRadius: BorderRadius.circular(CreaseRadius.control),
                  scale: 0.96,
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.wicketRedSoft,
                      borderRadius: BorderRadius.circular(CreaseRadius.control),
                      border: Border.all(
                        color: c.wicketRed.withValues(alpha: 0.28),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      'Run out',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: c.wicketRed,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CreasePressable(
                onTap: onUndoTap,
                borderRadius: BorderRadius.circular(CreaseRadius.control),
                scale: 0.95,
                child: Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: keyBg,
                    borderRadius: BorderRadius.circular(CreaseRadius.control),
                    border: Border.all(color: c.hairline, width: 1),
                    boxShadow: isDark
                        ? null
                        : [
                            BoxShadow(
                              color:
                                  const Color(0xFF101315).withValues(alpha: 0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 1.5),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.undo_rounded,
                        size: 18,
                        color: c.inkPrimary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Undo',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
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
    final bg = isAccent
        ? c.pitchGreen
        : (isDark ? const Color(0xFF1D2227) : Colors.white);
    final fg = isAccent ? Colors.white : c.inkPrimary;

    return CreasePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CreaseRadius.control),
      scale: 0.94,
      child: Container(
        height: 60,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(CreaseRadius.control),
          border: Border.all(
            color: isAccent ? c.pitchGreen : c.hairline,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : const Color(0xFF101315))
                  .withValues(alpha: isDark ? 0.28 : (isAccent ? 0.10 : 0.055)),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: creaseNumeralStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: fg,
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
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ),
    );
  }
}
