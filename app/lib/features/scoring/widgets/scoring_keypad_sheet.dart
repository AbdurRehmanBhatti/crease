import 'package:flutter/material.dart';

import '../../../domain/models.dart';
import '../../../domain/stats_engine.dart';
import '../../../theme/crease_theme.dart';
import '../../../widgets/crease_ui.dart';
import '../../../widgets/glass_surface.dart';

/// Post-match summary & actions sheet that smoothly replaces the scoring keypad
/// once a match reaches [MatchStatus.completed], keeping Undo 1 tap away.
class MatchCompleteSheet extends StatelessWidget {
  const MatchCompleteSheet({
    super.key,
    required this.state,
    required this.onShare,
    required this.onViewScorecard,
    required this.onUndoLastBall,
    required this.onDone,
    this.onPlaySuperOver,
    this.onPlayerTap,
  });

  final DerivedMatchState state;
  final VoidCallback onShare;
  final VoidCallback onViewScorecard;
  final VoidCallback onUndoLastBall;
  final VoidCallback onDone;
  final VoidCallback? onPlaySuperOver;
  final ValueChanged<String>? onPlayerTap;

  PlayerCareerStats? _deriveMvp() {
    final all = StatsEngine.derive([state], excludeDemo: false);
    if (all.isEmpty) return null;
    all.sort((a, b) => b.mvpPoints.compareTo(a.mvpPoints));
    final top = all.first;
    return top.mvpPoints > 0 ? top : null;
  }

  String _formatMvpLine(PlayerCareerStats p) {
    final parts = <String>[];
    if (p.ballsFaced > 0 || p.runs > 0) {
      final star = p.notOuts > 0 ? '*' : '';
      parts.add('${p.runs}$star (${p.ballsFaced})');
    }
    if (p.wickets > 0) {
      parts.add('${p.wickets}/${p.runsConceded}');
    } else if (p.catches + p.stumpings + p.runOuts > 0 && parts.isEmpty) {
      final dism = p.catches + p.stumpings + p.runOuts;
      parts.add('$dism dismissal${dism == 1 ? '' : 's'}');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final mvp = _deriveMvp();
    final inningsList = [
      state.innings1,
      if (state.innings2 != null) state.innings2!,
      if (state.innings3 != null) state.innings3!,
      if (state.innings4 != null) state.innings4!,
    ];
    final scoresLine = inningsList.map((i) {
      final isSo = !state.config.isTestMatch && i.inningsNumber >= 3;
      return isSo
          ? '${i.battingTeam} SO ${i.scoreText} (${i.oversText})'
          : '${i.battingTeam} ${i.scoreText} (${i.oversText})';
    }).join('  ·  ');
    final isTournament = state.config.tournamentId != null;

    return GlassSurface(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(CreaseRadius.sheet),
      ),
      fillColor: c.surfaceSheet,
      borderColor: c.hairline,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.pitchGreenSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'FINAL',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: c.pitchGreen,
                        fontWeight: FontWeight.w800,
                        fontSize: 10.5,
                        letterSpacing: 0.7,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.resultSummary ?? 'Match complete',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            scoresLine,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: creaseNumeralStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: c.inkSecondary,
            ),
          ),
          if (mvp != null) ...[
            const SizedBox(height: 12),
            CreasePressable(
              onTap: onPlayerTap == null ? null : () => onPlayerTap!(mvp.name),
              borderRadius: BorderRadius.circular(CreaseRadius.control),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: c.surfaceKey,
                  borderRadius: BorderRadius.circular(CreaseRadius.control),
                  border: Border.all(color: c.hairlineSubtle),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c.pitchGreenSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.emoji_events_rounded,
                        size: 18,
                        color: c.pitchGreen,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PLAYER OF THE MATCH',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                  color: c.pitchGreen,
                                ),
                          ),
                          const SizedBox(height: 1),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  mvp.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (_formatMvpLine(mvp).isNotEmpty) ...[
                                Text(
                                  '  ·  ',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                Text(
                                  _formatMvpLine(mvp),
                                  style: creaseNumeralStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: c.inkSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (onPlayerTap != null)
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: c.inkSecondary,
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (onPlaySuperOver != null) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: c.inkPrimary,
                foregroundColor: c.ground,
                minimumSize: const Size.fromHeight(46),
              ),
              onPressed: onPlaySuperOver,
              icon: const Icon(Icons.bolt_rounded, size: 19),
              label: const Text('Play Super Over'),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.pitchGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: onShare,
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text('Share result'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: onViewScorecard,
                  icon: const Icon(Icons.table_chart_outlined, size: 18),
                  label: const Text('Scorecard'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: c.inkSecondary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: onUndoLastBall,
                icon: const Icon(Icons.undo_rounded, size: 17),
                label: const Text('Undo last ball'),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: c.inkPrimary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: onDone,
                icon: Icon(
                  isTournament
                      ? Icons.emoji_events_outlined
                      : Icons.check_rounded,
                  size: 17,
                ),
                label: Text(isTournament ? 'Back to tournament' : 'Done'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
