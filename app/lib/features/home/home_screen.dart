import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local_event_store.dart';
import '../../domain/models.dart';
import '../../domain/roster_sync_planner.dart';
import '../../domain/team_profile.dart';
import '../../domain/tournament_engine.dart';
import '../../domain/user_profile.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/crease_ui.dart';
import '../../widgets/glass_surface.dart';
import '../auth/auth_sheet.dart';
import '../live/live_tab_view.dart';
import '../profile/profile_screen.dart';
import '../quick_match/quick_match_sheet.dart';
import '../scorecard/scorecard_screen.dart';
import '../scoring/scorer_handover_sheets.dart';
import '../scoring/scoring_screen.dart';
import '../search/search_screen.dart';
import '../teams/teams_tab_view.dart';
import '../tournaments/create_tournament_sheet.dart';
import '../tournaments/tournament_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _resumeThrottle = ResumeSyncThrottle();
  List<DerivedMatchState> _matches = [];
  List<Tournament> _tournaments = [];
  List<TeamProfile> _teams = [];
  Map<String, List<String>> _knownRosters = {};
  UserProfile _profile = const UserProfile();
  bool _loading = true;
  int _navIndex = 0;
  int _publicLiveCount = 0;
  bool _refreshingRostersOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LocalEventStore.instance.directoryNotifier.addListener(_onDirectoryChanged);
    _loadMatches();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LocalEventStore.instance.directoryNotifier
        .removeListener(_onDirectoryChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (!_resumeThrottle.shouldSync()) return;
    unawaited(_refreshRostersOnResume());
  }

  Future<void> _refreshRostersOnResume() async {
    if (_refreshingRostersOnResume) return;
    _refreshingRostersOnResume = true;
    try {
      await LocalEventStore.instance.pullRostersForLocalTeams();
      _resumeThrottle.markSynced();
    } finally {
      _refreshingRostersOnResume = false;
    }
  }

  void _onDirectoryChanged() {
    if (!mounted || _loading) return;
    _loadMatches();
  }

  Map<String, List<String>> _deriveKnownRosters(
    List<TeamProfile> teams,
    List<Tournament> tournaments,
    List<DerivedMatchState> matches,
  ) {
    final rosters = <String, List<String>>{};
    void merge(String teamName, List<String> players) {
      final key = teamName.trim();
      if (key.isEmpty) return;
      final list = rosters.putIfAbsent(key, () => <String>[]);
      for (final p in players) {
        final trimmed = p.trim();
        if (trimmed.isEmpty ||
            LocalEventStore.isPlaceholderPlayerName(trimmed)) {
          continue;
        }
        if (!list.any((e) => e.toLowerCase() == trimmed.toLowerCase())) {
          list.add(trimmed);
        }
      }
    }

    for (final t in teams) {
      merge(t.name, t.players);
    }
    final savedNameById = {for (final t in teams) t.id: t.name};
    final dir = LocalEventStore.instance.directory;
    for (final m in matches) {
      final aNames = m.config.teamAPlayerIds
          .map((id) => dir.resolvePlayerName(id, adHocPlayers: m.config.adHocPlayers))
          .where((n) => n.isNotEmpty)
          .toList();
      final bNames = m.config.teamBPlayerIds
          .map((id) => dir.resolvePlayerName(id, adHocPlayers: m.config.adHocPlayers))
          .where((n) => n.isNotEmpty)
          .toList();
      if (m.config.teamAId == null) {
        if (!m.config.teamA.trim().endsWith('(2)')) {
          merge(m.config.teamA, aNames);
        }
      } else if (savedNameById.containsKey(m.config.teamAId)) {
        merge(savedNameById[m.config.teamAId]!, aNames);
      }
      if (m.config.teamBId == null) {
        if (!m.config.teamB.trim().endsWith('(2)')) {
          merge(m.config.teamB, bNames);
        }
      } else if (savedNameById.containsKey(m.config.teamBId)) {
        merge(savedNameById[m.config.teamBId]!, bNames);
      }
    }
    return rosters;
  }

  Future<void> _loadMatches() async {
    final store = LocalEventStore.instance;
    await store.refreshDirectory();
    final configs = await store.listMatches();
    final tournaments = await store.listTournaments();
    final teams = await store.listTeams();
    final profile = await store.getUserProfile();
    final derived = <DerivedMatchState>[];
    for (final cfg in configs) {
      final events = await store.getBallEvents(cfg.id);
      derived.add(store.deriveMatch(cfg, events));
    }
    final knownRosters = _deriveKnownRosters(teams, tournaments, derived);
    if (!mounted) return;
    setState(() {
      _matches = derived;
      _tournaments = tournaments;
      _teams = teams;
      _knownRosters = knownRosters;
      _profile = profile;
      _loading = false;
    });
    _refreshPublicLiveCount();
  }

  Future<void> _refreshPublicLiveCount() async {
    final count = await LocalEventStore.instance.fetchPublicLiveCount();
    if (!mounted) return;
    if (count != _publicLiveCount) {
      setState(() => _publicLiveCount = count);
    }
  }

  Future<void> _toggleMatchVisibility(DerivedMatchState match) async {
    final goPublic = !match.config.isPublicLive;
    if (goPublic && !isSignedInAccount()) {
      final ok = await requireSignedInAccount(
        context,
        title: 'Sign in to broadcast live',
        subtitle:
            'Public matches sync live to the Crease Live tab under your account.',
      );
      if (!ok || !mounted) return;
    }
    final nextVis = goPublic
        ? BroadcastVisibility.public
        : BroadcastVisibility.unlisted;
    await LocalEventStore.instance.setMatchVisibility(
      match.config.id,
      nextVis,
    );
    await _refreshSingleMatch(match.config.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            goPublic
                ? 'Match is now public on the Live tab.'
                : 'Match switched to Unlisted (link only).',
          ),
        ),
      );
    _refreshPublicLiveCount();
  }

  Future<void> _refreshProfileOnly() async {
    final profile = await LocalEventStore.instance.getUserProfile();
    if (!mounted) return;
    setState(() => _profile = profile);
  }

  Future<void> _refreshTeamsOnly() async {
    final teams = await LocalEventStore.instance.listTeams();
    if (!mounted) return;
    setState(() {
      _teams = teams;
      _knownRosters = _deriveKnownRosters(teams, _tournaments, _matches);
    });
  }

  Future<void> _refreshSingleMatch(String matchId) async {
    final store = LocalEventStore.instance;
    final cfg = await store.getMatch(matchId);
    final nextMatches = List<DerivedMatchState>.from(_matches);
    final existingIdx = nextMatches.indexWhere((m) => m.config.id == matchId);
    if (cfg == null) {
      if (existingIdx >= 0) nextMatches.removeAt(existingIdx);
    } else {
      final events = await store.getBallEvents(cfg.id);
      final derived = store.deriveMatch(cfg, events);
      if (existingIdx >= 0) {
        nextMatches[existingIdx] = derived;
      } else {
        nextMatches.insert(0, derived);
      }
    }
    // Also pick up any newly created follow-up match (e.g. Super Over).
    final knownIds = nextMatches.map((m) => m.config.id).toSet();
    final allConfigs = await store.listMatches();
    for (final c in allConfigs) {
      if (!knownIds.contains(c.id)) {
        final ev = await store.getBallEvents(c.id);
        nextMatches.insert(0, store.deriveMatch(c, ev));
      }
    }
    if (!mounted) return;
    setState(() {
      _matches = nextMatches;
      _knownRosters = _deriveKnownRosters(_teams, _tournaments, nextMatches);
    });
  }

  Future<void> _refreshTournament(String tournamentId) async {
    final store = LocalEventStore.instance;
    final tournaments = await store.listTournaments();
    final tConfigs = await store.listMatchesForTournament(tournamentId);
    final refreshed = <DerivedMatchState>[];
    for (final cfg in tConfigs) {
      final events = await store.getBallEvents(cfg.id);
      refreshed.add(store.deriveMatch(cfg, events));
    }
    final nextMatches = _matches
        .where((m) => m.config.tournamentId != tournamentId)
        .toList()
      ..addAll(refreshed)
      ..sort((a, b) => b.config.createdAt.compareTo(a.config.createdAt));
    if (!mounted) return;
    setState(() {
      _tournaments = tournaments;
      _matches = nextMatches;
      _knownRosters = _deriveKnownRosters(_teams, tournaments, nextMatches);
    });
  }

  Future<void> _createTeam() async {
    final team = await showCreateTeamSheet(
      context,
      existingTeamNames: _teams.map((t) => t.name).toList(),
    );
    if (team == null) return;
    await LocalEventStore.instance.saveTeam(team);
    LocalEventStore.instance.syncTeamToSupabase(team.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeamDetailScreen(
          teamName: team.name,
          savedProfile: team,
          initialRoster: team.players,
          matches: _matches,
        ),
      ),
    );
    _refreshTeamsOnly();
  }

  Future<void> _createTournament() async {
    final ok = await requireSignedInAccount(
      context,
      title: 'Sign in to create a tournament',
      subtitle:
          'Tournaments sync standings, NRR, and fixtures across participating teams.',
    );
    if (!ok || !mounted) return;
    final tournament = await showCreateTournamentSheet(context);
    if (tournament == null || !mounted) return;
    setState(() {
      _tournaments = [
        tournament,
        ..._tournaments.where((t) => t.id != tournament.id),
      ];
    });
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TournamentDetailScreen(tournamentId: tournament.id),
      ),
    );
    _refreshTournament(tournament.id);
  }

  Future<void> _createQuickMatch() async {
    final myTeam = _teams.where((t) => t.isMyTeam).firstOrNull?.name;
    final config = await showQuickMatchSheet(
      context,
      initialKnownTeams: _knownRosters,
      defaultMyTeamName: myTeam,
    );
    if (config == null) return;
    await LocalEventStore.instance.saveMatch(config);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScoringScreen(matchId: config.id)),
    );
    _refreshSingleMatch(config.id);
  }

  Future<void> _openMatch(String matchId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScoringScreen(matchId: matchId)),
    );
    _refreshSingleMatch(matchId);
  }

  Future<void> _openScorecard(String matchId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScorecardScreen(matchId: matchId)),
    );
    _refreshSingleMatch(matchId);
  }

  Future<void> _confirmDeleteMatch(DerivedMatchState match) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${match.config.title}?'),
        content: const Text(
          'This removes the match and its ball-by-ball scorecard from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.crease.wicketRed,
              foregroundColor: context.crease.onWicketRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await LocalEventStore.instance.deleteMatch(match.config.id);
    _refreshSingleMatch(match.config.id);
  }

  Future<void> _joinAsScorer() async {
    final ok = await requireSignedInAccount(
      context,
      title: 'Sign in to join as a scorer',
      subtitle: 'Co-scoring syncs live balls across devices under your account.',
    );
    if (!ok || !mounted) return;
    final matchId = await showJoinAsScorerSheet(context);
    if (matchId == null || !mounted) return;
    await _openMatch(matchId);
  }

  Future<void> _openSearch() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          localMatches: _matches,
          localTeams: _teams,
          localTournaments: _tournaments,
        ),
      ),
    );
    if (!mounted) return;
    _loadMatches();
  }

  Future<void> _openProfile() async {
    final versionBefore = LocalEventStore.accountDataVersion.value;
    String? uidBefore;
    try {
      uidBefore = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {}

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
    if (!mounted) return;

    String? uidAfter;
    try {
      uidAfter = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {}

    if (LocalEventStore.accountDataVersion.value != versionBefore ||
        uidAfter != uidBefore) {
      await _loadMatches();
    } else {
      await _refreshProfileOnly();
    }
  }

  bool get _isGuestAccount => !isSignedInAccount();

  Future<void> _refreshAndSync() async {
    await LocalEventStore.instance.syncAllPendingToSupabase();
    await LocalEventStore.instance.pullLatestForMyTeams();
    await _loadMatches();
  }

  String get _tabHeading => switch (_navIndex) {
        1 => 'Live',
        2 => 'My Teams',
        3 => 'My Tournaments',
        _ => 'Crease',
      };

  Widget _buildHeaderSliver(BuildContext context, CreaseThemeExtension c) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          children: [
            if (_navIndex == 0) ...[
              const CreaseMark(size: 28),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                _tabHeading,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                    ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Search Crease',
              child: CreasePressable(
                onTap: _openSearch,
                borderRadius: BorderRadius.circular(CreaseRadius.control),
                scale: 0.94,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: c.surfaceGlass,
                        borderRadius:
                            BorderRadius.circular(CreaseRadius.control),
                        border: Border.all(color: c.hairline),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: c.inkPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Profile & account',
              child: CreasePressable(
                onTap: _openProfile,
                borderRadius: BorderRadius.circular(CreaseRadius.control),
                scale: 0.94,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: c.surfaceGlass,
                            borderRadius:
                                BorderRadius.circular(CreaseRadius.control),
                            border: Border.all(color: c.hairline),
                          ),
                          alignment: Alignment.center,
                          child: (_profile.avatarUrl != null &&
                                  _profile.avatarUrl!.isNotEmpty)
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    CreaseRadius.control - 1,
                                  ),
                                  child: Image.network(
                                    _profile.avatarUrl!,
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        _avatarFallback(context, c),
                                  ),
                                )
                              : _avatarFallback(context, c),
                        ),
                        if (_isGuestAccount)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: c.pitchGreen,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: c.ground,
                                  width: 2,
                                ),
                              ),
                            ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final liveMatches =
        _matches.where((m) => m.status != MatchStatus.completed).toList();
    final recentMatches =
        _matches.where((m) => m.status == MatchStatus.completed).toList();

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: _navIndex == 1
            ? LiveTabView(
                headerSliver: _buildHeaderSliver(context, c),
                onLiveCountChanged: (count) {
                  if (!mounted || count == _publicLiveCount) return;
                  setState(() => _publicLiveCount = count);
                },
                onStartMatch: () {
                  setState(() => _navIndex = 0);
                  _createQuickMatch();
                },
              )
            : RefreshIndicator(
                color: c.pitchGreen,
                backgroundColor: c.surfaceGlass,
                onRefresh: _refreshAndSync,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    _buildHeaderSliver(context, c),
              if (_navIndex == 0) ...[
                if (_loading)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                    sliver: SliverList.separated(
                      itemCount: 3,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, _) => const CreaseSkeletonBox(height: 132),
                    ),
                  )
                else if (_matches.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: GlassSurface(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CreaseMark(size: 40),
                              const SizedBox(height: 16),
                              Text(
                                'No matches yet',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Start a quick match or join an active game with a scorer code.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _createQuickMatch,
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('Start match'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _joinAsScorer,
                                  icon: const Icon(
                                    Icons.swap_horiz_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Join with scorer code'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                else ...[
                  if (liveMatches.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 2, 12, 8),
                        child: Row(
                          children: [
                            Text(
                              'In progress',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const Spacer(),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: _joinAsScorer,
                              icon: const Icon(
                                Icons.swap_horiz_rounded,
                                size: 17,
                              ),
                              label: const Text('Join scorer'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                      sliver: SliverList.separated(
                        itemCount: liveMatches.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) => _MatchScoreCard(
                          match: liveMatches[index],
                          onTap: () => _openMatch(liveMatches[index].config.id),
                          onOpenScoring: () =>
                              _openMatch(liveMatches[index].config.id),
                          onOpenScorecard: () =>
                              _openScorecard(liveMatches[index].config.id),
                          onToggleVisibility: () =>
                              _toggleMatchVisibility(liveMatches[index]),
                          onDelete: () =>
                              _confirmDeleteMatch(liveMatches[index]),
                        ),
                      ),
                    ),
                  ],
                  if (recentMatches.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 2, 12, 8),
                        child: Row(
                          children: [
                            Text(
                              'Completed',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const Spacer(),
                            if (liveMatches.isEmpty)
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: _joinAsScorer,
                                icon: const Icon(
                                  Icons.swap_horiz_rounded,
                                  size: 17,
                                ),
                                label: const Text('Join scorer'),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                      sliver: SliverList.separated(
                        itemCount: recentMatches.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) => _MatchScoreCard(
                          match: recentMatches[index],
                          onTap: () =>
                              _openScorecard(recentMatches[index].config.id),
                          onOpenScoring: () =>
                              _openMatch(recentMatches[index].config.id),
                          onOpenScorecard: () =>
                              _openScorecard(recentMatches[index].config.id),
                          onDelete: () =>
                              _confirmDeleteMatch(recentMatches[index]),
                        ),
                      ),
                    ),
                  ],
                ],
              ] else if (_navIndex == 2)
                TeamsTabView(
                  savedTeams: _teams,
                  knownRosters: _knownRosters,
                  matches: _matches,
                  onChanged: _loadMatches,
                )
              else if (_navIndex == 3) ...[
                if (_tournaments.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: GlassSurface(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: c.pitchGreenSoft,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.emoji_events_outlined,
                                  size: 22,
                                  color: c.pitchGreen,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'No tournaments yet',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Group fixtures together to track standings, points, and Net Run Rate.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _createTournament,
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('New tournament'),
                                ),
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
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                      child: Text(
                        '${_tournaments.length} tournament${_tournaments.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                    sliver: SliverList.separated(
                      itemCount: _tournaments.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final t = _tournaments[index];
                        final tMatches = _matches
                            .where((m) => m.config.tournamentId == t.id)
                            .toList();
                        final overview =
                            TournamentEngine.deriveOverview(t, tMatches);
                        final subtitle = overview.champion != null
                            ? 'Champion: ${overview.champion} · ${t.formatLabel}'
                            : overview.totalPlannedMatches > 0
                                ? '${t.structure.shortLabel} · ${overview.completedTotalCount}/${overview.totalPlannedMatches} matches · ${t.formatLabel}'
                                : '${t.teams.length} team${t.teams.length == 1 ? '' : 's'} · ${tMatches.length} match${tMatches.length == 1 ? '' : 'es'} · ${t.formatLabel}';
                        return CreasePressable(
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    TournamentDetailScreen(tournamentId: t.id),
                              ),
                            );
                            _refreshTournament(t.id);
                          },
                          child: GlassSurface(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                CreaseTournamentBadge(
                                  size: 40,
                                  hasChampion: overview.champion != null,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: overview.champion != null
                                                  ? c.pitchGreen
                                                  : c.inkSecondary,
                                              fontWeight:
                                                  overview.champion != null
                                                      ? FontWeight.w600
                                                      : FontWeight.w400,
                                            ),
                                      ),
                                      if ((t.location != null &&
                                              t.location!.isNotEmpty) ||
                                          t.dateRangeLabel != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          [
                                            if (t.location != null &&
                                                t.location!.isNotEmpty)
                                              t.location!,
                                            if (t.dateRangeLabel != null)
                                              t.dateRangeLabel!,
                                          ].join(' · '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: c.inkSecondary),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 20,
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
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: (!_loading &&
              ((_navIndex == 0 && _matches.isNotEmpty) ||
                  (_navIndex == 2 && _teams.isNotEmpty) ||
                  (_navIndex == 3 && _tournaments.isNotEmpty)))
          ? FloatingActionButton.extended(
              backgroundColor: c.pitchGreen,
              foregroundColor: c.onPitchGreen,
              elevation: 2,
              onPressed: _navIndex == 2
                  ? _createTeam
                  : _navIndex == 3
                      ? _createTournament
                      : _createQuickMatch,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(
                _navIndex == 2
                    ? 'New team'
                    : _navIndex == 3
                        ? 'New tournament'
                        : 'New match',
              ),
            )
          : null,
      bottomNavigationBar: _CreaseBottomNav(
        selectedIndex: _navIndex,
        hasActiveLive: _publicLiveCount > 0,
        onSelect: (i) {
          if (i == _navIndex) return;
          HapticFeedback.selectionClick();
          setState(() => _navIndex = i);
        },
      ),
    );
  }

  Widget _avatarFallback(BuildContext context, CreaseThemeExtension c) {
    if (_profile.initials.isNotEmpty) {
      return Text(
        _profile.initials,
        style: creaseNumeralStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: c.pitchGreen,
        ),
      );
    }
    return Icon(
      Icons.person_outline_rounded,
      size: 20,
      color: c.inkPrimary,
    );
  }
}

class _MatchScoreCard extends StatelessWidget {
  const _MatchScoreCard({
    required this.match,
    required this.onTap,
    required this.onOpenScoring,
    required this.onOpenScorecard,
    this.onToggleVisibility,
    required this.onDelete,
  });

  final DerivedMatchState match;
  final VoidCallback onTap;
  final VoidCallback onOpenScoring;
  final VoidCallback onOpenScorecard;
  final VoidCallback? onToggleVisibility;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final isLive = match.status == MatchStatus.live;
    final isBreak = match.status == MatchStatus.inningsBreak;
    final isCompleted = match.status == MatchStatus.completed;
    final inn1 = match.innings1;
    final inn2 = match.innings2;
    final inn2Started =
        inn2 != null && (inn2.legalBalls > 0 || inn2.isDeclared || match.activeInningsNumber >= 2);
    final team1Name = inn1.battingTeam;
    final team2Name = inn1.bowlingTeam;
    final activeTeam = match.activeInnings.battingTeam;

    String? footerText;
    Color footerColor = c.inkSecondary;
    if (match.resultSummary != null) {
      footerText = match.resultSummary!;
      footerColor = c.pitchGreen;
    } else if (match.leadTrailText != null) {
      footerText = match.leadTrailText!;
      footerColor = c.inkPrimary;
    } else if (match.activeInnings.runsNeeded != null && isLive) {
      final rem = match.activeInnings.ballsRemaining;
      footerText =
          '${match.activeInnings.battingTeam} need ${match.activeInnings.runsNeeded} from $rem ball${rem == 1 ? '' : 's'}';
      footerColor = c.inkPrimary;
    } else if (isBreak) {
      footerText = 'Innings break';
    }

    return CreasePressable(
      onTap: onTap,
      onLongPress: onDelete,
      child: GlassSurface(
        borderColor: c.hairline,
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top metadata strip
            Row(
              children: [
                if (isLive) ...[
                  const CreaseLiveDot(size: 7),
                  const SizedBox(width: 6),
                  Text(
                    'Live',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: c.pitchGreen,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ] else
                  Text(
                    isBreak ? 'Innings break' : 'Final',
                    style: Theme.of(context).textTheme.labelMedium,
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
                    match.config.formatLabel,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontSize: 10.5,
                          color: c.inkPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (match.config.isPublicLive) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: c.pitchGreenSoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Public',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontSize: 10,
                            color: c.pitchGreen,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
                const Spacer(),
                if (match.unsyncedCount > 0) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 13,
                        color: c.inkSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Offline',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontSize: 11,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 2),
                ],
                CreaseMenuButton<String>(
                  compact: true,
                  iconSize: 18,
                  sheetTitle: match.config.title,
                  tooltip: 'Match options',
                  items: [
                    if (isCompleted) ...[
                      const CreaseMenuItem(
                        value: 'scorecard',
                        label: 'View scorecard',
                        icon: Icons.table_chart_outlined,
                      ),
                      const CreaseMenuItem(
                        value: 'scoring',
                        label: 'Reopen scoring',
                        subtitle: 'Edit a ball or play Super Over',
                        icon: Icons.sports_cricket_rounded,
                      ),
                    ] else ...[
                      const CreaseMenuItem(
                        value: 'scoring',
                        label: 'Resume scoring',
                        icon: Icons.sports_cricket_rounded,
                      ),
                      const CreaseMenuItem(
                        value: 'scorecard',
                        label: 'View scorecard',
                        icon: Icons.table_chart_outlined,
                      ),
                      if (onToggleVisibility != null)
                        CreaseMenuItem(
                          value: 'visibility',
                          label: match.config.isPublicLive
                              ? 'Make unlisted'
                              : 'Show on Live tab',
                          subtitle: match.config.isPublicLive
                              ? 'Hide from Crease Live (link still works)'
                              : 'Broadcast live publicly on Crease Live',
                          icon: match.config.isPublicLive
                              ? Icons.lock_outline_rounded
                              : Icons.sensors_rounded,
                        ),
                    ],
                    const CreaseMenuItem(
                      value: 'delete',
                      label: 'Delete match',
                      icon: Icons.delete_outline_rounded,
                      isDestructive: true,
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'scorecard') {
                      onOpenScorecard();
                    } else if (value == 'scoring') {
                      onOpenScoring();
                    } else if (value == 'visibility') {
                      onToggleVisibility?.call();
                    } else if (value == 'delete') {
                      onDelete();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Team 1 scoreline
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _TeamScoreRow(
                teamName: team1Name,
                teamId: match.config.teamIdForSide(inn1.battingSide),
                score: inn1.scoreText,
                overs: '${inn1.oversText} ov',
                isHighlighted: isLive && activeTeam == team1Name,
                dimmed: isCompleted &&
                    match.resultSummary != null &&
                    !match.resultSummary!
                        .toLowerCase()
                        .startsWith(team1Name.toLowerCase()),
              ),
            ),
            const SizedBox(height: 8),

            // Team 2 scoreline
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _TeamScoreRow(
                teamName: team2Name,
                teamId: match.config.teamIdForSide(
                  inn2?.battingSide ??
                      (inn1.battingSide == MatchSide.a
                          ? MatchSide.b
                          : MatchSide.a),
                ),
                score: inn2Started ? inn2.scoreText : null,
                overs: inn2Started ? '${inn2.oversText} ov' : 'Yet to bat',
                isHighlighted: isLive && activeTeam == team2Name,
                dimmed: !inn2Started ||
                    (isCompleted &&
                        match.resultSummary != null &&
                        !match.resultSummary!
                            .toLowerCase()
                            .startsWith(team2Name.toLowerCase())),
              ),
            ),

            if (footerText != null) ...[
              const SizedBox(height: 11),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(height: 1, color: c.hairlineSubtle),
                    const SizedBox(height: 9),
                    Text(
                      footerText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: footerColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TeamScoreRow extends StatelessWidget {
  const _TeamScoreRow({
    required this.teamName,
    this.teamId,
    required this.score,
    required this.overs,
    required this.isHighlighted,
    required this.dimmed,
  });

  final String teamName;
  final String? teamId;
  final String? score;
  final String overs;
  final bool isHighlighted;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final nameColor = dimmed ? c.inkSecondary : c.inkPrimary;
    return Row(
      children: [
        CreaseTeamBadge(
          name: teamName,
          teamId: teamId,
          size: 28,
          highlighted: isHighlighted,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            teamName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: nameColor,
                  fontWeight:
                      isHighlighted ? FontWeight.w700 : FontWeight.w600,
                ),
          ),
        ),
        const SizedBox(width: 10),
        if (score != null) ...[
          Text(
            overs,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: c.inkSecondary,
                  fontSize: 12,
                ),
          ),
          const SizedBox(width: 8),
          Text(
            score!,
            style: creaseNumeralStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: nameColor,
            ),
          ),
        ] else
          Text(
            overs,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: c.inkSecondary,
                  fontSize: 12.5,
                ),
          ),
      ],
    );
  }
}

class _CreaseBottomNav extends StatelessWidget {
  const _CreaseBottomNav({
    required this.selectedIndex,
    required this.hasActiveLive,
    required this.onSelect,
  });

  final int selectedIndex;
  final bool hasActiveLive;
  final ValueChanged<int> onSelect;

  static const _items = [
    (
      label: 'Matches',
      icon: Icons.sports_cricket_outlined,
      activeIcon: Icons.sports_cricket_rounded,
    ),
    (
      label: 'Live',
      icon: Icons.sensors_outlined,
      activeIcon: Icons.sensors_rounded,
    ),
    (
      label: 'Teams',
      icon: Icons.groups_outlined,
      activeIcon: Icons.groups_rounded,
    ),
    (
      label: 'Tournaments',
      icon: Icons.emoji_events_outlined,
      activeIcon: Icons.emoji_events_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceSheet,
        border: Border(top: BorderSide(color: c.hairlineSubtle, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onSelect(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          width: selectedIndex == i ? 20 : 0,
                          height: 2.5,
                          margin: const EdgeInsets.only(bottom: 5),
                          decoration: BoxDecoration(
                            color: c.pitchGreen,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              selectedIndex == i
                                  ? _items[i].activeIcon
                                  : _items[i].icon,
                              size: 22,
                              color: selectedIndex == i
                                  ? c.pitchGreen
                                  : c.inkSecondary,
                            ),
                            if (i == 1 && hasActiveLive && selectedIndex != 1)
                              Positioned(
                                right: -3,
                                top: -2,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: c.pitchGreen,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: c.surfaceSheet,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _items[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontSize: 11,
                                    color: selectedIndex == i
                                        ? c.pitchGreen
                                        : c.inkSecondary,
                                    fontWeight: selectedIndex == i
                                        ? FontWeight.w700
                                        : FontWeight.w500,
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
    );
  }
}
