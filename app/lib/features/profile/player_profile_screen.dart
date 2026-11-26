import 'package:flutter/material.dart';

import '../../data/local_event_store.dart';
import '../../domain/models.dart';
import '../../domain/stats_engine.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/crease_ui.dart';
import '../../widgets/glass_surface.dart';
import '../scorecard/scorecard_screen.dart';
import 'player_career_poster.dart';

enum _StatsCategory { batting, bowling, fielding }

/// Full 3-tab Player Profile screen (Overview · Stats · Matches)
/// accessible from Search, Stats, Team Squads, and Match Scorecards.
class PlayerProfileScreen extends StatefulWidget {
  const PlayerProfileScreen({
    super.key,
    required this.playerName,
    this.playerId,
    this.userId,
    this.role,
    this.teams = const [],
    this.isVerified = false,
    this.avatarUrl,
    this.matches,
  });

  final String playerName;
  final String? playerId;
  final String? userId;
  final String? role;
  final List<String> teams;
  final bool isVerified;
  final String? avatarUrl;
  final List<DerivedMatchState>? matches;

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  PlayerFullProfile? _profile;
  List<String> _teams = const [];
  String? _avatarUrl;
  bool _loading = true;
  _StatsCategory _statsCategory = _StatsCategory.batting;
  bool _oppBowlingMode = false;

  @override
  void initState() {
    super.initState();
    _teams = widget.teams;
    _avatarUrl = widget.avatarUrl;
    _load();
  }

