import 'package:flutter/material.dart';

import '../../../domain/stats_engine.dart';
import '../../../domain/tournament_engine.dart';
import '../../../theme/crease_theme.dart';
import '../../../widgets/glass_surface.dart';
import 'tournament_fixture_card.dart';

class TournamentStandingsTab extends StatelessWidget {
  const TournamentStandingsTab({
    super.key,
    required this.tournament,
    required this.overview,
    required this.tournamentMvp,
    required this.onAddTeams,
    required this.onTapFixture,
    required this.onUnlockKnockoutsEarly,
    this.readOnly = false,
  });

  final Tournament tournament;
  final TournamentOverview overview;
  final PlayerCareerStats? tournamentMvp;
  final VoidCallback onAddTeams;
  final ValueChanged<ScheduledFixture> onTapFixture;
  final VoidCallback onUnlockKnockoutsEarly;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final standings = overview.standings;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    if (tournament.teams.length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: GlassSurface(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Add teams to start',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Add at least 2 teams to populate the Points Table and generate the schedule.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (!readOnly) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onAddTeams,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add teams'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 120 + bottomInset),
      children: [
        if (overview.champion != null) ...[
          TournamentChampionBanner(
            champion: overview.champion!,
            mvp: tournamentMvp,
          ),
          const SizedBox(height: 14),
        ],
        if (tournament.structure == TournamentStructure.leagueKnockout &&
            overview.totalLeagueCount > 0) ...[
          GlassSurface(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        overview.leagueComplete
                            ? 'League stage complete'
                            : 'League stage · ${overview.completedLeagueCount} of ${overview.totalLeagueCount}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (overview.qualifiersCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: overview.knockoutsUnlocked
                              ? c.pitchGreenSoft
                              : c.pillMutedBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          overview.knockoutsUnlocked
                              ? 'Knockouts live'
                              : 'Top ${overview.qualifiersCount} qualify',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontSize: 11,
                                    color: overview.knockoutsUnlocked
                                        ? c.pitchGreen
                                        : c.inkPrimary,
                                  ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: overview.totalLeagueCount == 0
                        ? 0
                        : overview.completedLeagueCount /
                            overview.totalLeagueCount,
                    minHeight: 5,
                    backgroundColor: c.pillMutedBg,
                    color: c.pitchGreen,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        GlassSurface(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 31),
                  Expanded(
                    child: Text(
                      'Team',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  for (final col in const [
                    (label: 'P', tip: 'Played', width: 24.0),
                    (label: 'W', tip: 'Won', width: 24.0),
                    (label: 'L', tip: 'Lost', width: 24.0),
                    (label: 'Pts', tip: 'Points', width: 28.0),
                    (label: 'NRR', tip: 'Net Run Rate', width: 48.0),
                  ])
                    SizedBox(
                      width: col.width,
                      child: Tooltip(
                        message: col.tip,
                        child: Text(
                          col.label,
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                    ),
                ],
              ),
              const Divider(height: 16),
              for (var i = 0; i < standings.length; i++) ...[
                _StandingsRowWidget(
                  rank: i + 1,
                  row: standings[i],
                  isQualified: i < overview.qualifiersCount &&
                      standings[i].played > 0,
                ),
                if (i != standings.length - 1) const Divider(height: 14),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'League matches only. Net Run Rate follows ICC calculation after each completed match.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (overview.knockoutFixtures.isNotEmpty &&
            overview.knockoutsUnlocked) ...[
          const SizedBox(height: 20),
          Text(
            'Knockout stage',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (final f in overview.knockoutFixtures) ...[
            TournamentFixtureCard(
              fixture: f,
              onTap: () => onTapFixture(f),
            ),
            const SizedBox(height: 10),
          ],
        ] else if (overview.knockoutFixtures.isNotEmpty &&
            overview.completedLeagueCount > 0) ...[
          const SizedBox(height: 16),
          GlassSurface(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: c.inkSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Knockouts unlock after league (${overview.completedLeagueCount}/${overview.totalLeagueCount})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (!readOnly)
                  TextButton(
                    onPressed: onUnlockKnockoutsEarly,
                    child: const Text('Unlock early'),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StandingsRowWidget extends StatelessWidget {
  const _StandingsRowWidget({
    required this.rank,
    required this.row,
    required this.isQualified,
  });

  final int rank;
  final PointsTableRow row;
  final bool isQualified;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final nrrColor = row.nrr > 0.0005
        ? c.pitchGreen
        : row.nrr < -0.0005
            ? c.wicketRed
            : c.inkSecondary;

    return Semantics(
      label:
          'Rank $rank, ${row.teamName}${isQualified ? ', in qualification zone' : ''}, ${row.played} played, ${row.won} won, ${row.lost} lost, ${row.points} points, net run rate ${row.nrrText}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 20,
              margin: const EdgeInsetsDirectional.only(end: 6),
              decoration: BoxDecoration(
                color: isQualified ? c.pitchGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(
              width: 18,
              child: Text(
                '$rank',
                style: creaseNumeralStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: isQualified ? c.pitchGreen : c.inkSecondary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                row.teamName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight:
                          isQualified ? FontWeight.w600 : FontWeight.w500,
                    ),
              ),
            ),
            SizedBox(
              width: 24,
              child: Text(
                '${row.played}',
                textAlign: TextAlign.end,
                style: creaseNumeralStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: c.inkPrimary,
                ),
              ),
            ),
            SizedBox(
              width: 24,
              child: Text(
                '${row.won}',
                textAlign: TextAlign.end,
                style: creaseNumeralStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: c.inkPrimary,
                ),
              ),
            ),
            SizedBox(
              width: 24,
              child: Text(
                '${row.lost}',
                textAlign: TextAlign.end,
                style: creaseNumeralStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: c.inkSecondary,
                ),
              ),
            ),
            SizedBox(
              width: 28,
              child: Text(
                '${row.points}',
                textAlign: TextAlign.end,
                style: creaseNumeralStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: c.inkPrimary,
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                row.nrrText,
                textAlign: TextAlign.end,
                style: creaseNumeralStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: nrrColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
