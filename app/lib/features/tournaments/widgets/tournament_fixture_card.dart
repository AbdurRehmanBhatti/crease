import 'package:flutter/material.dart';

import '../../../domain/models.dart';
import '../../../domain/stats_engine.dart';
import '../../../domain/tournament_engine.dart';
import '../../../theme/crease_theme.dart';
import '../../../widgets/crease_ui.dart';
import '../../../widgets/glass_surface.dart';

bool isUnstartedLiveMatch(DerivedMatchState? match) {
  if (match == null || match.status != MatchStatus.live) return false;
  return match.innings1.totalRuns == 0 &&
      match.innings1.wickets == 0 &&
      match.innings1.legalBalls == 0 &&
      match.innings2 == null;
}

class TournamentChampionBanner extends StatelessWidget {
  const TournamentChampionBanner({
    super.key,
    required this.champion,
    this.mvp,
  });

  final String champion;
  final PlayerCareerStats? mvp;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return GlassSurface(
      borderColor: c.pitchGreen.withValues(alpha: 0.4),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.pitchGreen,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tournament champion',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: c.pitchGreen,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  champion,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (mvp != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Tournament MVP · ${mvp!.name} (${mvp!.mvpPoints} pts)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TournamentFixtureCard extends StatelessWidget {
  const TournamentFixtureCard({
    super.key,
    required this.fixture,
    required this.onTap,
    this.onDiscardLiveMatch,
  });

  final ScheduledFixture fixture;
  final VoidCallback onTap;
  final VoidCallback? onDiscardLiveMatch;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final match = fixture.match;
    final isLocked = fixture.lockedReason != null && match == null;
    final winner = match != null ? TournamentEngine.winnerOf(match) : null;

    String? scoreFor(String teamName) {
      if (match == null) return null;
      if (match.innings1.battingTeam.toLowerCase() == teamName.toLowerCase()) {
        return '${match.innings1.scoreText} (${match.innings1.oversText})';
      }
      final inn2 = match.innings2;
      if (inn2 != null &&
          inn2.battingTeam.toLowerCase() == teamName.toLowerCase() &&
          (inn2.legalBalls > 0 || inn2.isDeclared)) {
        return '${inn2.scoreText} (${inn2.oversText})';
      }
      return null;
    }

    final teamA = fixture.displayTeamA;
    final teamB = fixture.displayTeamB;
    final scoreA = fixture.teamA != null ? scoreFor(fixture.teamA!) : null;
    final scoreB = fixture.teamB != null ? scoreFor(fixture.teamB!) : null;

    Widget statusPill() {
      if (fixture.isLive) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CreaseLiveDot(size: 6),
            const SizedBox(width: 5),
            Text(
              'Live',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: c.pitchGreen,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        );
      }
      if (fixture.isCompleted) {
        return Text(
          'Result',
          style: Theme.of(context).textTheme.labelMedium,
        );
      }
      if (isLocked) {
        return Icon(Icons.lock_outline_rounded, size: 15, color: c.inkSecondary);
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.pitchGreenSoft,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'Play',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontSize: 11,
                color: c.pitchGreen,
                fontWeight: FontWeight.w700,
              ),
        ),
      );
    }

    return CreasePressable(
      onTap: isLocked ? null : onTap,
      child: GlassSurface(
        fillColor: isLocked ? c.surfaceKey : null,
        borderColor: fixture.isLive
            ? c.pitchGreen.withValues(alpha: 0.45)
            : isLocked
                ? c.hairlineSubtle
                : null,
        padding: const EdgeInsets.fromLTRB(15, 12, 15, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  fixture.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: fixture.stage == MatchStage.finalMatch
                            ? c.pitchGreen
                            : c.inkSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                statusPill(),
                if (onDiscardLiveMatch != null) ...[
                  const SizedBox(width: 4),
                  CreaseMenuButton<String>(
                    compact: true,
                    icon: Icons.more_horiz_rounded,
                    iconSize: 18,
                    tooltip: 'Match options',
                    sheetTitle: fixture.label,
                    onSelected: (v) {
                      if (v == 'discard') onDiscardLiveMatch!();
                    },
                    items: const [
                      CreaseMenuItem(
                        value: 'discard',
                        label: 'Discard unstarted match',
                        subtitle: 'Returns this fixture to upcoming',
                        icon: Icons.delete_outline_rounded,
                        isDestructive: true,
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            _FixtureTeamRow(
              name: teamA,
              hasRealTeam: fixture.teamA != null,
              score: scoreA,
              isWinner:
                  winner != null && winner.toLowerCase() == teamA.toLowerCase(),
              isLoser:
                  winner != null && winner.toLowerCase() != teamA.toLowerCase(),
            ),
            const SizedBox(height: 7),
            _FixtureTeamRow(
              name: teamB,
              hasRealTeam: fixture.teamB != null,
              score: scoreB,
              isWinner:
                  winner != null && winner.toLowerCase() == teamB.toLowerCase(),
              isLoser:
                  winner != null && winner.toLowerCase() != teamB.toLowerCase(),
            ),
            if (match?.resultSummary != null) ...[
              const SizedBox(height: 9),
              Divider(height: 1, color: c.hairlineSubtle),
              const SizedBox(height: 8),
              Text(
                match!.resultSummary!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: c.pitchGreen,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ] else if (isLocked) ...[
              const SizedBox(height: 8),
              Text(
                fixture.lockedReason!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FixtureTeamRow extends StatelessWidget {
  const _FixtureTeamRow({
    required this.name,
    required this.hasRealTeam,
    this.score,
    required this.isWinner,
    required this.isLoser,
  });

  final String name;
  final bool hasRealTeam;
  final String? score;
  final bool isWinner;
  final bool isLoser;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final textColor = !hasRealTeam || isLoser ? c.inkSecondary : c.inkPrimary;
    return Row(
      children: [
        if (hasRealTeam)
          CreaseTeamBadge(name: name, size: 24)
        else
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.pillMutedBg,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '?',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: textColor,
                  fontWeight: isWinner ? FontWeight.w700 : FontWeight.w600,
                ),
          ),
        ),
        if (score != null)
          Text(
            score!,
            style: creaseNumeralStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
      ],
    );
  }
}