  Future<void> _load() async {
    final store = LocalEventStore.instance;
    if (store.directory.playersById.isEmpty) {
      await store.refreshDirectory();
    }
    final dir = store.directory;

    List<DerivedMatchState> matches;
    if (widget.matches != null) {
      matches = widget.matches!;
    } else {
      final configs = await store.listMatches();
      matches = <DerivedMatchState>[];
      for (final cfg in configs) {
        final events = await store.getBallEvents(cfg.id);
        matches.add(store.deriveMatch(cfg, events));
      }
    }

    var teams = List<String>.from(_teams);
    final lower = widget.playerName.trim().toLowerCase();
    final pid = widget.playerId?.trim();
    if (teams.isEmpty) {
      final savedTeams = await store.listTeams();
      for (final t in savedTeams) {
        final hasMatch = (pid != null && pid.isNotEmpty)
            ? t.squad.any((p) => p.id == pid)
            : t.players.any((p) => p.trim().toLowerCase() == lower);
        if (hasMatch) {
          teams.add(t.name);
        }
      }
    }

    var resolvedAvatar = _avatarUrl;
    if (resolvedAvatar == null || resolvedAvatar.isEmpty) {
      final myProfile = await store.getUserProfile();
      final myLinked = myProfile.linkedPlayerName?.trim().toLowerCase();
      final myName = myProfile.displayName.trim().toLowerCase();
      if ((myLinked == lower || myName == lower) &&
          myProfile.avatarUrl != null &&
          myProfile.avatarUrl!.isNotEmpty) {
        resolvedAvatar = myProfile.avatarUrl;
      } else if (pid != null && pid.isNotEmpty) {
        resolvedAvatar = await store.fetchPublicPlayerAvatar(pid);
      }
    }

    final realMatches = matches.where((m) => !m.config.isDemo).toList();
    final derived = StatsEnginePlayerProfile.derivePlayerProfile(
      realMatches.isNotEmpty ? realMatches : matches,
      widget.playerName,
      playerId: widget.playerId,
      userId: widget.userId,
      excludeDemo: realMatches.isNotEmpty,
      playerNamesById: dir.playerNamesById,
      playerUserIdsById: dir.playerUserIdsById,
    );

    if (!mounted) return;
    setState(() {
      _profile = derived;
      _teams = teams;
      _avatarUrl = resolvedAvatar;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final stats = _profile?.overall;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: c.ground,
        appBar: AppBar(
          title: Text(widget.playerName),
          actions: [
            if (stats != null)
              IconButton(
                tooltip: 'Share career card',
                icon: const Icon(Icons.share_rounded, size: 20),
                onPressed: () {
                  PlayerCareerPoster.sharePlayerCard(
                    playerName: widget.playerName,
                    stats: stats,
                    role: widget.role,
                    teamName: _teams.isNotEmpty ? _teams.first : stats.teamName,
                  );
                },
              ),
          ],
          bottom: TabBar(
            labelColor: c.inkPrimary,
            indicatorColor: c.pitchGreen,
            indicatorWeight: 2.5,
            unselectedLabelColor: c.inkSecondary,
            dividerColor: c.hairlineSubtle,
            labelStyle: Theme.of(context).textTheme.titleSmall,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Stats'),
              Tab(text: 'Matches'),
            ],
          ),
        ),
        body: _loading
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    CreaseSkeletonBox(height: 112),
                    SizedBox(height: 12),
                    CreaseSkeletonBox(height: 170),
                  ],
                ),
              )
            : TabBarView(
                children: [
                  _buildOverviewTab(context, _profile!),
                  _buildStatsTab(context, _profile!),
                  _buildMatchesTab(context, _profile!),
                ],
              ),
      ),
    );
  }

  Widget _buildOverviewTab(BuildContext context, PlayerFullProfile data) {
    final c = context.crease;
    final s = data.overall;
    final recent = data.contributions.take(5).toList();
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final sortedOpponents = List<PlayerOpponentSummary>.from(data.opponents)
      ..sort((a, b) => _oppBowlingMode
          ? b.wickets.compareTo(a.wickets)
          : b.runs.compareTo(a.runs));
    final topOpponents = sortedOpponents
        .where((o) => _oppBowlingMode ? o.legalBallsBowled > 0 : o.inningsBatted > 0)
        .take(5)
        .toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 32 + bottomInset),
      children: [
        // Identity card
        GlassSurface(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CreasePlayerAvatar(
                name: widget.playerName,
                size: 56,
                highlighted: true,
                avatarUrl: _avatarUrl,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.playerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (widget.isVerified) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.verified_rounded,
                            size: 18,
                            color: c.pitchGreen,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (widget.role != null && widget.role!.isNotEmpty)
                          _MetaPill(label: widget.role!),
                        for (final team in _teams.take(3))
                          _MetaPill(label: team, accent: true),
                        if (s != null)
                          _MetaPill(
                            label:
                                '${s.matchesPlayed} ${s.matchesPlayed == 1 ? 'match' : 'matches'}',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3-column Batting · Bowling · Fielding summary
        GlassSurface(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _DisciplineColumn(
                    title: 'Batting',
                    metrics: [
                      ('Runs', '${s?.runs ?? 0}'),
                      (
                        'Avg',
                        s == null || (s.inningsBatted - s.notOuts) <= 0
                            ? '—'
                            : s.battingAverage.toStringAsFixed(1),
                      ),
                      ('HS', s?.highestScoreText ?? '—'),
                    ],
                  ),
                ),
                VerticalDivider(width: 16, color: c.hairlineSubtle),
                Expanded(
                  child: _DisciplineColumn(
                    title: 'Bowling',
                    metrics: [
                      ('Wickets', '${s?.wickets ?? 0}'),
                      (
                        'Econ',
                        s == null ? '0.0' : s.economy.toStringAsFixed(1),
                      ),
                      ('Best', s?.bestBowlingText ?? '—'),
                    ],
                  ),
                ),
                VerticalDivider(width: 16, color: c.hairlineSubtle),
                Expanded(
                  child: _DisciplineColumn(
                    title: 'Fielding',
                    metrics: [
                      ('Catches', '${s?.catches ?? 0}'),
                      ('Stumpings', '${s?.stumpings ?? 0}'),
                      ('Run-outs', '${s?.runOuts ?? 0}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Recent Form (last 5 matches)
        Text('Recent form', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        GlassSurface(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              _FormRow(
                label: 'Bat',
                values: [
                  for (var i = 0; i < 5; i++)
                    i < recent.length ? (recent[i].batLabel ?? '—') : '—',
                ],
                accentColor: c.pitchGreen,
              ),
              const SizedBox(height: 10),
              _FormRow(
                label: 'Bowl',
                values: [
                  for (var i = 0; i < 5; i++)
                    i < recent.length ? (recent[i].bowlLabel ?? '—') : '—',
                ],
                accentColor: c.inkPrimary,
              ),
            ],
          ),
        ),

        if (data.opponents.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                'Best against',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              SizedBox(
                width: 164,
                child: CreaseSegmentedControl<bool>(
                  selected: _oppBowlingMode,
                  onChanged: (v) => setState(() => _oppBowlingMode = v),
                  items: const [
                    (value: false, label: 'Bat', icon: null),
                    (value: true, label: 'Bowl', icon: null),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GlassSurface(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: topOpponents.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _oppBowlingMode
                          ? 'No bowling spells recorded yet.'
                          : 'No batting innings recorded yet.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Team',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          SizedBox(
                            width: 52,
                            child: Text(
                              _oppBowlingMode ? 'Wkts' : 'Runs',
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            child: Text(
                              _oppBowlingMode ? 'Runs' : 'Inn',
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: Text(
                              _oppBowlingMode ? 'Econ' : 'SR',
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Divider(height: 1, color: c.hairlineSubtle),
                      for (var i = 0; i < topOpponents.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: c.hairlineSubtle),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  topOpponents[i].opponent,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: c.inkPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                              SizedBox(
                                width: 52,
                                child: Text(
                                  _oppBowlingMode
                                      ? '${topOpponents[i].wickets}'
                                      : '${topOpponents[i].runs}',
                                  textAlign: TextAlign.end,
                                  style: creaseNumeralStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: c.inkPrimary,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 48,
                                child: Text(
                                  _oppBowlingMode
                                      ? '${topOpponents[i].runsConceded}'
                                      : '${topOpponents[i].inningsBatted}',
                                  textAlign: TextAlign.end,
                                  style: creaseNumeralStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500,
                                    color: c.inkSecondary,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 56,
                                child: Text(
                                  _oppBowlingMode
                                      ? topOpponents[i]
                                          .economy
                                          .toStringAsFixed(1)
                                      : topOpponents[i]
                                          .strikeRate
                                          .toStringAsFixed(1),
                                  textAlign: TextAlign.end,
                                  style: creaseNumeralStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: c.pitchGreen,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatsTab(BuildContext context, PlayerFullProfile data) {
    final c = context.crease;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final overall = data.overall;

    final columns = <({String label, PlayerCareerStats stats})>[
      if (overall != null) (label: 'All', stats: overall),
      for (final entry in data.byFormat.entries)
        (label: entry.key, stats: entry.value),
    ];

    List<(String, List<String>)> rowsForCategory() {
      switch (_statsCategory) {
        case _StatsCategory.batting:
          return [
            ('Matches', [for (final col in columns) '${col.stats.matchesPlayed}']),
            ('Innings', [for (final col in columns) '${col.stats.inningsBatted}']),
            ('Runs', [for (final col in columns) '${col.stats.runs}']),
            ('Balls', [for (final col in columns) '${col.stats.ballsFaced}']),
            ('Highest', [for (final col in columns) col.stats.highestScoreText]),
            (
              'Average',
              [
                for (final col in columns)
                  (col.stats.inningsBatted - col.stats.notOuts) <= 0
                      ? '—'
                      : col.stats.battingAverage.toStringAsFixed(1),
              ],
            ),
            (
              'Strike Rate',
              [
                for (final col in columns)
                  col.stats.strikeRate.toStringAsFixed(1),
              ],
            ),
            ('Not Out', [for (final col in columns) '${col.stats.notOuts}']),
            ('Ducks', [for (final col in columns) '${col.stats.ducks}']),
            ('100s', [for (final col in columns) '${col.stats.hundreds}']),
            ('50s', [for (final col in columns) '${col.stats.fifties}']),
            ('30s', [for (final col in columns) '${col.stats.thirties}']),
            ('6s', [for (final col in columns) '${col.stats.sixes}']),
            ('4s', [for (final col in columns) '${col.stats.fours}']),
          ];
        case _StatsCategory.bowling:
          return [
            ('Matches', [for (final col in columns) '${col.stats.matchesPlayed}']),
            ('Innings', [for (final col in columns) '${col.stats.inningsBowled}']),
            ('Overs', [for (final col in columns) col.stats.oversBowledText]),
            ('Wickets', [for (final col in columns) '${col.stats.wickets}']),
            ('Runs', [for (final col in columns) '${col.stats.runsConceded}']),
            ('Best', [for (final col in columns) col.stats.bestBowlingText]),
            (
              'Economy',
              [for (final col in columns) col.stats.economy.toStringAsFixed(2)],
            ),
            (
              'Average',
              [
                for (final col in columns)
                  col.stats.wickets == 0
                      ? '—'
                      : col.stats.bowlingAverage.toStringAsFixed(1),
              ],
            ),
            ('Maidens', [for (final col in columns) '${col.stats.maidens}']),
          ];
        case _StatsCategory.fielding:
          return [
            ('Matches', [for (final col in columns) '${col.stats.matchesPlayed}']),
            ('Total', [for (final col in columns) '${col.stats.fieldingDismissals}']),
            ('Catches', [for (final col in columns) '${col.stats.catches}']),
            ('Stumpings', [for (final col in columns) '${col.stats.stumpings}']),
            ('Run-outs', [for (final col in columns) '${col.stats.runOuts}']),
            ('MVP Points', [for (final col in columns) '${col.stats.mvpPoints}']),
          ];
      }
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 32 + bottomInset),
      children: [
        CreaseSegmentedControl<_StatsCategory>(
          selected: _statsCategory,
          onChanged: (v) => setState(() => _statsCategory = v),
          items: const [
            (value: _StatsCategory.batting, label: 'Batting', icon: null),
            (value: _StatsCategory.bowling, label: 'Bowling', icon: null),
            (value: _StatsCategory.fielding, label: 'Fielding', icon: null),
          ],
        ),
        const SizedBox(height: 14),
        if (columns.isEmpty)
          GlassSurface(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No match statistics recorded for ${widget.playerName} yet.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else
          GlassSurface(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Builder(
              builder: (context) {
                final naturalWidth = 112.0 + (columns.length * 72.0);
                final minTableWidth =
                    (MediaQuery.sizeOf(context).width - 68).clamp(0.0, 2000.0);
                final tableWidth =
                    naturalWidth > minTableWidth ? naturalWidth : minTableWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Metric',
                                  style:
                                      Theme.of(context).textTheme.labelMedium,
                                ),
                              ),
                              for (final col in columns)
                                SizedBox(
                                  width: 72,
                                  child: Text(
                                    col.label,
                                    textAlign: TextAlign.end,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: col.label == 'All'
                                              ? c.pitchGreen
                                              : c.inkSecondary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: c.hairlineSubtle),
                        for (final row in rowsForCategory()) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    row.$1,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: c.inkPrimary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ),
                                for (var i = 0; i < row.$2.length; i++)
                                  SizedBox(
                                    width: 72,
                                    child: Text(
                                      row.$2[i],
                                      textAlign: TextAlign.end,
                                      style: creaseNumeralStyle(
                                        fontSize: 14.5,
                                        fontWeight: i == 0
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: i == 0
                                            ? c.inkPrimary
                                            : c.inkSecondary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Divider(height: 1, color: c.hairlineSubtle),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildMatchesTab(BuildContext context, PlayerFullProfile data) {
    final c = context.crease;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    if (data.contributions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: GlassSurface(
            padding: const EdgeInsets.all(22),
            child: Text(
              'No matches recorded for ${widget.playerName} yet.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 32 + bottomInset),
      itemCount: data.contributions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = data.contributions[index];
        final m = item.match;
        final perfParts = <String>[
          if (item.batLabel != null) 'Bat ${item.batLabel}',
          if (item.bowlLabel != null) 'Bowl ${item.bowlLabel}',
        ];
        return CreasePressable(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ScorecardScreen(matchId: m.config.id),
            ),
          ),
          child: GlassSurface(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
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
                        m.config.formatLabel,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontSize: 10.5,
                              color: c.inkPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${m.config.teamA} v ${m.config.teamB}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: c.inkSecondary,
                    ),
                  ],
                ),
                if (perfParts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    perfParts.join('  ·  '),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: c.pitchGreen,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
                if (m.resultSummary != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    m.resultSummary!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: c.inkSecondary,
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
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, this.accent = false});
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent ? c.pitchGreenSoft : c.pillMutedBg,
        borderRadius: BorderRadius.circular(CreaseRadius.badge),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontSize: 11,
              color: accent ? c.pitchGreen : c.inkPrimary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _DisciplineColumn extends StatelessWidget {
  const _DisciplineColumn({required this.title, required this.metrics});
  final String title;
  final List<(String, String)> metrics;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Column(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: c.pitchGreen,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < metrics.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Text(
            metrics[i].$2,
            style: creaseNumeralStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: c.inkPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            metrics[i].$1,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: c.inkSecondary,
                  fontSize: 11.5,
                ),
          ),
        ],
      ],
    );
  }
}

class _FormRow extends StatelessWidget {
  const _FormRow({
    required this.label,
    required this.values,
    required this.accentColor,
  });

  final String label;
  final List<String> values;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: c.inkPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        for (var i = 0; i < values.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: values[i] == '—' ? c.surfaceKey : c.pillMutedBg,
                borderRadius: BorderRadius.circular(CreaseRadius.control - 2),
                border: Border.all(
                  color: values[i] == '—'
                      ? c.hairlineSubtle
                      : accentColor.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                values[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: creaseNumeralStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: values[i] == '—' ? c.inkSecondary : accentColor,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
