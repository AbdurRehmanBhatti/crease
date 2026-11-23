import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/models.dart';
import '../../domain/stats_engine.dart';
import '../../domain/team_profile.dart';
import '../../domain/tournament_engine.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/glass_surface.dart';

enum _StatsBoard { mvp, batting, bowling, boundaries }

class StatsTabView extends StatefulWidget {
  const StatsTabView({
    super.key,
    required this.matches,
    required this.tournaments,
    required this.savedTeams,
  });

  final List<DerivedMatchState> matches;
  final List<Tournament> tournaments;
  final List<TeamProfile> savedTeams;

  @override
  State<StatsTabView> createState() => _StatsTabViewState();
}

class _StatsTabViewState extends State<StatsTabView> {
  _StatsBoard _board = _StatsBoard.mvp;
  String? _selectedTournamentId;
  String? _selectedTeamName;
  bool _userChangedScope = false;

  @override
  void initState() {
    super.initState();
    _applyDefaultScope();
  }

  @override
  void didUpdateWidget(covariant StatsTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_userChangedScope && _selectedTeamName == null && _selectedTournamentId == null) {
      _applyDefaultScope();
    }
  }

  void _applyDefaultScope() {
    final myTeams = widget.savedTeams.where((t) => t.isMyTeam).toList();
    if (myTeams.isNotEmpty) {
      _selectedTeamName = myTeams.first.name;
    }
  }

  List<PlayerCareerStats> get _ranked {
    final hasRealMatches = widget.matches.any((m) => !m.config.isDemo);
    final excludeDemo =
        hasRealMatches || _selectedTeamName != null || _selectedTournamentId != null;
    final all = StatsEngine.derive(
      widget.matches,
      tournamentId: _selectedTournamentId,
      teamName: _selectedTeamName,
      excludeDemo: excludeDemo,
    );
    return switch (_board) {
      _StatsBoard.mvp => StatsEngine.byMvp(all),
      _StatsBoard.batting => StatsEngine.byRuns(all),
      _StatsBoard.bowling => StatsEngine.byWickets(all),
      _StatsBoard.boundaries => StatsEngine.bySixes(all),
    };
  }

  String _primaryMetric(PlayerCareerStats p) => switch (_board) {
        _StatsBoard.mvp => '${p.mvpPoints} pts',
        _StatsBoard.batting => '${p.runs}',
        _StatsBoard.bowling => '${p.wickets} wkts',
        _StatsBoard.boundaries => '${p.sixes}×6 · ${p.fours}×4',
      };

  String _secondaryMetric(PlayerCareerStats p) => switch (_board) {
        _StatsBoard.mvp =>
          '${p.runs}r · ${p.wickets}w · ${p.fieldingDismissals}f',
        _StatsBoard.batting =>
          'Avg ${p.battingAverage.toStringAsFixed(1)} · SR ${p.strikeRate.toStringAsFixed(0)} · HS ${p.highestScoreText}',
        _StatsBoard.bowling =>
          '${p.oversBowledText} ov · Econ ${p.economy.toStringAsFixed(1)} · Best ${p.bestBowlingText}',
        _StatsBoard.boundaries =>
          '${p.runs} runs (${p.ballsFaced} balls) · SR ${p.strikeRate.toStringAsFixed(0)}',
      };

  void _openPlayerCard(PlayerCareerStats p) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return GlassSurface(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: Theme.of(ctx).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${p.matchesPlayed} match${p.matchesPlayed == 1 ? '' : 'es'} · ${p.mvpPoints} MVP pts',
                          style: Theme.of(ctx)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: c.pitchGreen),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Share player stats',
                    icon: const Icon(Icons.share_rounded),
                    onPressed: () {
                      Share.share(
                        '${p.name} — Crease Career Stats\n'
                        'Batting: ${p.runs} runs (${p.ballsFaced}b), HS ${p.highestScoreText}, SR ${p.strikeRate.toStringAsFixed(0)}, 4s:${p.fours} 6s:${p.sixes}\n'
                        'Bowling: ${p.wickets} wkts (${p.oversBowledText} ov), Econ ${p.economy.toStringAsFixed(1)}, Best ${p.bestBowlingText}\n'
                        'MVP: ${p.mvpPoints} pts',
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _StatBox(label: 'Runs', value: '${p.runs}'),
                  const SizedBox(width: 8),
                  _StatBox(
                    label: 'SR',
                    value: p.strikeRate.toStringAsFixed(0),
                  ),
                  const SizedBox(width: 8),
                  _StatBox(label: 'Wkts', value: '${p.wickets}'),
                  const SizedBox(width: 8),
                  _StatBox(
                    label: 'Econ',
                    value: p.legalBallsBowled == 0
                        ? '—'
                        : p.economy.toStringAsFixed(1),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _StatBox(label: 'High', value: p.highestScoreText),
                  const SizedBox(width: 8),
                  _StatBox(label: '4s / 6s', value: '${p.fours} / ${p.sixes}'),
                  const SizedBox(width: 8),
                  _StatBox(label: 'Best', value: p.bestBowlingText),
                  const SizedBox(width: 8),
                  _StatBox(label: 'Fielding', value: '${p.fieldingDismissals}'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMvpInfoSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        Widget row(String label, String pts) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                            color: c.inkPrimary,
                          ),
                    ),
                  ),
                  Text(
                    pts,
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          color: c.pitchGreen,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ],
              ),
            );
        return GlassSurface(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                'How MVP points work',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'Most Valuable Player ranks all-round match impact across batting, bowling, and fielding.',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              row('Every run scored', '+1 pt'),
              row('Four / Six bonus', '+1 / +2 pts'),
              row('Half-century (50) / Century (100)', '+10 / +25 pts'),
              Divider(height: 18, color: c.hairlineSubtle),
              row('Every wicket taken', '+20 pts'),
              row('Maiden over bowled', '+10 pts'),
              Divider(height: 18, color: c.hairlineSubtle),
              row('Catch, stumping, or run-out', '+8 pts'),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final ranked = _ranked;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          // Board selector segmented bar (fits cleanly with zero horizontal clipping)
          GlassSurface(
            borderRadius: BorderRadius.circular(14),
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                for (final entry in const [
                  (_StatsBoard.mvp, 'MVP'),
                  (_StatsBoard.batting, 'Batting'),
                  (_StatsBoard.bowling, 'Bowling'),
                  (_StatsBoard.boundaries, '4s & 6s'),
                ])
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _board = entry.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _board == entry.$1
                              ? c.pitchGreen
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text(
                          entry.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: _board == entry.$1
                                        ? Colors.white
                                        : c.inkPrimary,
                                    fontWeight: _board == entry.$1
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          if (_board == _StatsBoard.mvp)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _showMvpInfoSheet,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Most Valuable Player · all-round impact score',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: c.inkSecondary,
                              ),
                        ),
                      ),
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: c.pitchGreen,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Scope filter: My Teams first (default), then Tournaments, then All
          Builder(
            builder: (context) {
              final myTeams =
                  widget.savedTeams.where((t) => t.isMyTeam).toList();
              if (myTeams.isEmpty && widget.tournaments.isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final team in myTeams)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            avatar: Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: _selectedTeamName == team.name
                                  ? Colors.white
                                  : c.pitchGreen,
                            ),
                            label: Text(team.name),
                            selected: _selectedTeamName == team.name,
                            selectedColor: c.pitchGreen,
                            checkmarkColor: Colors.white,
                            labelStyle: TextStyle(
                              color: _selectedTeamName == team.name
                                  ? Colors.white
                                  : c.inkPrimary,
                            ),
                            onSelected: (_) => setState(() {
                              _userChangedScope = true;
                              _selectedTeamName = team.name;
                              _selectedTournamentId = null;
                            }),
                          ),
                        ),
                      for (final t in widget.tournaments)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(t.name),
                            selected: _selectedTournamentId == t.id,
                            onSelected: (_) => setState(() {
                              _userChangedScope = true;
                              _selectedTournamentId = t.id;
                              _selectedTeamName = null;
                            }),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: const Text('All'),
                          selected: _selectedTournamentId == null &&
                              _selectedTeamName == null,
                          onSelected: (_) => setState(() {
                            _userChangedScope = true;
                            _selectedTournamentId = null;
                            _selectedTeamName = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 14),

          if (ranked.isEmpty)
            GlassSurface(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.insights_rounded, size: 30, color: c.pitchGreen),
                  const SizedBox(height: 10),
                  Text(
                    'No player stats yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Score a few balls and leaderboards will populate automatically.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            )
          else ...[
            // Leader hero card (#1)
            GestureDetector(
              onTap: () => _openPlayerCard(ranked.first),
              child: GlassSurface(
                borderColor: c.pitchGreen,
                borderWidth: 1.2,
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.pitchGreen,
                        shape: BoxShape.circle,
                      ),
                      child: const Text(
                        '#1',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ranked.first.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _secondaryMetric(ranked.first),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _primaryMetric(ranked.first),
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: c.pitchGreen,
                            fontSize: 22,
                          ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Full ranked list
            GlassSurface(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                children: [
                  for (var i = 0; i < ranked.length; i++) ...[
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _openPlayerCard(ranked[i]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 4,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              child: Text(
                                '${i + 1}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: i == 0
                                          ? c.pitchGreen
                                          : c.inkSecondary,
                                    ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedTeamName == null &&
                                            ranked[i].teamName != null
                                        ? '${ranked[i].name} · ${ranked[i].teamName}'
                                        : ranked[i].name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _secondaryMetric(ranked[i]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.labelMedium,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _primaryMetric(ranked[i]),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: i == 0 ? c.pitchGreen : c.inkPrimary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (i != ranked.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: c.surfaceKey,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.hairline),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontSize: 15,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: 11,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
