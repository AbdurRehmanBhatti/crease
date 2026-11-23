import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local_event_store.dart';
import '../../domain/cricket_engine.dart';
import '../../domain/models.dart';
import '../../domain/team_profile.dart';
import '../../domain/tournament_engine.dart';
import '../../domain/user_profile.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/glass_surface.dart';
import '../profile/profile_screen.dart';
import '../quick_match/quick_match_sheet.dart';
import '../scoring/scorer_handover_sheets.dart';
import '../scoring/scoring_screen.dart';
import '../stats/stats_tab_view.dart';
import '../teams/teams_tab_view.dart';
import '../tournaments/create_tournament_sheet.dart';
import '../tournaments/tournament_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<DerivedMatchState> _matches = [];
  List<Tournament> _tournaments = [];
  List<TeamProfile> _teams = [];
  Map<String, List<String>> _knownRosters = {};
  UserProfile _profile = const UserProfile();
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
    final tournaments = await store.listTournaments();
    final teams = await store.listTeams();
    final knownRosters = await store.listKnownTeamRosters();
    final profile = await store.getUserProfile();
    final derived = <DerivedMatchState>[];
    for (final cfg in configs) {
      final events = await store.getBallEvents(cfg.id);
      derived.add(CricketEngine.derive(cfg, events));
    }
    if (!mounted) return;
    setState(() {
      _matches = derived;
      _tournaments = tournaments;
      _teams = teams;
      _knownRosters = knownRosters;
      _profile = profile;
      _loading = false;
    });
  }

  Future<void> _createTeam() async {
    final team = await showCreateTeamSheet(context);
    if (team == null) return;
    await LocalEventStore.instance.saveTeam(team);
    LocalEventStore.instance.syncTeamToSupabase(team.id);
    _loadMatches();
  }

  Future<void> _createTournament() async {
    final tournament = await showCreateTournamentSheet(context);
    if (tournament == null) return;
    await LocalEventStore.instance.saveTournament(tournament);
    LocalEventStore.instance.syncTournamentToSupabase(tournament.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TournamentDetailScreen(tournamentId: tournament.id),
      ),
    );
    _loadMatches();
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

  Future<void> _confirmDeleteMatch(DerivedMatchState match) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${match.config.title}?'),
        content: const Text(
          'This permanently removes the match and its ball-by-ball scorecard from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.crease.wicketRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await LocalEventStore.instance.deleteMatch(match.config.id);
    _loadMatches();
  }

  Future<void> _joinAsScorer() async {
    final matchId = await showJoinAsScorerSheet(context);
    if (matchId == null || !mounted) return;
    await _openMatch(matchId);
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
    _loadMatches();
  }

  bool get _isGuestAccount {
    try {
      final email = Supabase.instance.client.auth.currentUser?.email;
      return email == null || email.trim().isEmpty;
    } catch (_) {
      return true;
    }
  }

  Future<void> _refreshAndSync() async {
    await LocalEventStore.instance.syncAllPendingToSupabase();
    await LocalEventStore.instance.pullLatestForMyTeams();
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
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: c.pitchGreen,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                        onPressed: _navIndex == 1
                            ? _createTeam
                            : _navIndex == 2
                                ? _createTournament
                                : _createQuickMatch,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(
                          _navIndex == 1
                              ? 'Team'
                              : _navIndex == 2
                                  ? 'Tournament'
                                  : 'Quick Match',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Profile & Sign in',
                        child: InkWell(
                          onTap: _openProfile,
                          borderRadius: BorderRadius.circular(22),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: c.surfaceGlass,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: c.hairline),
                                ),
                                alignment: Alignment.center,
                                child: _profile.initials.isNotEmpty
                                    ? Text(
                                        _profile.initials,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              color: c.pitchGreen,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      )
                                    : Icon(
                                        Icons.person_outline_rounded,
                                        size: 22,
                                        color: c.inkPrimary,
                                      ),
                              ),
                              if (_isGuestAccount)
                                Positioned(
                                  right: 1,
                                  top: 1,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: c.pitchGreen,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: c.ground,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
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
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: _joinAsScorer,
                              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                              label: const Text('Join as scorer with code'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 2, 12, 4),
                      child: Row(
                        children: [
                          Text(
                            'Live & recent',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const Spacer(),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: c.pitchGreen,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: _joinAsScorer,
                            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                            label: const Text('Join as scorer'),
                          ),
                        ],
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
                        onLongPress: () => _confirmDeleteMatch(m),
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
              ] else if (_navIndex == 1)
                TeamsTabView(
                  savedTeams: _teams,
                  knownRosters: _knownRosters,
                  matches: _matches,
                  onChanged: _loadMatches,
                )
              else if (_navIndex == 2) ...[
                if (_tournaments.isEmpty)
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
                                Icons.emoji_events_outlined,
                                size: 32,
                                color: c.pitchGreen,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No tournaments yet',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Create a tournament to get an auto-calculated Points Table and ICC Net Run Rate.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: c.pitchGreen,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _createTournament,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('New Tournament'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 6, 20, 8),
                      child: Text(
                        'Your tournaments',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    sliver: SliverList.separated(
                      itemCount: _tournaments.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final t = _tournaments[index];
                        return GestureDetector(
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    TournamentDetailScreen(tournamentId: t.id),
                              ),
                            );
                            _loadMatches();
                          },
                          child: GlassSurface(
                            padding: const EdgeInsets.all(18),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${t.teams.length} teams · ${t.formatLabel} (${t.oversLimit} overs)',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: c.inkSecondary,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ] else
                StatsTabView(
                  matches: _matches,
                  tournaments: _tournaments,
                  savedTeams: _teams,
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
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.sports_cricket_outlined),
            selectedIcon: Icon(Icons.sports_cricket_rounded, color: c.pitchGreen),
            label: 'Matches',
          ),
          NavigationDestination(
            icon: const Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups_rounded, color: c.pitchGreen),
            label: 'Teams',
          ),
          NavigationDestination(
            icon: const Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events_rounded, color: c.pitchGreen),
            label: 'Tournaments',
          ),
          NavigationDestination(
            icon: const Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded, color: c.pitchGreen),
            label: 'Stats',
          ),
        ],
      ),
    );
  }
}

