import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local_event_store.dart';
import '../../domain/cricket_engine.dart';
import '../../domain/match_insights.dart';
import '../../domain/models.dart';
import '../../domain/stats_engine.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/crease_ui.dart';
import '../../widgets/glass_surface.dart';
import '../profile/player_profile_screen.dart';
import 'match_summary_poster.dart';

/// 4-tab Daylight Glass Match Center: Overview · Scorecard · Charts · Overs.
/// Works seamlessly for both local matches and shared remote matches (with live updates).
class ScorecardScreen extends StatefulWidget {
  const ScorecardScreen({super.key, required this.matchId});

  final String matchId;

  @override
  State<ScorecardScreen> createState() => _ScorecardScreenState();
}

class _ScorecardScreenState extends State<ScorecardScreen> {
  DerivedMatchState? _state;
  bool _loading = true;
  bool _isRemoteLive = false;
  int _selectedInnings = 1;
  bool _userPickedInnings = false;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    final channel = _realtimeChannel;
    if (channel != null) {
      try {
        Supabase.instance.client.removeChannel(channel);
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _load() async {
    final store = LocalEventStore.instance;
    final localConfig = await store.getMatch(widget.matchId);
    if (localConfig != null) {
      await store.refreshDirectory();
      final events = await store.getBallEvents(widget.matchId);
      if (!mounted) return;
      final derived = store.deriveMatch(localConfig, events);
      setState(() {
        _state = derived;
        _isRemoteLive = false;
        if (!_userPickedInnings) {
          _selectedInnings = derived.activeInningsNumber;
        }
        _loading = false;
      });
      return;
    }

    // Not stored locally (e.g. opened via shared deep link) — fetch from cloud & watch live.
    final remote = await store.fetchRemoteMatch(widget.matchId);
    if (!mounted) return;
    if (remote == null) {
      setState(() {
        _state = null;
        _loading = false;
      });
      return;
    }
    final derived = CricketEngine.derive(
      remote.config,
      remote.events,
      playerNamesById: remote.playerNamesById,
      teamNamesById: remote.teamNamesById,
    );
    setState(() {
      _state = derived;
      _isRemoteLive = true;
      if (!_userPickedInnings) {
        _selectedInnings = derived.activeInningsNumber;
      }
      _loading = false;
    });
    _subscribeRemoteUpdates();
  }

  void _subscribeRemoteUpdates() {
    if (_realtimeChannel != null) return;
    try {
      final client = Supabase.instance.client;
      _realtimeChannel = client
          .channel('scorecard-${widget.matchId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'ball_events',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'match_id',
              value: widget.matchId,
            ),
            callback: (_) => _refreshRemote(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'matches',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: widget.matchId,
            ),
            callback: (_) => _refreshRemote(),
          )
          .subscribe();
    } catch (_) {}
  }

  Future<void> _refreshRemote() async {
    final remote =
        await LocalEventStore.instance.fetchRemoteMatch(widget.matchId);
    if (!mounted || remote == null) return;
    final derived = CricketEngine.derive(
      remote.config,
      remote.events,
      playerNamesById: remote.playerNamesById,
      teamNamesById: remote.teamNamesById,
    );
    setState(() {
      _state = derived;
      if (!_userPickedInnings) {
        _selectedInnings = derived.activeInningsNumber;
      }
    });
  }

  Future<void> _shareFullScorecard(DerivedMatchState state) async {
    await MatchSummaryPoster.shareMatch(state);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    if (_loading) {
      return Scaffold(
        backgroundColor: c.ground,
        appBar: AppBar(title: const Text('Match Center')),
        body: const Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              CreaseSkeletonBox(height: 140),
              SizedBox(height: 14),
              CreaseSkeletonBox(height: 92),
              SizedBox(height: 14),
              CreaseSkeletonBox(height: 180),
            ],
          ),
        ),
      );
    }

    final state = _state;
    if (state == null) {
      return Scaffold(
        backgroundColor: c.ground,
        appBar: AppBar(title: const Text('Match Center')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Match not found yet. Ask the scorer to sync online and try again.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final playedInnings = state.allInnings
        .where((i) => i.legalBalls > 0 || i.isDeclared || i.inningsNumber == state.activeInningsNumber)
        .toList();
    final hasBothInnings = playedInnings.length > 1;
    final shownInnings = state.inningsByNumber(_selectedInnings);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: c.ground,
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Match Center'),
              if (_isRemoteLive && state.resultSummary == null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.pitchGreenSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CreaseLiveDot(size: 6),
                      const SizedBox(width: 5),
                      Text(
                        'Live',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: c.pitchGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Share match summary & live link',
              icon: const Icon(Icons.share_rounded),
              onPressed: () => _shareFullScorecard(state),
            ),
          ],
          bottom: TabBar(
            labelColor: c.inkPrimary,
            indicatorColor: c.pitchGreen,
            indicatorWeight: 2.5,
            unselectedLabelColor: c.inkSecondary,
            dividerColor: c.hairlineSubtle,
            labelStyle: Theme.of(context).textTheme.titleSmall,
            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Scorecard'),
              Tab(text: 'Charts'),
              Tab(text: 'Overs'),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: TabBarView(
          children: [
            _OverviewTab(state: state, innings: shownInnings),
            _ScorecardTab(
              state: state,
              innings: shownInnings,
              hasBothInnings: hasBothInnings,
              selectedInnings: _selectedInnings,
              onSelectInnings: (v) => setState(() {
                _userPickedInnings = true;
                _selectedInnings = v;
              }),
            ),
            _ChartsTab(
              state: state,
              innings: shownInnings,
              hasBothInnings: hasBothInnings,
              selectedInnings: _selectedInnings,
              onSelectInnings: (v) => setState(() {
                _userPickedInnings = true;
                _selectedInnings = v;
              }),
            ),
            _OversTab(
              state: state,
              innings: shownInnings,
              hasBothInnings: hasBothInnings,
              selectedInnings: _selectedInnings,
              onSelectInnings: (v) => setState(() => _selectedInnings = v),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.state, required this.innings});

  final DerivedMatchState state;
  final DerivedInningsState innings;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final mvpList = StatsEngine.byMvp(
      StatsEngine.derive(
        [state],
        playerNamesById: state.resolvedPlayerNames,
      ),
    );
    final mvp = mvpList.isNotEmpty ? mvpList.first : null;

    final allBatters = [
      for (final inn in state.allInnings) ...inn.batters,
    ]..sort((a, b) => b.runs.compareTo(a.runs));
    final allBowlers = [
      for (final inn in state.allInnings) ...inn.bowlers,
    ]..sort((a, b) {
        final w = b.wickets.compareTo(a.wickets);
        return w != 0 ? w : a.economy.compareTo(b.economy);
      });
    final topBatters = allBatters;
    final topBowlers = allBowlers;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        // Hero score summary (shows both teams cleanly)
        GlassSurface(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${state.config.title} · ${state.config.formatLabel}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 10),
              for (final inn in state.allInnings)
                if (inn.legalBalls > 0 ||
                    inn.isDeclared ||
                    inn.inningsNumber == state.activeInningsNumber) ...[
                  _OverviewScoreRow(
                    team: state.config.isTestMatch
                        ? '${inn.battingTeam} (${inn.inningsNumber})'
                        : inn.battingTeam,
                    score: inn.scoreText,
                    overs: '${inn.oversText} ov',
                    isActive: inn.inningsNumber == state.activeInningsNumber,
                  ),
                  const SizedBox(height: 6),
                ],
              const SizedBox(height: 8),
              if (state.resultSummary != null)
                Text(
                  state.resultSummary!,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: c.pitchGreen),
                )
              else if (innings.runsNeeded != null)
                Text(
                  '${innings.battingTeam} need ${innings.runsNeeded} from ${innings.ballsRemaining} balls · RRR ${innings.requiredRunRate?.toStringAsFixed(1) ?? '-'}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: c.pitchGreen, fontWeight: FontWeight.w600),
                )
              else
                Text(
                  state.config.isTestMatch || innings.oversLimit <= 0
                      ? 'CRR ${innings.currentRunRate.toStringAsFixed(2)}'
                      : 'CRR ${innings.currentRunRate.toStringAsFixed(2)} · ${innings.ballsRemaining} balls left',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
            ],
          ),
        ),

        if (mvp != null) ...[
          const SizedBox(height: 16),
          const _SectionTitle('Match MVP'),
          GlassSurface(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CreaseTeamBadge(
                  name: mvp.name,
                  size: 40,
                  highlighted: true,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mvp.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${mvp.runs} (${mvp.ballsFaced}) · ${mvp.wickets} wkts · ${mvp.fieldingDismissals} fielding',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Text(
                  '${mvp.mvpPoints} pts',
                  style: creaseNumeralStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: c.pitchGreen,
                  ),
                ),
              ],
            ),
          ),
        ],

        if (topBatters.isNotEmpty || topBowlers.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _SectionTitle('Top performers'),
          GlassSurface(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final b in topBatters.take(2))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          b.isOut ? b.name : '${b.name} *',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        Text(
                          '${b.runs} (${b.balls}) · SR ${b.strikeRate.toStringAsFixed(0)}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
                if (topBatters.isNotEmpty && topBowlers.isNotEmpty)
                  const Divider(height: 16),
                for (final bw in topBowlers.take(2))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          bw.name,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        Text(
                          '${bw.figuresText} · Econ ${bw.economy.toStringAsFixed(1)}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],

        // Match Info & Squads (cleanly integrated so there's no empty Info tab)
        const SizedBox(height: 16),
        const _SectionTitle('Match info & squads'),
        GlassSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(
                'Format',
                state.config.isTestMatch || state.config.oversLimit <= 0
                    ? '${state.config.formatLabel} (Unlimited overs)'
                    : '${state.config.formatLabel} (${state.config.oversLimit} overs)',
              ),
              const Divider(height: 14),
              _InfoRow('Players / side', '${state.config.playersPerSide}'),
              const Divider(height: 14),
              _InfoRow(
                'Status',
                state.unsyncedCount == 0
                    ? 'Backed up'
                    : 'Offline · ${state.unsyncedCount} pending',
              ),
              if (state.config.teamAPlayerIds.isNotEmpty) ...[
                const Divider(height: 16),
                Text(state.config.teamA,
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 6),
                Text(
                  state.config.teamAPlayerIds
                      .map((id) => state.resolvedPlayerNames[id] ?? '')
                      .where((n) => n.isNotEmpty)
                      .join(' · '),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              if (state.config.teamBPlayerIds.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(state.config.teamB,
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 6),
                Text(
                  state.config.teamBPlayerIds
                      .map((id) => state.resolvedPlayerNames[id] ?? '')
                      .where((n) => n.isNotEmpty)
                      .join(' · '),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ScorecardTab extends StatelessWidget {
  const _ScorecardTab({
    required this.state,
    required this.innings,
    required this.hasBothInnings,
    required this.selectedInnings,
    required this.onSelectInnings,
  });

  final DerivedMatchState state;
  final DerivedInningsState innings;
  final bool hasBothInnings;
  final int selectedInnings;
  final ValueChanged<int> onSelectInnings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        if (hasBothInnings) ...[
          _InningsSwitcher(
            state: state,
            selectedInnings: selectedInnings,
            onSelect: onSelectInnings,
          ),
          const SizedBox(height: 14),
        ],

        // Extras & total strip
        GlassSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${innings.battingTeam}  ${innings.scoreText} (${innings.oversText} ov)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    'CRR ${innings.currentRunRate.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Extras ${innings.extrasTotal} (wd ${innings.wides}, nb ${innings.noBalls}, b ${innings.byes}, lb ${innings.legByes})',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        const _SectionTitle('Batting'),
        GlassSurface(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            children: [
              const _ScorecardHeaderRow(
                col0: 'Batter',
                cols: ['R', 'B', '4s', '6s', 'SR'],
              ),
              const Divider(height: 14),
              for (final b in innings.batters) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlayerProfileScreen(
                        playerName: b.name,
                        playerId: b.playerId.isNotEmpty ? b.playerId : null,
                        teams: [innings.battingTeam],
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ScorecardDataRow(
                          label: b.isOut ? b.name : '${b.name} *',
                          isHighlight: !b.isOut,
                          values: [
                            '${b.runs}',
                            '${b.balls}',
                            '${b.fours}',
                            '${b.sixes}',
                            b.strikeRate.toStringAsFixed(0),
                          ],
                        ),
                        if (b.dismissalText != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              b.dismissalText!,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (b != innings.batters.last) const Divider(height: 10),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),
        const _SectionTitle('Bowling'),
        GlassSurface(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            children: [
              const _ScorecardHeaderRow(
                col0: 'Bowler',
                cols: ['O', 'M', 'R', 'W', 'Econ'],
              ),
              const Divider(height: 14),
              for (final bw in innings.bowlers) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlayerProfileScreen(
                        playerName: bw.name,
                        playerId: bw.playerId.isNotEmpty ? bw.playerId : null,
                        teams: [innings.bowlingTeam],
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _ScorecardDataRow(
                      label: bw.name,
                      values: [
                        bw.oversText,
                        '${bw.maidens}',
                        '${bw.runsConceded}',
                        '${bw.wickets}',
                        bw.economy.toStringAsFixed(1),
                      ],
                    ),
                  ),
                ),
                if (bw != innings.bowlers.last) const Divider(height: 10),
              ],
            ],
          ),
        ),

        if (innings.fallOfWickets.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _SectionTitle('Fall of wickets'),
          GlassSurface(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              children: [
                for (var i = 0; i < innings.fallOfWickets.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text(
                            '${innings.fallOfWickets[i].wicketNumber}',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            innings.fallOfWickets[i].batterName,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                        Text(
                          '${innings.fallOfWickets[i].runsAtFall} (${innings.fallOfWickets[i].oversAtFall})',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
                  if (i != innings.fallOfWickets.length - 1)
                    const Divider(height: 1),
                ],
              ],
            ),
          ),
        ],

        Builder(
          builder: (context) {
            final stands = MatchInsights.partnerships(innings);
            if (stands.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                const _SectionTitle('Partnerships'),
                GlassSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < stands.length; i++) ...[
                        _PartnershipContributionRow(segment: stands[i]),
                        if (i != stands.length - 1) const Divider(height: 14),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ChartsTab extends StatelessWidget {
  const _ChartsTab({
    required this.state,
    required this.innings,
    required this.hasBothInnings,
    required this.selectedInnings,
    required this.onSelectInnings,
  });

  final DerivedMatchState state;
  final DerivedInningsState innings;
  final bool hasBothInnings;
  final int selectedInnings;
  final ValueChanged<int> onSelectInnings;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final worm1 = MatchInsights.wormPoints(state.innings1);
    final worm2 = state.innings2 != null
        ? MatchInsights.wormPoints(state.innings2!)
        : const <({int over, int cumulativeRuns, int wickets})>[];
    final breakdown = MatchInsights.breakdown(innings);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        // 1. Worm Graph (overlays both innings with Steel Slate vs Pitch Green)
        const _SectionTitle('Worm graph (cumulative runs)'),
        GlassSurface(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  if (worm1.isNotEmpty) ...[
                    _LegendDot(
                      color: c.chartSecondary,
                      label: state.innings1.battingTeam,
                    ),
                    const SizedBox(width: 14),
                  ],
                  if (worm2.isNotEmpty && state.innings2 != null)
                    _LegendDot(
                      color: c.pitchGreen,
                      label: state.innings2!.battingTeam,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 168,
                child: CustomPaint(
                  painter: _WormPainter(
                    series1: worm1,
                    series2: worm2,
                    color1: c.chartSecondary,
                    color2: c.pitchGreen,
                    wicketColor: c.wicketRed,
                    gridColor: c.hairlineSubtle,
                    labelColor: c.inkSecondary,
                  ),
                  size: Size.infinite,
                ),
              ),
            ],
          ),
        ),

        if (hasBothInnings) ...[
          const SizedBox(height: 16),
          _InningsSwitcher(
            state: state,
            selectedInnings: selectedInnings,
            onSelect: onSelectInnings,
          ),
        ],

        const SizedBox(height: 16),

        // 2. Manhattan Chart
        const _SectionTitle('Manhattan (runs per over)'),
        GlassSurface(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: SizedBox(
            height: 138,
            child: CustomPaint(
              painter: _ManhattanPainter(
                overs: innings.overs,
                barColor: c.pitchGreen,
                wicketColor: c.wicketRed,
                gridColor: c.hairlineSubtle,
                labelColor: c.inkSecondary,
              ),
              size: Size.infinite,
            ),
          ),
        ),

        const SizedBox(height: 16),

        // 3. Scoring Breakdown (3 direct glass tiles — no nested cards)
        const _SectionTitle('Scoring breakdown'),
        Row(
          children: [
            _MiniMetric(
              label: 'Dot balls',
              value: '${breakdown.dotPercent.toStringAsFixed(0)}%',
              sub: '${breakdown.dotBalls} of ${breakdown.legalBalls}',
            ),
            const SizedBox(width: 10),
            _MiniMetric(
              label: 'Boundaries',
              value: '${breakdown.boundaryRunPercent.toStringAsFixed(0)}%',
              sub: '${breakdown.fours}×4 · ${breakdown.sixes}×6',
              highlight: true,
            ),
            const SizedBox(width: 10),
            _MiniMetric(
              label: 'Extras',
              value: '${breakdown.extrasRuns}',
              sub: 'runs',
            ),
          ],
        ),
      ],
    );
  }
}

class _OversTab extends StatelessWidget {
  const _OversTab({
    required this.state,
    required this.innings,
    required this.hasBothInnings,
    required this.selectedInnings,
    required this.onSelectInnings,
  });

  final DerivedMatchState state;
  final DerivedInningsState innings;
  final bool hasBothInnings;
  final int selectedInnings;
  final ValueChanged<int> onSelectInnings;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final nonEmptyOvers =
        innings.overs.where((o) => o.balls.isNotEmpty).toList().reversed.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        if (hasBothInnings) ...[
          _InningsSwitcher(
            state: state,
            selectedInnings: selectedInnings,
            onSelect: onSelectInnings,
          ),
          const SizedBox(height: 14),
        ],
        if (nonEmptyOvers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Center(
              child: Text(
                'No balls bowled yet.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          )
        else
          for (var i = 0; i < nonEmptyOvers.length; i++) ...[
            Builder(
              builder: (context) {
                final ov = nonEmptyOvers[i];
                final wickets = ov.balls.where((b) => b.isWicket).toList();
                return GlassSurface(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Over ${ov.overNumber} · ${ov.bowler}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            '${ov.runsInOver} run${ov.runsInOver == 1 ? '' : 's'}${ov.wicketsInOver > 0 ? ' · ${ov.wicketsInOver} wkt' : ''}',
                            style:
                                Theme.of(context).textTheme.labelMedium?.copyWith(
                                      color: ov.wicketsInOver > 0
                                          ? c.wicketRed
                                          : c.inkSecondary,
                                    ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final b in ov.balls) _SmallBallBadge(ball: b),
                        ],
                      ),
                      for (final w in wickets)
                        if (w.dismissalSummary(state.resolvedPlayerNames) != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              w.dismissalSummary(state.resolvedPlayerNames)!,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: c.wicketRed),
                            ),
                          ),
                    ],
                  ),
                );
              },
            ),
            if (i != nonEmptyOvers.length - 1) const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _OverviewScoreRow extends StatelessWidget {
  const _OverviewScoreRow({
    required this.team,
    required this.score,
    required this.overs,
    required this.isActive,
  });

  final String team;
  final String score;
  final String overs;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            team,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? c.inkPrimary : c.inkSecondary,
                ),
          ),
        ),
        Text(
          score,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? c.inkPrimary : c.inkSecondary,
              ),
        ),
        const SizedBox(width: 6),
        Text(
          overs,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _InningsSwitcher extends StatelessWidget {
  const _InningsSwitcher({
    required this.state,
    required this.selectedInnings,
    required this.onSelect,
  });

  final DerivedMatchState state;
  final int selectedInnings;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final list = state.allInnings
        .where((i) =>
            i.legalBalls > 0 ||
            i.isDeclared ||
            i.inningsNumber == state.activeInningsNumber)
        .toList();

    if (list.length == 2) {
      return CreaseSegmentedControl<int>(
        items: [
          for (final inn in list)
            (
              value: inn.inningsNumber,
              label: '${inn.battingTeam} (${inn.scoreText})',
              icon: null,
            ),
        ],
        selected: selectedInnings,
        onChanged: onSelect,
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final inn in list)
            Builder(
              builder: (chipCtx) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    !state.config.isTestMatch && inn.inningsNumber >= 3
                        ? '${inn.battingTeam} SO (${inn.scoreText})'
                        : '${inn.battingTeam} #${inn.inningsNumber} (${inn.scoreText})',
                  ),
                  selected: selectedInnings == inn.inningsNumber,
                  selectedColor: c.pitchGreen,
                  checkmarkColor: c.onPitchGreen,
                  labelStyle: TextStyle(
                    color: selectedInnings == inn.inningsNumber
                        ? c.onPitchGreen
                        : c.inkPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                  side: BorderSide(
                    color: selectedInnings == inn.inningsNumber
                        ? c.pitchGreen
                        : c.hairline,
                  ),
                  onSelected: (_) {
                    onSelect(inn.inningsNumber);
                    Scrollable.ensureVisible(
                      chipCtx,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      alignment: 0.5,
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PartnershipContributionRow extends StatelessWidget {
  const _PartnershipContributionRow({required this.segment});
  final PartnershipSegment segment;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final total = (segment.runsA + segment.runsB).clamp(1, 9999);
    final ratioA = (segment.runsA / total).clamp(0.0, 1.0);
    final ratioB = (segment.runsB / total).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      segment.batterA,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                    ),
                    Text(
                      '${segment.runsA} (${segment.ballsA})',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  children: [
                    Text(
                      '${segment.runs}${segment.isActive ? '*' : ''}',
                      style: creaseNumeralStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: segment.isActive ? c.pitchGreen : c.inkPrimary,
                      ),
                    ),
                    Text(
                      '${segment.balls}b',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      segment.batterB,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                    ),
                    Text(
                      '${segment.runsB} (${segment.ballsB})',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: ratioA,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: c.pitchGreen,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: ratioB,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: c.chartSecondary,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(2),
                        ),
                      ),
                    ),
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

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _SmallBallBadge extends StatelessWidget {
  const _SmallBallBadge({required this.ball});
  final BallEvent ball;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final isBoundary =
        !ball.isWicket && (ball.runsOffBat == 4 || ball.runsOffBat == 6);
    Color bg = c.surfaceKey;
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

    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: border),
      ),
      child: Text(
        ball.shortMark,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: fg,
              fontSize: ball.shortMark.length > 2 ? 10 : 12,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
    required this.sub,
    this.highlight = false,
  });

  final String label;
  final String value;
  final String sub;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Expanded(
      child: GlassSurface(
        borderRadius: BorderRadius.circular(CreaseRadius.card),
        borderColor: c.hairline,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Text(
              value,
              style: creaseNumeralStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: highlight ? c.pitchGreen : c.inkPrimary,
              ),
            ),
            const SizedBox(height: 3),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}

class _ScorecardHeaderRow extends StatelessWidget {
  const _ScorecardHeaderRow({required this.col0, required this.cols});
  final String col0;
  final List<String> cols;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(col0, style: Theme.of(context).textTheme.labelMedium),
        ),
        for (final col in cols)
          Expanded(
            flex: 1,
            child: Text(
              col,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
      ],
    );
  }
}

class _ScorecardDataRow extends StatelessWidget {
  const _ScorecardDataRow({
    required this.label,
    required this.values,
    this.isHighlight = false,
  });

  final String label;
  final List<String> values;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: isHighlight ? FontWeight.w600 : FontWeight.w400,
                  color: isHighlight ? c.pitchGreen : c.inkPrimary,
                ),
          ),
        ),
        for (var i = 0; i < values.length; i++)
          Expanded(
            flex: 1,
            child: Text(
              values[i],
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13.5,
                  ),
            ),
          ),
      ],
    );
  }
}

