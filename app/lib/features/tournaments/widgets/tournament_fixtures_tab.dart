import 'package:flutter/material.dart';

import '../../../domain/models.dart';
import '../../../domain/stats_engine.dart';
import '../../../domain/tournament_engine.dart';
import '../../../theme/crease_theme.dart';
import '../../../widgets/crease_ui.dart';
import '../../../widgets/glass_surface.dart';
import 'tournament_fixture_card.dart';

enum _FixtureStatusFilter {
  all('All'),
  upcoming('Upcoming'),
  completed('Completed');

  const _FixtureStatusFilter(this.label);
  final String label;
}

class TournamentFixturesTab extends StatefulWidget {
  const TournamentFixturesTab({
    super.key,
    required this.tournament,
    required this.overview,
    this.tournamentMvp,
    required this.onAddTeams,
    required this.onTapFixture,
    required this.onTapExtraMatch,
    required this.onDiscardLiveMatch,
    required this.onUnlockKnockoutsEarly,
    this.readOnly = false,
  });

  final Tournament tournament;
  final TournamentOverview overview;
  final PlayerCareerStats? tournamentMvp;
  final VoidCallback onAddTeams;
  final ValueChanged<ScheduledFixture> onTapFixture;
  final ValueChanged<DerivedMatchState> onTapExtraMatch;
  final void Function(DerivedMatchState match, String label) onDiscardLiveMatch;
  final VoidCallback onUnlockKnockoutsEarly;
  final bool readOnly;

  @override
  State<TournamentFixturesTab> createState() => _TournamentFixturesTabState();
}

class _TournamentFixturesTabState extends State<TournamentFixturesTab> {
  bool _showLockedKnockouts = false;
  _FixtureStatusFilter _statusFilter = _FixtureStatusFilter.all;
  String? _teamFilter;
  final Set<int> _expandedRounds = {};
  bool _initializedRounds = false;

  void _ensureDefaultExpandedRounds(
    Map<int, List<ScheduledFixture>> rounds,
    List<int> roundNumbers,
  ) {
    if (_initializedRounds || roundNumbers.isEmpty) return;
    _initializedRounds = true;
    if (roundNumbers.length <= 3) {
      for (final r in roundNumbers) {
        final list = rounds[r]!;
        if (list.any((f) => !f.isCompleted)) {
          _expandedRounds.add(r);
        }
      }
      if (_expandedRounds.isEmpty) {
        _expandedRounds.add(roundNumbers.last);
      }
      return;
    }
    int? firstActiveRound;
    for (final r in roundNumbers) {
      final list = rounds[r]!;
      if (list.any((f) => f.isLive)) {
        _expandedRounds.add(r);
      }
      firstActiveRound ??= list.any((f) => !f.isCompleted) ? r : null;
    }
    if (firstActiveRound != null) {
      _expandedRounds.add(firstActiveRound);
    } else {
      _expandedRounds.add(roundNumbers.last);
    }
  }

