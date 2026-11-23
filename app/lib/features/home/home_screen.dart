import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local_event_store.dart';
import '../../domain/cricket_engine.dart';
import '../../domain/models.dart';
import '../../domain/team_profile.dart';
import '../../domain/tournament_engine.dart';
import '../../domain/user_profile.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/crease_ui.dart';
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

  String get _tabHeading => switch (_navIndex) {
        1 => 'Teams',
        2 => 'Tournaments',
        3 => 'Stats',
        _ => 'Crease',
      };

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
        child: RefreshIndicator(
          color: c.pitchGreen,
          backgroundColor: c.surfaceGlass,
          onRefresh: _refreshAndSync,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
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
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.6,
                              ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_navIndex == 1 ||
                          (_navIndex == 0 && _matches.isNotEmpty) ||
                          (_navIndex == 2 && _tournaments.isNotEmpty))
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: c.inkPrimary,
                            foregroundColor: c.ground,
                            minimumSize: const Size(0, 38),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                            textStyle: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(CreaseRadius.control),
                            ),
                          ),
                          onPressed: _navIndex == 1
                              ? _createTeam
                              : _navIndex == 2
                                  ? _createTournament
                                  : _createQuickMatch,
                          icon: const Icon(Icons.add_rounded, size: 17),
                          label: Text(
                            _navIndex == 1
                                ? 'Team'
                                : _navIndex == 2
                                    ? 'Tournament'
                                    : 'New match',
                          ),
                        ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Profile & account',
                        child: CreasePressable(
                          onTap: _openProfile,
                          borderRadius:
                              BorderRadius.circular(CreaseRadius.control),
                          scale: 0.94,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: c.surfaceGlass,
                                  borderRadius: BorderRadius.circular(
                                    CreaseRadius.control,
                                  ),
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
                    ],
                  ),
                ),
              ),
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
                          onLongPress: () =>
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
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                      sliver: SliverList.separated(
                        itemCount: recentMatches.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) => _MatchScoreCard(
                          match: recentMatches[index],
                          onTap: () =>
                              _openMatch(recentMatches[index].config.id),
                          onLongPress: () =>
                              _confirmDeleteMatch(recentMatches[index]),
                        ),
                      ),
                    ),
                  ],
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
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    sliver: SliverList.separated(
                      itemCount: _tournaments.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final t = _tournaments[index];
                        final tMatches = _matches
                            .where((m) => m.config.tournamentId == t.id)
                            .length;
                        return CreasePressable(
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
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                CreaseTeamBadge(
                                  name: t.name,
                                  size: 40,
                                  highlighted: true,
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
                                        '${t.teams.length} teams · $tMatches match${tMatches == 1 ? '' : 'es'} · ${t.formatLabel}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                      ),
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
      bottomNavigationBar: _CreaseBottomNav(
        selectedIndex: _navIndex,
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
    required this.onLongPress,
  });

  final DerivedMatchState match;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final isLive = match.status == MatchStatus.live;
    final isBreak = match.status == MatchStatus.inningsBreak;
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
      footerText =
          '${match.activeInnings.battingTeam} need ${match.activeInnings.runsNeeded} from ${match.activeInnings.ballsRemaining} balls';
      footerColor = c.inkPrimary;
    } else if (isBreak) {
      footerText = 'Innings break';
    }

    return CreasePressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: GlassSurface(
        borderColor: c.hairline,
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
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
                const Spacer(),
                if (match.unsyncedCount > 0)
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
              ],
            ),
            const SizedBox(height: 12),

            // Team 1 scoreline
            _TeamScoreRow(
              teamName: team1Name,
              score: inn1.scoreText,
              overs: '${inn1.oversText} ov',
              isHighlighted: isLive && activeTeam == team1Name,
              dimmed: match.status == MatchStatus.completed &&
                  match.resultSummary != null &&
                  !match.resultSummary!
                      .toLowerCase()
                      .startsWith(team1Name.toLowerCase()),
            ),
            const SizedBox(height: 8),

            // Team 2 scoreline
            _TeamScoreRow(
              teamName: team2Name,
              score: inn2Started ? inn2.scoreText : null,
              overs: inn2Started ? '${inn2.oversText} ov' : 'Yet to bat',
              isHighlighted: isLive && activeTeam == team2Name,
              dimmed: !inn2Started ||
                  (match.status == MatchStatus.completed &&
                      match.resultSummary != null &&
                      !match.resultSummary!
                          .toLowerCase()
                          .startsWith(team2Name.toLowerCase())),
            ),

            if (footerText != null) ...[
              const SizedBox(height: 11),
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
          ],
        ),
      ),
    );
  }
}

class _TeamScoreRow extends StatelessWidget {
  const _TeamScoreRow({
    required this.teamName,
    required this.score,
    required this.overs,
    required this.isHighlighted,
    required this.dimmed,
  });

  final String teamName;
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
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  static const _items = [
    (
      label: 'Matches',
      icon: Icons.sports_cricket_outlined,
      activeIcon: Icons.sports_cricket_rounded,
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
    (
      label: 'Stats',
      icon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart_rounded,
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
                        Icon(
                          selectedIndex == i
                              ? _items[i].activeIcon
                              : _items[i].icon,
                          size: 22,
                          color: selectedIndex == i
                              ? c.pitchGreen
                              : c.inkSecondary,
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