/// Lightweight CustomPainter Worm Graph (cumulative runs per over + wicket dots + axis labels).
class _WormPainter extends CustomPainter {
  const _WormPainter({
    required this.series1,
    required this.series2,
    required this.color1,
    required this.color2,
    required this.wicketColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<({int over, int cumulativeRuns, int wickets})> series1;
  final List<({int over, int cumulativeRuns, int wickets})> series2;
  final Color color1;
  final Color color2;
  final Color wicketColor;
  final Color gridColor;
  final Color labelColor;

  void _drawLabel(Canvas canvas, String text, Offset offset,
      {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: labelColor,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = align == TextAlign.right ? offset.dx - tp.width : offset.dx;
    tp.paint(canvas, Offset(dx, offset.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final all = [...series1, ...series2];
    if (all.isEmpty) return;

    const leftPad = 28.0;
    const bottomPad = 18.0;
    const topPad = 6.0;
    final chartW = size.width - leftPad;
    final chartH = size.height - bottomPad - topPad;

    final maxOvers = all.fold<int>(1, (p, e) => e.over > p ? e.over : p);
    final maxRuns = all.fold<int>(
      10,
      (p, e) => e.cumulativeRuns > p ? e.cumulativeRuns : p,
    );

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (final frac in const [0.0, 0.5, 1.0]) {
      final y = topPad + chartH * (1 - frac);
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);
      _drawLabel(
        canvas,
        '${(maxRuns * frac).round()}',
        Offset(leftPad - 6, y - 6),
        align: TextAlign.right,
      );
    }

    _drawLabel(canvas, 'Ov 1', Offset(leftPad, size.height - 13));
    if (maxOvers > 1) {
      _drawLabel(
        canvas,
        'Ov $maxOvers',
        Offset(size.width, size.height - 13),
        align: TextAlign.right,
      );
    }

    void drawSeries(
      List<({int over, int cumulativeRuns, int wickets})> pts,
      Color color,
    ) {
      if (pts.isEmpty) return;
      final linePaint = Paint()
        ..color = color
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final wktPaint = Paint()..color = wicketColor;

      final path = Path()..moveTo(leftPad, topPad + chartH);
      final fillPath = Path()..moveTo(leftPad, topPad + chartH);
      double lastX = leftPad;
      for (final p in pts) {
        final x = leftPad + (p.over / maxOvers) * chartW;
        final y = topPad + chartH - ((p.cumulativeRuns / maxRuns) * chartH);
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
        lastX = x;
      }
      fillPath
        ..lineTo(lastX, topPad + chartH)
        ..close();
      canvas.drawPath(
        fillPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.14),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromLTWH(leftPad, topPad, chartW, chartH)),
      );
      canvas.drawPath(path, linePaint);

      for (final p in pts) {
        if (p.wickets > 0) {
          final x = leftPad + (p.over / maxOvers) * chartW;
          final y = topPad + chartH - ((p.cumulativeRuns / maxRuns) * chartH);
          canvas.drawCircle(
            Offset(x, y),
            5.2,
            Paint()..color = Colors.white,
          );
          canvas.drawCircle(Offset(x, y), 3.4, wktPaint);
        }
      }
    }

    drawSeries(series1, color1);
    drawSeries(series2, color2);
  }

  @override
  bool shouldRepaint(covariant _WormPainter oldDelegate) =>
      oldDelegate.series1 != series1 || oldDelegate.series2 != series2;
}

/// Ultra-lightweight CustomPainter Manhattan chart with Y/X axis labels.
class _ManhattanPainter extends CustomPainter {
  const _ManhattanPainter({
    required this.overs,
    required this.barColor,
    required this.wicketColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<OverSummary> overs;
  final Color barColor;
  final Color wicketColor;
  final Color gridColor;
  final Color labelColor;

  void _drawLabel(Canvas canvas, String text, Offset offset,
      {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: labelColor,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = align == TextAlign.right ? offset.dx - tp.width : offset.dx;
    tp.paint(canvas, Offset(dx, offset.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (overs.isEmpty) return;
    const leftPad = 24.0;
    const bottomPad = 18.0;
    const topPad = 12.0;
    final chartW = size.width - leftPad;
    final chartH = size.height - bottomPad - topPad;

    final maxRuns = overs.fold<int>(
      6,
      (prev, o) => o.runsInOver > prev ? o.runsInOver : prev,
    );

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final frac in const [0.0, 0.5, 1.0]) {
      final y = topPad + chartH * (1 - frac);
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);
      _drawLabel(
        canvas,
        '${(maxRuns * frac).round()}',
        Offset(leftPad - 6, y - 6),
        align: TextAlign.right,
      );
    }
    _drawLabel(
      canvas,
      'Ov ${overs.first.overNumber}',
      Offset(leftPad, size.height - 13),
    );
    if (overs.length > 1) {
      _drawLabel(
        canvas,
        'Ov ${overs.last.overNumber}',
        Offset(size.width, size.height - 13),
        align: TextAlign.right,
      );
    }

    final barPaint = Paint()..color = barColor;
    final wktPaint = Paint()..color = wicketColor;
    final slotWidth = chartW / overs.length;
    final barWidth = (slotWidth * 0.56).clamp(4.0, 18.0);

    for (var i = 0; i < overs.length; i++) {
      final ov = overs[i];
      final h = (ov.runsInOver / maxRuns) * chartH;
      final left = leftPad + i * slotWidth + (slotWidth - barWidth) / 2;
      final top = topPad + chartH - h;

      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, top, barWidth, h.clamp(2.0, chartH)),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(rect, barPaint);

      for (var w = 0; w < ov.wicketsInOver; w++) {
        canvas.drawCircle(
          Offset(
            left + barWidth / 2,
            (top - 6 - w * 8).clamp(4.0, topPad + chartH),
          ),
          3.2,
          wktPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ManhattanPainter oldDelegate) =>
      oldDelegate.overs != overs;
}
