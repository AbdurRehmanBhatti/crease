import 'package:flutter/material.dart';

import '../../data/local_event_store.dart';
import '../../domain/cricket_engine.dart';
import '../../domain/models.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/glass_surface.dart';
import '../quick_match/quick_match_sheet.dart';
import '../scoring/scoring_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<DerivedMatchState> _matches = [];
  bool _loading = true;
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    final store = LocalEventStore.instance;
    final configs = await store.listMatches();
    final derived = <DerivedMatchState>[];
    for (final cfg in configs) {
      final events = await store.getBallEvents(cfg.id);
      derived.add(CricketEngine.derive(cfg, events));
    }
    if (!mounted) return;
    setState(() {
      _matches = derived;
      _loading = false;
    });
  }

  Future<void> _createQuickMatch() async {
    final config = await showQuickMatchSheet(context);
    if (config == null) return;
    await LocalEventStore.instance.saveMatch(config);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScoringScreen(matchId: config.id)),
    );
    _loadMatches();
  }

  Future<void> _openMatch(String matchId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScoringScreen(matchId: matchId)),
    );
    _loadMatches();
  }

  Future<void> _refreshAndSync() async {
    await LocalEventStore.instance.syncAllPendingToSupabase();
    await _loadMatches();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;

    return Scaffold(
      backgroundColor: c.ground,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: const Alignment(0, -0.35),
            colors: [c.sageWashTop, c.ground],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            color: c.pitchGreen,
            onRefresh: _refreshAndSync,
            child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Crease',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.8,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Live cricket scorer',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: c.pitchGreen,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        onPressed: _createQuickMatch,
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: const Text('Quick Match'),
                      ),
                    ],
                  ),
                ),
              ),
              if (_navIndex == 0) ...[
                if (_loading)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_matches.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'No matches yet',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Start a Quick Match in 3 taps. Every ball is saved locally first.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 6, 20, 8),
                      child: Text(
                        'Live & recent',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    sliver: SliverList.separated(
                    itemCount: _matches.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final m = _matches[index];
                      final inn = m.activeInnings;
                      return GestureDetector(
                        onTap: () => _openMatch(m.config.id),
                        child: GlassSurface(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (m.status == MatchStatus.live) ...[
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
                                  Expanded(
                                    child: Text(
                                      m.config.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                  if (m.config.isDemo)
                                    Container(
                                      margin: const EdgeInsets.only(right: 6),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: c.pitchGreenSoft,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'DEMO',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              fontSize: 10,
                                              color: c.pitchGreen,
                                            ),
                                      ),
                                    ),
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            fontSize: 11,
                                            color: c.inkPrimary,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    inn.scoreText,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(fontSize: 32),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '${inn.oversText} overs',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  const Spacer(),
                                  if (m.unsyncedCount > 0)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.cloud_off_rounded,
                                          size: 14,
                                          color: c.inkSecondary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Saved locally',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium,
                                        ),
                                      ],
                                    )
                                  else
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.cloud_done_outlined,
                                          size: 15,
                                          color: c.pitchGreen,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Synced',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(color: c.pitchGreen),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              if (inn.runsNeeded != null &&
                                  m.status == MatchStatus.live) ...[
                                const SizedBox(height: 6),
                                Text(
                                  '${inn.battingTeam} need ${inn.runsNeeded} from ${inn.ballsRemaining} balls',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ] else if (m.resultSummary != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  m.resultSummary!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: c.pitchGreen),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                ],
              ] else
                SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: GlassSurface(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _navIndex == 1
                                  ? Icons.emoji_events_outlined
                                  : Icons.insights_rounded,
                              size: 32,
                              color: c.pitchGreen,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _navIndex == 1
                                  ? 'Tournaments & Auto NRR'
                                  : 'Career Stats & Leaderboards',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _navIndex == 1
                                  ? 'Coming in Phase 2 — points tables and Net Run Rate derived straight from the ball log.'
                                  : 'Coming in Phase 2 — batting averages, strike rates, bowling economy, and MVP rankings.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        backgroundColor: c.surfaceSheet,
        indicatorColor: c.pitchGreenSoft,
        onDestinationSelected: (i) => setState(() => _navIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sports_cricket_outlined),
            selectedIcon: Icon(Icons.sports_cricket_rounded),
            label: 'Matches',
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events_rounded),
            label: 'Tournaments',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Stats',
          ),
        ],
      ),
    );
  }
}

