import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/models.dart';
import '../../domain/stats_engine.dart';
import '../../domain/team_profile.dart';
import '../../domain/tournament_engine.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/crease_ui.dart';
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
    if (!_userChangedScope &&
        _selectedTeamName == null &&
        _selectedTournamentId == null) {
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
    final excludeDemo = hasRealMatches ||
        _selectedTeamName != null ||
        _selectedTournamentId != null;
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
          '${p.runs} runs (${p.ballsFaced}b) · SR ${p.strikeRate.toStringAsFixed(0)}',
      };

  void _openPlayerCard(PlayerCareerStats p) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return GlassSurface(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(CreaseRadius.sheet),
          ),
          fillColor: c.surfaceSheet,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
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
                  CreaseTeamBadge(name: p.name, size: 46, highlighted: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: Theme.of(ctx).textTheme.titleLarge,
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
                    icon: const Icon(Icons.share_rounded, size: 20),
                    onPressed: () {
                      Share.share(
                        '${p.name} · Crease Career Stats\n'
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
                        ? '-'
                        : p.economy.toStringAsFixed(1),
                  ),
                ],
              ),
              const SizedBox(height: 10),
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
              padding: const EdgeInsets.symmetric(vertical: 6),
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
                    style: creaseNumeralStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: c.pitchGreen,
                    ),
                  ),
                ],
              ),
            );
        return GlassSurface(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(CreaseRadius.sheet),
          ),
          fillColor: c.surfaceSheet,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CreaseSheetHeader(
                title: 'MVP scoring',
                subtitle:
                    'All-round match impact across batting, bowling, and fielding.',
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
          CreaseSegmentedControl<_StatsBoard>(
            selected: _board,
            onChanged: (v) => setState(() => _board = v),
            items: const [
              (value: _StatsBoard.mvp, label: 'MVP', icon: null),
              (value: _StatsBoard.batting, label: 'Batting', icon: null),
              (value: _StatsBoard.bowling, label: 'Bowling', icon: null),
              (value: _StatsBoard.boundaries, label: '4s & 6s', icon: null),
            ],
          ),

          if (_board == _StatsBoard.mvp)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _showMvpInfoSheet,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 3,
                    horizontal: 2,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'All-round impact across batting, bowling & fielding',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Formula',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: c.pitchGreen,
                            ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.info_outline_rounded,
                        size: 15,
                        color: c.pitchGreen,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          Builder(
            builder: (context) {
              final myTeams =
                  widget.savedTeams.where((t) => t.isMyTeam).toList();
              if (myTeams.isEmpty && widget.tournaments.isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final team in myTeams)
                        _ScopePill(
                          label: team.name,
                          selected: _selectedTeamName == team.name,
                          onTap: () => setState(() {
                            _userChangedScope = true;
                            _selectedTeamName = team.name;
                            _selectedTournamentId = null;
                          }),
                        ),
                      for (final t in widget.tournaments)
                        _ScopePill(
                          label: t.name,
                          selected: _selectedTournamentId == t.id,
                          onTap: () => setState(() {
                            _userChangedScope = true;
                            _selectedTournamentId = t.id;
                            _selectedTeamName = null;
                          }),
                        ),
                      _ScopePill(
                        label: 'All matches',
                        selected: _selectedTournamentId == null &&
                            _selectedTeamName == null,
                        onTap: () => setState(() {
                          _userChangedScope = true;
                          _selectedTournamentId = null;
                          _selectedTeamName = null;
                        }),
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
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c.pitchGreenSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.bar_chart_rounded,
                      size: 22,
                      color: c.pitchGreen,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No player stats yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Completed deliveries will appear here as batting, bowling, and MVP rankings.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            )
          else ...[
            // Leader feature card (#1)
            CreasePressable(
              onTap: () => _openPlayerCard(ranked.first),
              child: GlassSurface(
                borderColor: c.pitchGreen.withValues(alpha: 0.45),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.pitchGreen,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text(
                        '1',
                        style: creaseNumeralStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _secondaryMetric(ranked.first),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _primaryMetric(ranked.first),
                      style: creaseNumeralStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        color: c.pitchGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (ranked.length > 1) ...[
              const SizedBox(height: 12),
              GlassSurface(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: Column(
                  children: [
                    for (var i = 1; i < ranked.length; i++) ...[
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _openPlayerCard(ranked[i]),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 2,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 26,
                                child: Text(
                                  '${i + 1}',
                                  style: creaseNumeralStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: c.inkSecondary,
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
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _secondaryMetric(ranked[i]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _primaryMetric(ranked[i]),
                                style: creaseNumeralStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: c.inkPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (i != ranked.length - 1)
                        Divider(height: 1, color: c.hairlineSubtle),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ]),
      ),
    );
  }
}

class _ScopePill extends StatelessWidget {
  const _ScopePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(CreaseRadius.pill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? c.inkPrimary : c.surfaceGlass,
            borderRadius: BorderRadius.circular(CreaseRadius.pill),
            border: Border.all(
              color: selected ? c.inkPrimary : c.hairline,
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontSize: 12,
                  color: selected ? c.ground : c.inkPrimary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
          ),
        ),
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
          borderRadius: BorderRadius.circular(CreaseRadius.control),
          border: Border.all(color: c.hairlineSubtle),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: creaseNumeralStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: c.inkPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
