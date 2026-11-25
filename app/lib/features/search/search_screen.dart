import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/local_event_store.dart';
import '../../domain/models.dart';
import '../../domain/stats_engine.dart';
import '../../domain/team_profile.dart';
import '../../domain/tournament_engine.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/crease_ui.dart';
import '../../widgets/glass_surface.dart';
import '../profile/player_profile_screen.dart';
import '../scorecard/scorecard_screen.dart';
import '../scoring/scoring_screen.dart';
import '../teams/teams_tab_view.dart';
import '../tournaments/tournament_detail_screen.dart';

enum _SearchFilter { all, matches, teams, tournaments, players }

/// Universal search across local + public Crease matches, teams, tournaments,
/// and players.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.localMatches,
    required this.localTeams,
    required this.localTournaments,
  });

  final List<DerivedMatchState> localMatches;
  final List<TeamProfile> localTeams;
  final List<Tournament> localTournaments;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _chipKeys = {
    for (final f in _SearchFilter.values) f: GlobalKey(),
  };
  _SearchFilter _filter = _SearchFilter.all;
  Timer? _debounce;
  int _seq = 0;
  bool _searchingRemote = false;

  late final List<PlayerCareerStats> _localPlayerStats;
  late final Map<String, List<String>> _localPlayerTeams;

  List<({String id, String name, String? location, List<String> players})>
      _remoteTeams = const [];
  List<
      ({
        String id,
        String teamA,
        String teamB,
        String formatLabel,
        DateTime createdAt,
      })> _remoteMatches = const [];
  List<
      ({
        String id,
        String name,
        String? location,
        String formatLabel,
        int teamCount,
        String? dateRangeLabel,
      })> _remoteTournaments = const [];
  List<
      ({
        String playerName,
        String teamId,
        String teamName,
        String? teamLocation,
      })> _remotePlayers = const [];

  @override
  void initState() {
    super.initState();
    final realMatches =
        widget.localMatches.where((m) => !m.config.isDemo).toList();
    _localPlayerStats = StatsEngine.derive(
      realMatches.isNotEmpty ? realMatches : widget.localMatches,
      excludeDemo: realMatches.isNotEmpty,
    );
    _localPlayerTeams = <String, List<String>>{};
    for (final t in widget.localTeams) {
      for (final p in t.players) {
        final key = p.trim().toLowerCase();
        if (key.isEmpty || LocalEventStore.isPlaceholderPlayerName(p)) continue;
        final list = _localPlayerTeams.putIfAbsent(key, () => <String>[]);
        if (!list.contains(t.name)) list.add(t.name);
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _scheduleRemoteSearch(String text) {
    _debounce?.cancel();
    final clean = text.trim();
    if (clean.length < 2) {
      if (_searchingRemote ||
          _remoteTeams.isNotEmpty ||
          _remoteMatches.isNotEmpty ||
          _remoteTournaments.isNotEmpty ||
          _remotePlayers.isNotEmpty) {
        setState(() {
          _searchingRemote = false;
          _remoteTeams = const [];
          _remoteMatches = const [];
          _remoteTournaments = const [];
          _remotePlayers = const [];
        });
      }
      return;
    }
    final seq = ++_seq;
    setState(() => _searchingRemote = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final store = LocalEventStore.instance;
      final localTeamIds = {for (final t in widget.localTeams) t.id};
      final localMatchIds = {for (final m in widget.localMatches) m.config.id};
      final localTourneyIds = {for (final t in widget.localTournaments) t.id};

      final results = await Future.wait([
        store.searchPublicTeams(
          clean,
          limit: 8,
          excludeIds: localTeamIds,
          dedupeByName: false,
        ),
        store.searchPublicMatches(
          clean,
          limit: 8,
          excludeIds: localMatchIds,
        ),
        store.searchPublicTournaments(
          clean,
          limit: 8,
          excludeIds: localTourneyIds,
        ),
        store.searchPublicPlayers(
          clean,
          limit: 10,
          excludeTeamIds: localTeamIds,
        ),
      ]);
      if (!mounted || seq != _seq) return;
      setState(() {
        _remoteTeams = results[0] as List<
            ({String id, String name, String? location, List<String> players})>;
        _remoteMatches = results[1] as List<
            ({
              String id,
              String teamA,
              String teamB,
              String formatLabel,
              DateTime createdAt,
            })>;
        _remoteTournaments = results[2] as List<
            ({
              String id,
              String name,
              String? location,
              String formatLabel,
              int teamCount,
              String? dateRangeLabel,
            })>;
        _remotePlayers = results[3] as List<
            ({
              String playerName,
              String teamId,
              String teamName,
              String? teamLocation,
            })>;
        _searchingRemote = false;
      });
    });
  }

  void _openPlayerProfile(
    BuildContext context, {
    required String name,
    List<String> teams = const [],
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerProfileScreen(
          playerName: name,
          teams: teams,
          matches: widget.localMatches,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final raw = _ctrl.text.trim();
    final q = raw.toLowerCase();

    final localMatches = q.isEmpty
        ? const <DerivedMatchState>[]
        : widget.localMatches
            .where((m) =>
                !m.config.isDemo &&
                (m.config.teamA.toLowerCase().contains(q) ||
                    m.config.teamB.toLowerCase().contains(q) ||
                    m.config.formatLabel.toLowerCase().contains(q)))
            .take(10)
            .toList();

    final localTeams = q.isEmpty
        ? const <TeamProfile>[]
        : widget.localTeams
            .where((t) =>
                t.name.toLowerCase().contains(q) ||
                (t.location?.toLowerCase().contains(q) ?? false))
            .toList();

    final localTournaments = q.isEmpty
        ? const <Tournament>[]
        : widget.localTournaments
            .where((t) =>
                t.name.toLowerCase().contains(q) ||
                (t.location?.toLowerCase().contains(q) ?? false))
            .toList();

    // Players: match against local stats + saved team rosters
    final playerEntries =
        <({String name, PlayerCareerStats? stats, List<String> teams})>[];
    if (q.isNotEmpty) {
      final seenLower = <String>{};
      for (final s in _localPlayerStats) {
        if (s.name.toLowerCase().contains(q) &&
            seenLower.add(s.name.toLowerCase())) {
          playerEntries.add((
            name: s.name,
            stats: s,
            teams: _localPlayerTeams[s.name.toLowerCase()] ?? const [],
          ));
        }
      }
      for (final t in widget.localTeams) {
        for (final p in t.players) {
          if (p.toLowerCase().contains(q) &&
              !LocalEventStore.isPlaceholderPlayerName(p) &&
              seenLower.add(p.toLowerCase())) {
            playerEntries.add((
              name: p,
              stats: null,
              teams: _localPlayerTeams[p.toLowerCase()] ?? [t.name],
            ));
          }
        }
      }
    }

    final showMatches =
        _filter == _SearchFilter.all || _filter == _SearchFilter.matches;
    final showTeams =
        _filter == _SearchFilter.all || _filter == _SearchFilter.teams;
    final showTournaments =
        _filter == _SearchFilter.all || _filter == _SearchFilter.tournaments;
    final showPlayers =
        _filter == _SearchFilter.all || _filter == _SearchFilter.players;

    final hasAnyResult =
        (showMatches && (localMatches.isNotEmpty || _remoteMatches.isNotEmpty)) ||
            (showTeams && (localTeams.isNotEmpty || _remoteTeams.isNotEmpty)) ||
            (showTournaments &&
                (localTournaments.isNotEmpty ||
                    _remoteTournaments.isNotEmpty)) ||
            (showPlayers &&
                (playerEntries.isNotEmpty || _remotePlayers.isNotEmpty));

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (v) {
              setState(() {});
              _scheduleRemoteSearch(v);
            },
            decoration: InputDecoration(
              hintText: 'Search matches, teams, tournaments…',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              fillColor: c.surfaceGlass,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              suffixIcon: _searchingRemote
                  ? const Padding(
                      padding: EdgeInsets.all(11),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : raw.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _ctrl.clear();
                            _scheduleRemoteSearch('');
                            setState(() {});
                          },
                        ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                children: [
                  for (final item in const [
                    (_SearchFilter.all, 'All'),
                    (_SearchFilter.matches, 'Matches'),
                    (_SearchFilter.teams, 'Teams'),
                    (_SearchFilter.tournaments, 'Tournaments'),
                    (_SearchFilter.players, 'Players'),
                  ])
                    Padding(
                      key: _chipKeys[item.$1],
                      padding: EdgeInsets.only(
                        right: item.$1 == _SearchFilter.players ? 0 : 8,
                      ),
                      child: ChoiceChip(
                        label: Text(item.$2),
                        selected: _filter == item.$1,
                        selectedColor: c.pitchGreen,
                        visualDensity: VisualDensity.compact,
                        labelStyle: TextStyle(
                          fontSize: 12.5,
                          color: _filter == item.$1
                              ? c.onPitchGreen
                              : c.inkPrimary,
                          fontWeight: _filter == item.$1
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                        side: BorderSide(
                          color: _filter == item.$1 ? c.pitchGreen : c.hairline,
                        ),
                        onSelected: (_) {
                          setState(() => _filter = item.$1);
                          final chipCtx = _chipKeys[item.$1]?.currentContext;
                          if (chipCtx != null) {
                            Scrollable.ensureVisible(
                              chipCtx,
                              duration: const Duration(milliseconds: 240),
                              curve: Curves.easeOutCubic,
                              alignment: 0.5,
                            );
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: raw.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 36,
                            color: c.inkSecondary.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Search Crease',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Find your matches, saved squads, tournaments, players, or any public club on Crease.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  )
                : !hasAnyResult
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            _searchingRemote
                                ? 'Searching Crease…'
                                : 'No results for "$raw".',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      )
                    : ListView(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          8,
                          20,
                          28 + MediaQuery.paddingOf(context).bottom,
                        ),
                        children: [
                          if (showMatches &&
                              (localMatches.isNotEmpty ||
                                  _remoteMatches.isNotEmpty)) ...[
                            _SectionLabel('Matches'),
                            for (final m in localMatches)
                              _ResultCard(
                                leading: CreaseTeamBadge(
                                  name: m.config.teamA,
                                  size: 38,
                                  highlighted: m.status == MatchStatus.live,
                                ),
                                title: '${m.config.teamA} v ${m.config.teamB}',
                                subtitle: m.status == MatchStatus.live
                                    ? 'Live · ${m.config.formatLabel}'
                                    : (m.resultSummary ?? m.config.formatLabel),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => m.status == MatchStatus.live
                                        ? ScoringScreen(matchId: m.config.id)
                                        : ScorecardScreen(
                                            matchId: m.config.id,
                                          ),
                                  ),
                                ),
                              ),
                            for (final rm in _remoteMatches)
                              _ResultCard(
                                leading: CreaseTeamBadge(
                                  name: rm.teamA,
                                  size: 38,
                                ),
                                title: '${rm.teamA} v ${rm.teamB}',
                                subtitle: 'On Crease · ${rm.formatLabel}',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ScorecardScreen(matchId: rm.id),
                                  ),
                                ),
                              ),
                          ],
                          if (showTeams &&
                              (localTeams.isNotEmpty ||
                                  _remoteTeams.isNotEmpty)) ...[
                            _SectionLabel('Teams'),
                            for (final t in localTeams)
                              _ResultCard(
                                leading: CreaseTeamBadge(
                                  name: t.name,
                                  size: 38,
                                  highlighted: t.isMyTeam,
                                ),
                                title: t.name,
                                subtitle: [
                                  if (t.location != null &&
                                      t.location!.isNotEmpty)
                                    t.location!,
                                  '${t.players.length} ${t.players.length == 1 ? 'player' : 'players'}',
                                ].join(' · '),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => TeamDetailScreen(
                                      teamName: t.name,
                                      savedProfile: t,
                                      initialRoster: t.players,
                                      matches: widget.localMatches,
                                    ),
                                  ),
                                ),
                              ),
                            for (final rt in _remoteTeams)
                              _ResultCard(
                                leading: CreaseTeamBadge(
                                  name: rt.name,
                                  size: 38,
                                ),
                                title: rt.name,
                                subtitle: [
                                  'On Crease',
                                  if (rt.location != null &&
                                      rt.location!.isNotEmpty)
                                    rt.location!,
                                  if (rt.players.isNotEmpty)
                                    '${rt.players.length} ${rt.players.length == 1 ? 'player' : 'players'}',
                                ].join(' · '),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => TeamDetailScreen(
                                      teamName: rt.name,
                                      savedProfile: TeamProfile(
                                        id: rt.id,
                                        name: rt.name,
                                        location: rt.location,
                                        isMyTeam: false,
                                        isOwner: false,
                                        players: rt.players,
                                        createdAt: DateTime.now(),
                                      ),
                                      initialRoster: rt.players,
                                      matches: widget.localMatches,
                                      readOnlyPublic: true,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                          if (showTournaments &&
                              (localTournaments.isNotEmpty ||
                                  _remoteTournaments.isNotEmpty)) ...[
                            _SectionLabel('Tournaments'),
                            for (final t in localTournaments)
                              _ResultCard(
                                leading: const CreaseTournamentBadge(
                                  size: 38,
                                ),
                                title: t.name,
                                subtitle: [
                                  '${t.formatLabel} · ${t.teams.length} teams',
                                  if (t.location != null &&
                                      t.location!.isNotEmpty)
                                    t.location!,
                                  if (t.dateRangeLabel != null)
                                    t.dateRangeLabel!,
                                ].join(' · '),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => TournamentDetailScreen(
                                      tournamentId: t.id,
                                    ),
                                  ),
                                ),
                              ),
                            for (final rt in _remoteTournaments)
                              _ResultCard(
                                leading: const CreaseTournamentBadge(
                                  size: 38,
                                ),
                                title: rt.name,
                                subtitle: [
                                  'On Crease',
                                  '${rt.formatLabel} · ${rt.teamCount} teams',
                                  if (rt.location != null &&
                                      rt.location!.isNotEmpty)
                                    rt.location!,
                                  if (rt.dateRangeLabel != null)
                                    rt.dateRangeLabel!,
                                ].join(' · '),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => TournamentDetailScreen(
                                      tournamentId: rt.id,
                                      readOnlyPublic: true,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                          if (showPlayers &&
                              (playerEntries.isNotEmpty ||
                                  _remotePlayers.isNotEmpty)) ...[
                            _SectionLabel('Players'),
                            for (final p in playerEntries)
                              _ResultCard(
                                leading: CreasePlayerAvatar(
                                  name: p.name,
                                  size: 38,
                                ),
                                title: p.name,
                                subtitle: p.stats != null
                                    ? '${p.stats!.runs}r · ${p.stats!.wickets}w · ${p.stats!.mvpPoints.toStringAsFixed(0)} MVP'
                                    : (p.teams.isNotEmpty
                                        ? p.teams.join(', ')
                                        : 'Squad player'),
                                onTap: () => _openPlayerProfile(
                                  context,
                                  name: p.name,
                                  teams: p.teams,
                                ),
                              ),
                            for (final rp in _remotePlayers)
                              _ResultCard(
                                leading: CreasePlayerAvatar(
                                  name: rp.playerName,
                                  size: 38,
                                ),
                                title: rp.playerName,
                                subtitle: [
                                  'On Crease',
                                  rp.teamName,
                                  if (rp.teamLocation != null) rp.teamLocation!,
                                ].join(' · '),
                                onTap: () => _openPlayerProfile(
                                  context,
                                  name: rp.playerName,
                                  teams: [rp.teamName],
                                ),
                              ),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: c.inkSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CreasePressable(
        onTap: onTap,
        child: GlassSurface(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: c.inkSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: c.inkSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