  Future<void> _pickTeamFilter(BuildContext context) async {
    final teams = widget.tournament.teams;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        final maxSheetHeight = MediaQuery.sizeOf(ctx).height * 0.65;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          child: GlassSurface(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(CreaseRadius.sheet),
            ),
            fillColor: c.surfaceSheet,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CreaseSheetHeader(title: 'Filter by team'),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ListTile(
                          dense: true,
                          title: const Text('All teams'),
                          trailing: _teamFilter == null
                              ? Icon(Icons.check_rounded, color: c.pitchGreen)
                              : null,
                          onTap: () => Navigator.pop(ctx, ''),
                        ),
                        for (final team in teams)
                          ListTile(
                            dense: true,
                            leading: CreaseTeamBadge(name: team, size: 26),
                            title: Text(team),
                            trailing: _teamFilter == team
                                ? Icon(Icons.check_rounded, color: c.pitchGreen)
                                : null,
                            onTap: () => Navigator.pop(ctx, team),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _teamFilter = picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final tournament = widget.tournament;
    final overview = widget.overview;
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
                  'No fixtures yet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Add at least 2 teams to generate the tournament schedule.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (!widget.readOnly) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: widget.onAddTeams,
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

    // Open tournament: list all played/live matches cleanly
    if (tournament.structure == TournamentStructure.open) {
      if (overview.extraMatches.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'No fixtures played yet.\nTap "Start match" to record the first result.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        );
      }
      return ListView.separated(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 96 + bottomInset),
        itemCount:
            overview.extraMatches.length + (overview.champion != null ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (overview.champion != null && index == 0) {
            return TournamentChampionBanner(
              champion: overview.champion!,
              mvp: widget.tournamentMvp,
            );
          }
          final m = overview.extraMatches[
              overview.champion != null ? index - 1 : index];
          final inn = m.activeInnings;
          final stage = MatchStage.fromName(m.config.tournamentStage);
          final canDiscard = isUnstartedLiveMatch(m);
          return CreasePressable(
            onTap: () => widget.onTapExtraMatch(m),
            child: GlassSurface(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (m.status == MatchStatus.live) ...[
                        const CreaseLiveDot(size: 7),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          m.config.title,
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
                          color: stage == MatchStage.finalMatch
                              ? c.pitchGreenSoft
                              : c.pillMutedBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          stage.label,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontSize: 10.5,
                                    color: stage == MatchStage.finalMatch
                                        ? c.pitchGreen
                                        : c.inkPrimary,
                                  ),
                        ),
                      ),
                      if (canDiscard) ...[
                        const SizedBox(width: 4),
                        CreaseMenuButton<String>(
                          compact: true,
                          icon: Icons.more_horiz_rounded,
                          iconSize: 18,
                          tooltip: 'Match options',
                          sheetTitle: m.config.title,
                          onSelected: (v) {
                            if (v == 'discard') {
                              widget.onDiscardLiveMatch(m, m.config.title);
                            }
                          },
                          items: const [
                            CreaseMenuItem(
                              value: 'discard',
                              label: 'Discard unstarted match',
                              subtitle: 'Removes this 0/0 live match',
                              icon: Icons.delete_outline_rounded,
                              isDestructive: true,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${inn.battingTeam} ${inn.scoreText} (${inn.oversText} ov)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (m.resultSummary != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      m.resultSummary!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: c.pitchGreen,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    }

    final liveFixtures = overview.allFixtures.where((f) => f.isLive).toList();
    final isPureKnockout = tournament.structure == TournamentStructure.knockout;
    final showKnockoutsAboveLeague =
        isPureKnockout || overview.knockoutsUnlocked;

    final allRounds = <int, List<ScheduledFixture>>{};
    for (final f in overview.leagueFixtures) {
      allRounds.putIfAbsent(f.roundNumber, () => []).add(f);
    }
    final allRoundNumbers = allRounds.keys.toList()..sort();
    _ensureDefaultExpandedRounds(allRounds, allRoundNumbers);

    final hasActiveFilter =
        _statusFilter != _FixtureStatusFilter.all || _teamFilter != null;
    final filteredLeague = overview.leagueFixtures.where((f) {
      if (_statusFilter == _FixtureStatusFilter.upcoming &&
          (f.isCompleted || f.isLive)) {
        return false;
      }
      if (_statusFilter == _FixtureStatusFilter.completed && !f.isCompleted) {
        return false;
      }
      if (_teamFilter != null &&
          f.teamA != _teamFilter &&
          f.teamB != _teamFilter) {
        return false;
      }
      return true;
    }).toList();

    final rounds = <int, List<ScheduledFixture>>{};
    for (final f in filteredLeague) {
      rounds.putIfAbsent(f.roundNumber, () => []).add(f);
    }
    final roundNumbers = rounds.keys.toList()..sort();

    Widget buildKnockoutSection() {
      if (overview.knockoutFixtures.isEmpty) return const SizedBox.shrink();

      if (showKnockoutsAboveLeague) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isPureKnockout ? 'Knockout bracket' : 'Knockout stage',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final f in overview.knockoutFixtures) ...[
              TournamentFixtureCard(
                fixture: f,
                onTap: () => widget.onTapFixture(f),
                onDiscardLiveMatch:
                    !widget.readOnly && isUnstartedLiveMatch(f.match)
                        ? () => widget.onDiscardLiveMatch(f.match!, f.label)
                        : null,
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CreasePressable(
            onTap: () =>
                setState(() => _showLockedKnockouts = !_showLockedKnockouts),
            child: GlassSurface(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 16,
                    color: c.inkSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Knockout stage · ${overview.knockoutFixtures.length} matches',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Top ${overview.qualifiersCount} qualify · Unlocks after league (${overview.completedLeagueCount}/${overview.totalLeagueCount})',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _showLockedKnockouts
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: c.inkSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_showLockedKnockouts) ...[
            if (!widget.readOnly && overview.completedLeagueCount > 0)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: widget.onUnlockKnockoutsEarly,
                  child: const Text('Unlock early'),
                ),
              )
            else
              const SizedBox(height: 10),
            for (final f in overview.knockoutFixtures) ...[
              TournamentFixtureCard(
                fixture: f,
                onTap: () => widget.onTapFixture(f),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 96 + bottomInset),
      children: [
        if (overview.champion != null && isPureKnockout) ...[
          TournamentChampionBanner(
            champion: overview.champion!,
            mvp: widget.tournamentMvp,
          ),
          const SizedBox(height: 16),
        ],
        if (liveFixtures.isNotEmpty) ...[
          Row(
            children: [
              const CreaseLiveDot(size: 7),
              const SizedBox(width: 7),
              Text(
                'Live now',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: c.pitchGreen,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final f in liveFixtures) ...[
            TournamentFixtureCard(
              fixture: f,
              onTap: () => widget.onTapFixture(f),
              onDiscardLiveMatch:
                  !widget.readOnly && isUnstartedLiveMatch(f.match)
                      ? () => widget.onDiscardLiveMatch(f.match!, f.label)
                      : null,
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
        ],
        if (showKnockoutsAboveLeague &&
            overview.knockoutFixtures.isNotEmpty) ...[
          buildKnockoutSection(),
          if (allRoundNumbers.isNotEmpty) const SizedBox(height: 10),
        ],
        if (allRoundNumbers.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'League schedule',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${overview.completedLeagueCount}/${overview.totalLeagueCount} done',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in _FixtureStatusFilter.values) ...[
                  Builder(
                    builder: (chipCtx) => ChoiceChip(
                      label: Text(filter.label),
                      selected: _statusFilter == filter,
                      selectedColor: c.pitchGreenSoft,
                      labelStyle: TextStyle(
                        color: _statusFilter == filter
                            ? c.pitchGreen
                            : c.inkPrimary,
                        fontWeight: _statusFilter == filter
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                      side: BorderSide(
                        color: _statusFilter == filter
                            ? c.pitchGreen
                            : c.hairline,
                      ),
                      showCheckmark: false,
                      onSelected: (_) {
                        setState(() => _statusFilter = filter);
                        Scrollable.ensureVisible(
                          chipCtx,
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          alignment: 0.5,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Builder(
                  builder: (chipCtx) => ActionChip(
                    avatar: Icon(
                      Icons.filter_list_rounded,
                      size: 16,
                      color:
                          _teamFilter != null ? c.pitchGreen : c.inkSecondary,
                    ),
                    label: Text(
                      _teamFilter ?? 'All teams',
                      style: TextStyle(
                        color:
                            _teamFilter != null ? c.pitchGreen : c.inkPrimary,
                        fontWeight: _teamFilter != null
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    backgroundColor:
                        _teamFilter != null ? c.pitchGreenSoft : null,
                    side: BorderSide(
                      color: _teamFilter != null ? c.pitchGreen : c.hairline,
                    ),
                    onPressed: () {
                      Scrollable.ensureVisible(
                        chipCtx,
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        alignment: 0.5,
                      );
                      _pickTeamFilter(context);
                    },
                  ),
                ),
                if (hasActiveFilter) ...[
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: () => setState(() {
                      _statusFilter = _FixtureStatusFilter.all;
                      _teamFilter = null;
                    }),
                    child: const Text('Clear'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (roundNumbers.isEmpty)
            GlassSurface(
              padding: const EdgeInsets.all(18),
              child: Text(
                'No fixtures match the current filter.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            for (final r in roundNumbers) ...[
              Builder(
                builder: (ctx) {
                  final list = rounds[r]!;
                  final isExpanded =
                      hasActiveFilter || _expandedRounds.contains(r);
                  final doneCount = list.where((f) => f.isCompleted).length;
                  final liveCount = list.where((f) => f.isLive).length;
                  final summary = doneCount == list.length
                      ? '$doneCount/${list.length} done'
                      : liveCount > 0
                          ? '$liveCount live · ${list.length - doneCount - liveCount} upcoming'
                          : '${list.length - doneCount} upcoming';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CreasePressable(
                        onTap: hasActiveFilter
                            ? null
                            : () => setState(() {
                                  if (_expandedRounds.contains(r)) {
                                    _expandedRounds.remove(r);
                                  } else {
                                    _expandedRounds.add(r);
                                  }
                                }),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: c.surfaceKey,
                            borderRadius:
                                BorderRadius.circular(CreaseRadius.control),
                            border: Border.all(color: c.hairlineSubtle),
                          ),
                          child: Row(
                            children: [
                              Text(
                                'Round $r',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontSize: 13.5),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  summary,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: liveCount > 0
                                            ? c.pitchGreen
                                            : c.inkSecondary,
                                      ),
                                ),
                              ),
                              if (!hasActiveFilter)
                                Icon(
                                  isExpanded
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                  size: 20,
                                  color: c.inkSecondary,
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (isExpanded)
                        for (final f in list) ...[
                          TournamentFixtureCard(
                            fixture: f,
                            onTap: () => widget.onTapFixture(f),
                            onDiscardLiveMatch: !widget.readOnly &&
                                    isUnstartedLiveMatch(f.match)
                                ? () => widget.onDiscardLiveMatch(
                                      f.match!,
                                      f.label,
                                    )
                                : null,
                          ),
                          const SizedBox(height: 10),
                        ],
                    ],
                  );
                },
              ),
            ],
        ],
        if (!showKnockoutsAboveLeague &&
            overview.knockoutFixtures.isNotEmpty) ...[
          const SizedBox(height: 6),
          buildKnockoutSection(),
        ],
      ],
    );
  }
}
