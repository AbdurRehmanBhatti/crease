import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models.dart';
import '../../../theme/crease_theme.dart';
import '../../../widgets/crease_ui.dart';

/// Compact, unobtrusive offline / sync pill shown directly below [TopMatchBar]
/// only when local ball events are pending cloud upload after a sync attempt.
/// Takes zero height when online & synced so there is no flicker during scoring.
class ScoringSyncPill extends StatelessWidget {
  const ScoringSyncPill({
    super.key,
    required this.unsyncedCount,
    required this.isSyncing,
    required this.showOffline,
    required this.onRetry,
  });

  final int unsyncedCount;
  final bool isSyncing;
  final bool showOffline;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final visible = showOffline && unsyncedCount > 0;

    return AnimatedSize(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: visible
          ? Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
              child: Center(
                child: Semantics(
                  button: true,
                  label: isSyncing
                      ? 'Syncing match to cloud'
                      : 'Saved offline, $unsyncedCount pending. Tap to retry sync.',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(CreaseRadius.pill),
                    onTap: isSyncing
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            onRetry();
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: c.pillMutedBg,
                          borderRadius:
                              BorderRadius.circular(CreaseRadius.pill),
                          border: Border.all(color: c.hairlineSubtle),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSyncing) ...[
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                  color: c.pitchGreen,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                'Syncing…',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      fontSize: 11.5,
                                      color: c.inkSecondary,
                                    ),
                              ),
                            ] else ...[
                              Icon(
                                Icons.cloud_off_rounded,
                                size: 13.5,
                                color: c.inkSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Saved offline · $unsyncedCount pending',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      fontSize: 11.5,
                                      color: c.inkSecondary,
                                    ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Retry',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: c.pitchGreen,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class TopMatchBar extends StatelessWidget {
  const TopMatchBar({
    super.key,
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
      padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
            onPressed: onBack,
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(CreaseRadius.control),
              onTap: onScorecard,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isLive) ...[
                      const CreaseLiveDot(size: 7),
                      const SizedBox(width: 7),
                    ],
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
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
                              fontSize: 10.5,
                              color: c.inkPrimary,
                              fontWeight: FontWeight.w700,
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
            icon: const Icon(Icons.table_chart_outlined, size: 20),
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

class ChaseOrRateStack extends StatelessWidget {
  const ChaseOrRateStack({
    super.key,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: c.pitchGreenSoft,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Final',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: c.pitchGreen,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
            ),
          ),
          const SizedBox(height: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 148),
            child: Text(
              resultSummary!,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      );
    }

    if (isTestMatch) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'Innings ${innings.inningsNumber}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 3),
          if (leadTrailText != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 148),
              child: Text(
                leadTrailText!,
                textAlign: TextAlign.right,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 3),
          Text(
            'CRR ${innings.currentRunRate.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.bodySmall,
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
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                TextSpan(
                  text: '${innings.runsNeeded}',
                  style: creaseNumeralStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: c.inkPrimary,
                  ),
                ),
              ],
            ),
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'off ',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                TextSpan(
                  text: '${innings.ballsRemaining}',
                  style: creaseNumeralStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: c.inkPrimary,
                  ),
                ),
                TextSpan(
                  text: innings.ballsRemaining == 1 ? ' ball' : ' balls',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: c.pillMutedBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              rrr == null ? 'RRR -' : 'RRR ${rrr.toStringAsFixed(1)}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: c.inkPrimary,
                    fontSize: 11.5,
                  ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '1st innings',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'CRR ',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              innings.currentRunRate.toStringAsFixed(2),
              style: creaseNumeralStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: c.inkPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${innings.ballsRemaining} ball${innings.ballsRemaining == 1 ? '' : 's'} left',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class OverTimeline extends StatelessWidget {
  const OverTimeline({
    super.key,
    required this.previousOver,
    required this.currentOver,
    required this.recentWicket,
    required this.onBallTap,
    this.hideEmptySlots = false,
  });

  final OverSummary? previousOver;
  final OverSummary? currentOver;
  final BallEvent? recentWicket;
  final ValueChanged<BallEvent> onBallTap;
  final bool hideEmptySlots;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final currentBalls = currentOver?.balls ?? const <BallEvent>[];
    final legalCount = currentOver?.legalBallsInOver ?? 0;
    final emptySlots = hideEmptySlots ? 0 : (6 - legalCount).clamp(0, 6);

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
                  opacity: 0.45,
                  child: Row(
                    children: [
                      Text(
                        'Ov ${previousOver!.overNumber}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
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
                Container(
                  width: 1,
                  height: 18,
                  margin: const EdgeInsets.only(left: 2, right: 10),
                  color: c.hairline,
                ),
              ],
              if (currentOver != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: c.pillMutedBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Ov ${currentOver!.overNumber}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: c.inkPrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              for (final b in currentBalls)
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: _BallCircle(
                    ball: b,
                    onTap: () => onBallTap(b),
                  ),
                ),
              for (var i = 0; i < emptySlots; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.surfaceGlass.withValues(alpha: 0.5),
                      border: Border.all(color: c.hairline, width: 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (recentWicket?.dismissalSummary != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: c.wicketRedSoft,
              borderRadius: BorderRadius.circular(CreaseRadius.badge),
            ),
            child: Text(
              recentWicket!.dismissalSummary!,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: c.wicketRed,
                    fontWeight: FontWeight.w600,
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
      fg = c.onWicketRed;
    } else if (isBoundary) {
      bg = c.pitchGreenSoft;
      border = c.pitchGreen;
      fg = c.pitchGreen;
    }

    return Semantics(
      button: true,
      label: 'Edit delivery ${ball.shortMark}',
      child: CreasePressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        scale: 0.9,
        child: SizedBox(
          width: 40,
          height: 48,
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(color: border, width: 1.1),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  ball.shortMark,
                  style: creaseNumeralStyle(
                    fontSize: ball.shortMark.length > 2 ? 10.5 : 14,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
