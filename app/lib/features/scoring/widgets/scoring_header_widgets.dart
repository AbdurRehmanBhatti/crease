import 'package:flutter/material.dart';

import '../../../domain/models.dart';
import '../../../theme/crease_theme.dart';

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

class OverTimeline extends StatelessWidget {
  const OverTimeline({
    super.key,
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
