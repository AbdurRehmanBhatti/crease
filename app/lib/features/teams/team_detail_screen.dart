part of 'teams_tab_view.dart';

class TeamDetailScreen extends StatefulWidget {
  const TeamDetailScreen({
    super.key,
    required this.teamName,
    required this.savedProfile,
    required this.initialRoster,
    required this.matches,
    this.readOnlyPublic = false,
  });

  final String teamName;
  final TeamProfile? savedProfile;
  final List<String> initialRoster;
  final List<DerivedMatchState> matches;
  final bool readOnlyPublic;

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

enum _WinLossScope { all, batFirst, bowlFirst }

enum _TeamStatsBoard { mvp, batting, bowling, boundaries }

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  static const _uuid = Uuid();
  late TeamProfile _profile;
  late bool _isSaved;
  Set<String> _claimedPlayers = const {};
  Map<String, String> _memberAvatars = const {};
  _WinLossScope _winLossScope = _WinLossScope.all;
  _TeamStatsBoard _statsBoard = _TeamStatsBoard.mvp;
  bool _uploadingLogo = false;

  void _setUploadingLogo(bool value) => setState(() => _uploadingLogo = value);

  bool get _canEdit => !widget.readOnlyPublic && _isSaved && _profile.isOwner;

  @override
  void initState() {
    super.initState();
    _isSaved = widget.savedProfile != null;
    _profile = widget.savedProfile ??
        TeamProfile(
          id: _uuid.v4(),
          name: widget.teamName,
          squad: const [],
          createdAt: DateTime.now(),
        );
    _loadClaimed();
    if (widget.readOnlyPublic && _profile.id.isNotEmpty) {
      _hydratePublicProfile();
    }
  }

  Future<void> _hydratePublicProfile() async {
    final full =
        await LocalEventStore.instance.fetchPublicTeamProfile(_profile.id);
    if (!mounted || full == null) return;
    setState(() {
      _profile = full.copyWith(isMyTeam: false, isOwner: false);
      _syncClaimedFromSquad();
    });
  }

  void _syncClaimedFromSquad() {
    _claimedPlayers = {
      for (final p in _profile.squad)
        if (p.isLinked) p.displayName.toLowerCase(),
    };
    _memberAvatars = {
      for (final p in _profile.squad)
        if (p.avatarUrl != null && p.avatarUrl!.isNotEmpty)
          p.displayName.toLowerCase(): p.avatarUrl!,
    };
  }

  Future<void> _loadClaimed() async {
    if (_isSaved && !widget.readOnlyPublic && _profile.id.isNotEmpty) {
      final latest = await LocalEventStore.instance.getTeam(_profile.id);
      if (mounted && latest != null) {
        setState(() {
          _profile = latest;
          _syncClaimedFromSquad();
        });
        return;
      }
    }
    if (!mounted) return;
    setState(_syncClaimedFromSquad);
  }


  Future<void> _persist(TeamProfile updated) async {
    setState(() {
      _profile = updated;
      _isSaved = true;
    });
    await LocalEventStore.instance.saveTeam(updated);
    LocalEventStore.instance.syncTeamToSupabase(updated.id);
  }


  String? _matchOutcomeForTeam(DerivedMatchState m) {
    if (m.status != MatchStatus.completed) return null;
    final side = m.config.sideForTeam(
      teamId: _profile.id.isNotEmpty ? _profile.id : null,
      teamName: _profile.name,
    );
    if (side == null) return null;
    if (m.config.isAbandoned) return 'NR';
    if (m.winnerSide == side) return 'W';
    if (m.winnerSide != null) return 'L';
    final summary = (m.resultSummary ?? '').toLowerCase();
    if (summary.contains('tied') || summary.contains('draw')) return 'T';
    if (summary.contains('abandoned') || summary.contains('no result')) {
      return 'NR';
    }
    return 'L';
  }

  ({int played, int won, int lost, int tied}) _winLossStats(
    List<DerivedMatchState> teamMatches,
  ) {
    var played = 0, won = 0, lost = 0, tied = 0;
    for (final m in teamMatches) {
      if (m.status != MatchStatus.completed) continue;
      final side = m.config.sideForTeam(
        teamId: _profile.id.isNotEmpty ? _profile.id : null,
        teamName: _profile.name,
      );
      if (side == null) continue;
      final battedFirst = m.config.battingFirstSide == side;
      if (_winLossScope == _WinLossScope.batFirst && !battedFirst) continue;
      if (_winLossScope == _WinLossScope.bowlFirst && battedFirst) continue;
      final outcome = _matchOutcomeForTeam(m);
      if (outcome == null || outcome == 'NR') continue;
      played++;
      if (outcome == 'W') {
        won++;
      } else if (outcome == 'T') {
        tied++;
      } else {
        lost++;
      }
    }
    return (played: played, won: won, lost: lost, tied: tied);
  }

  void _openPlayerProfile(String playerName, {String? playerId}) {
    final player = (playerId != null && playerId.isNotEmpty)
        ? (_profile.playerById(playerId) ?? _profile.playerByName(playerName))
        : _profile.playerByName(playerName);
    final meta = player?.meta ?? _profile.metaFor(playerName);
    final isClaimed =
        player?.isLinked ?? _claimedPlayers.contains(playerName.toLowerCase());
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerProfileScreen(
          playerName: player?.displayName ?? playerName,
          playerId: player?.id ?? playerId,
          userId: player?.userId,
          role: meta.role,
          teams: [_profile.name],
          isVerified: isClaimed,
          avatarUrl: player?.avatarUrl ?? _memberAvatars[playerName.toLowerCase()],
          matches: widget.matches,
        ),
      ),
    );
  }

  void _showMvpFormulaSheet(BuildContext context) {
    final c = context.crease;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GlassSurface(
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
              title: 'How MVP points work',
              subtitle: 'Derived directly from ball-by-ball match events.',
            ),
            const SizedBox(height: 12),
            for (final item in const [
              ('1 run scored', '+1 pt'),
              ('Four (4)', '+1 bonus'),
              ('Six (6)', '+2 bonus'),
              ('Half-century (50+)', '+10 bonus'),
              ('Century (100+)', '+25 bonus'),
              ('Wicket taken', '+20 pts'),
              ('Maiden over', '+10 pts'),
              ('Catch / Stumping / Run-out', '+8 pts'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(item.$1, style: Theme.of(ctx).textTheme.bodyMedium),
                    Text(
                      item.$2,
                      style: creaseNumeralStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: c.pitchGreen,
                      ),
                    ),
                  ],
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
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final teamMatches = widget.matches
        .where(
          (m) => m.config.involvesTeam(
            teamId: _profile.id.isNotEmpty ? _profile.id : null,
            teamName: _profile.name,
          ),
        )
        .toList()
      ..sort((a, b) => b.config.createdAt.compareTo(a.config.createdAt));

    final statsList = LocalEventStore.instance.deriveStats(
      teamMatches,
      teamId: _profile.id.isNotEmpty ? _profile.id : null,
      teamName: _profile.name,
    );
    final cleanStatsList = statsList
        .where((s) => !LocalEventStore.isPlaceholderPlayerName(s.name))
        .toList();
    final statsByPlayerId = {
      for (final s in statsList)
        if (s.playerId.isNotEmpty) s.playerId: s,
    };
    final statsByLower = {
      for (final s in statsList) s.name.toLowerCase(): s,
    };

    final sortedPlayers = List<String>.from(_profile.players)
      ..sort((a, b) {
        final da = _designationOrder(_profile.metaFor(a).designation);
        final db = _designationOrder(_profile.metaFor(b).designation);
        if (da != db) return da.compareTo(db);
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    final recentForm = teamMatches
        .map(_matchOutcomeForTeam)
        .whereType<String>()
        .take(5)
        .toList();
    final wl = _winLossStats(teamMatches);
    final topScorer = StatsEngine.byRuns(cleanStatsList).firstOrNull;
    final topBowler = StatsEngine.byWickets(cleanStatsList)
        .where((p) => p.wickets > 0)
        .firstOrNull;

    final rankedBoard = switch (_statsBoard) {
      _TeamStatsBoard.mvp => StatsEngine.byMvp(cleanStatsList),
      _TeamStatsBoard.batting => StatsEngine.byRuns(cleanStatsList),
      _TeamStatsBoard.bowling => StatsEngine.byWickets(cleanStatsList),
      _TeamStatsBoard.boundaries => StatsEngine.bySixes(cleanStatsList),
    };

    String primaryMetric(PlayerCareerStats p) => switch (_statsBoard) {
          _TeamStatsBoard.mvp => '${p.mvpPoints} pts',
          _TeamStatsBoard.batting => '${p.runs}',
          _TeamStatsBoard.bowling => '${p.wickets} wkts',
          _TeamStatsBoard.boundaries => '${p.sixes}×6 · ${p.fours}×4',
        };

    String secondaryMetric(PlayerCareerStats p) => switch (_statsBoard) {
          _TeamStatsBoard.mvp =>
            '${p.runs}r · ${p.wickets}w · ${p.fieldingDismissals}f',
          _TeamStatsBoard.batting =>
            'SR ${p.strikeRate.toStringAsFixed(0)} · HS ${p.highestScoreText} · ${p.inningsBatted} inn',
          _TeamStatsBoard.bowling =>
            '${p.oversBowledText} ov · Econ ${p.economy.toStringAsFixed(1)} · Best ${p.bestBowlingText}',
          _TeamStatsBoard.boundaries =>
            '${p.runs} runs (${p.ballsFaced}b) · SR ${p.strikeRate.toStringAsFixed(0)}',
        };

    final statusPillLabel = widget.readOnlyPublic
        ? 'Public club'
        : _profile.isMyTeam
            ? 'My Team'
            : _profile.isOwner
                ? 'Saved team'
                : 'Squad member';

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: c.ground,
        appBar: AppBar(
          title: (_profile.location != null && _profile.location!.isNotEmpty)
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _profile.location!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                )
              : Text(_profile.name),
          actions: [
            if (_canEdit)
              IconButton(
                tooltip: 'Invite teammates',
                icon: const Icon(Icons.group_add_outlined),
                onPressed: () => showInviteTeammatesSheet(context, _profile),
              ),
            if (!widget.readOnlyPublic)
              CreaseMenuButton<String>(
                sheetTitle: _profile.name,
                tooltip: 'Team options',
                items: [
                  if (_profile.isOwner)
                    CreaseMenuItem(
                      value: 'toggle_pin',
                      label: _profile.isMyTeam
                          ? 'Unpin from My Team'
                          : 'Set as My Team',
                      subtitle: _profile.isMyTeam
                          ? 'Stop pre-filling in Quick Match'
                          : 'Pin to top & pre-fill in Quick Match',
                      icon: _profile.isMyTeam
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                    ),
                  if (_canEdit) ...[
                    const CreaseMenuItem(
                      value: 'edit',
                      label: 'Edit team',
                      subtitle: 'Update name or city',
                      icon: Icons.edit_outlined,
                    ),
                    const CreaseMenuItem(
                      value: 'delete',
                      label: 'Delete team',
                      subtitle: 'Keeps past matches and player stats',
                      icon: Icons.delete_outline_rounded,
                      isDestructive: true,
                    ),
                  ],
                  if (_isSaved && !_profile.isOwner)
                    const CreaseMenuItem(
                      value: 'leave',
                      label: 'Leave team',
                      subtitle: 'Removes this team from your device',
                      icon: Icons.logout_rounded,
                      isDestructive: true,
                    ),
                ],
                onSelected: (action) {
                  if (action == 'toggle_pin') {
                    _persist(_profile.copyWith(isMyTeam: !_profile.isMyTeam));
                  } else if (action == 'edit') {
                    _editTeam();
                  } else if (action == 'delete') {
                    _confirmDeleteTeam();
                  } else if (action == 'leave') {
                    _confirmLeaveTeam();
                  }
                },
              ),
          ],
          bottom: TabBar(
            indicatorColor: c.pitchGreen,
            labelColor: c.inkPrimary,
            unselectedLabelColor: c.inkSecondary,
            dividerColor: c.hairlineSubtle,
            labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
            unselectedLabelStyle:
                Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Players'),
              Tab(text: 'Matches'),
              Tab(text: 'Stats'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // TAB 1: OVERVIEW
            ListView(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 32 + bottomInset),
              children: [
                if (!widget.readOnlyPublic &&
                    !_profile.isMyTeam &&
                    _profile.isOwner) ...[
                  GlassSurface(
                    borderColor: c.pitchGreen.withValues(alpha: 0.3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isSaved
                                    ? 'Make this your main team?'
                                    : 'Play for this team?',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Keeps it pinned at the top & ready for quick matches.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: c.inkSecondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          onPressed: () =>
                              _persist(_profile.copyWith(isMyTeam: true)),
                          child: const Text('Pin team'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Club Hero Card
                GlassSurface(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (_canEdit)
                            CreasePressable(
                              onTap: _uploadingLogo
                                  ? null
                                  : _showTeamLogoOptions,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  CreaseTeamBadge(
                                    name: _profile.name,
                                    teamId: _profile.id,
                                    avatarUrl: _profile.logoUrl,
                                    size: 52,
                                    highlighted: _profile.isMyTeam,
                                  ),
                                  Positioned(
                                    right: -3,
                                    bottom: -3,
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: c.pitchGreen,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: c.surfaceSheet,
                                          width: 2,
                                        ),
                                      ),
                                      child: _uploadingLogo
                                          ? const Padding(
                                              padding: EdgeInsets.all(4),
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.camera_alt_rounded,
                                              size: 11,
                                              color: Colors.white,
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            CreaseTeamBadge(
                              name: _profile.name,
                              teamId: _profile.id,
                              avatarUrl: _profile.logoUrl,
                              size: 52,
                              highlighted: _profile.isMyTeam,
                            ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _profile.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _profile.isMyTeam
                                            ? c.pitchGreenSoft
                                            : c.pillMutedBg,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        statusPillLabel,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: _profile.isMyTeam
                                                  ? c.pitchGreen
                                                  : c.inkSecondary,
                                            ),
                                      ),
                                    ),
                                    if (_profile.profileCode != null &&
                                        _profile.profileCode!.isNotEmpty)
                                      CreasePressable(
                                        onTap: () {
                                          final code = _profile.profileCode!;
                                          Clipboard.setData(
                                            ClipboardData(text: code),
                                          );
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Team ID $code copied · share with opponents at the toss',
                                              ),
                                            ),
                                          );
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: c.surfaceKey,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border:
                                                Border.all(color: c.hairline),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'ID: ${_profile.profileCode!}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelMedium
                                                    ?.copyWith(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: c.inkPrimary,
                                                    ),
                                              ),
                                              const SizedBox(width: 4),
                                              Icon(
                                                Icons.copy_rounded,
                                                size: 11,
                                                color: c.inkSecondary,
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    else if (!widget.readOnlyPublic &&
                                        _profile.isOwner &&
                                        !isSignedInAccount())
                                      CreasePressable(
                                        onTap: () async {
                                          final ok =
                                              await requireSignedInAccount(
                                            context,
                                            title: 'Sign in for a Team ID',
                                            subtitle:
                                                'Get a shareable Team ID so opponents can link matches to ${_profile.name}.',
                                          );
                                          if (!ok || !mounted) return;
                                          await LocalEventStore.instance
                                              .syncTeamToSupabase(_profile.id);
                                          final refreshed = (await LocalEventStore
                                                  .instance
                                                  .listTeams())
                                              .where((t) => t.id == _profile.id)
                                              .firstOrNull;
                                          if (refreshed != null && mounted) {
                                            setState(() => _profile = refreshed);
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: c.surfaceKey,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border:
                                                Border.all(color: c.hairline),
                                          ),
                                          child: Text(
                                            'Sign in for Team ID',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: c.pitchGreen,
                                                ),
                                          ),
                                        ),
                                      ),
                                    Text(
                                      '${_profile.players.length} player${_profile.players.length == 1 ? '' : 's'} · ${teamMatches.length} match${teamMatches.length == 1 ? '' : 'es'}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: c.inkSecondary),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Divider(height: 1, color: c.hairlineSubtle),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            'Recent form',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const Spacer(),
                          if (recentForm.isEmpty)
                            Text(
                              'No completed matches yet',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: c.inkSecondary),
                            )
                          else
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final code in recentForm)
                                  Container(
                                    width: 26,
                                    height: 26,
                                    margin: const EdgeInsets.only(left: 6),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: code == 'W'
                                          ? c.pitchGreenSoft
                                          : code == 'L'
                                              ? c.wicketRedSoft
                                              : c.pillMutedBg,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      code,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                            color: code == 'W'
                                                ? c.pitchGreen
                                                : code == 'L'
                                                    ? c.wicketRed
                                                    : c.inkSecondary,
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Win / Loss Ratio Card
                Text(
                  'Win / Loss ratio',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                GlassSurface(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CreaseSegmentedControl<_WinLossScope>(
                        selected: _winLossScope,
                        onChanged: (v) => setState(() => _winLossScope = v),
                        items: const [
                          (
                            value: _WinLossScope.all,
                            label: 'All',
                            icon: null,
                          ),
                          (
                            value: _WinLossScope.batFirst,
                            label: 'Bat 1st',
                            icon: null,
                          ),
                          (
                            value: _WinLossScope.bowlFirst,
                            label: 'Bowl 1st',
                            icon: null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Builder(
                        builder: (context) {
                          final wonPct =
                              wl.played > 0 ? (wl.won * 100 / wl.played) : 0.0;
                          final lostPct =
                              wl.played > 0 ? (wl.lost * 100 / wl.played) : 0.0;
                          final wonFlex = wl.played > 0
                              ? (wonPct * 10).round().clamp(0, 1000)
                              : 0;
                          final lostFlex = wl.played > 0
                              ? (lostPct * 10).round().clamp(0, 1000)
                              : 0;
                          final tiedFlex = wl.played > 0
                              ? (1000 - wonFlex - lostFlex).clamp(0, 1000)
                              : 1000;
                          return Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Won ${wonPct.toStringAsFixed(0)}%',
                                    style: creaseNumeralStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: wl.won > 0
                                          ? c.pitchGreen
                                          : c.inkSecondary,
                                    ),
                                  ),
                                  Text(
                                    'Lost ${lostPct.toStringAsFixed(0)}%',
                                    style: creaseNumeralStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: wl.lost > 0
                                          ? c.wicketRed
                                          : c.inkSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  height: 9,
                                  child: Row(
                                    children: [
                                      if (wonFlex > 0)
                                        Expanded(
                                          flex: wonFlex,
                                          child: Container(color: c.pitchGreen),
                                        ),
                                      if (tiedFlex > 0)
                                        Expanded(
                                          flex: tiedFlex,
                                          child: Container(
                                            color: c.pillMutedBg,
                                          ),
                                        ),
                                      if (lostFlex > 0)
                                        Expanded(
                                          flex: lostFlex,
                                          child: Container(
                                            color: c.wicketRed
                                                .withValues(alpha: 0.72),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _MiniStatBox(
                                    label: 'Matches',
                                    value: '${wl.played}',
                                  ),
                                  const SizedBox(width: 8),
                                  _MiniStatBox(
                                    label: 'Won',
                                    value: '${wl.won}',
                                    highlight: wl.won > 0,
                                  ),
                                  const SizedBox(width: 8),
                                  _MiniStatBox(
                                    label: 'Lost',
                                    value: '${wl.lost}',
                                  ),
                                  if (wl.tied > 0) ...[
                                    const SizedBox(width: 8),
                                    _MiniStatBox(
                                      label: 'Tied',
                                      value: '${wl.tied}',
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Top Performers Card
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Top performers',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (topScorer != null || topBowler != null)
                      Builder(
                        builder: (tabCtx) => TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () =>
                              DefaultTabController.of(tabCtx).animateTo(3),
                          child: const Text('See all →'),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (topScorer == null && topBowler == null)
                  GlassSurface(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      'Score a match with ${_profile.name} to see top batters and bowlers.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else
                  GlassSurface(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (final entry in [
                          if (topScorer != null)
                            (
                              label: 'Top batter',
                              player: topScorer,
                              metric: '${topScorer.runs} runs',
                              sub:
                                  'SR ${topScorer.strikeRate.toStringAsFixed(0)} · HS ${topScorer.highestScoreText}',
                            ),
                          if (topBowler != null)
                            (
                              label: 'Top bowler',
                              player: topBowler,
                              metric: '${topBowler.wickets} wkts',
                              sub:
                                  'Econ ${topBowler.economy.toStringAsFixed(1)} · Best ${topBowler.bestBowlingText}',
                            ),
                        ].indexed) ...[
                          if (entry.$1 > 0)
                            Divider(
                              height: 1,
                              indent: 64,
                              color: c.hairlineSubtle,
                            ),
                          InkWell(
                            onTap: () =>
                                _openPlayerProfile(entry.$2.player.name),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  CreasePlayerAvatar(
                                    name: entry.$2.player.name,
                                    size: 38,
                                    highlighted: entry.$1 == 0,
                                    avatarUrl: _memberAvatars[
                                        entry.$2.player.name.toLowerCase()],
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.$2.label.toUpperCase(),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.6,
                                                color: c.pitchGreen,
                                              ),
                                        ),
                                        Text(
                                          entry.$2.player.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        Text(
                                          entry.$2.sub,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: c.inkSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    entry.$2.metric,
                                    style: creaseNumeralStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: entry.$1 == 0
                                          ? c.pitchGreen
                                          : c.inkPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: c.inkSecondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),

            // TAB 2: PLAYERS
            ListView(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 32 + bottomInset),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Players (${_profile.players.length})',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (_canEdit && sortedPlayers.isNotEmpty)
                      TextButton.icon(
                        onPressed: _addPlayer,
                        icon: const Icon(
                          Icons.person_add_alt_1_rounded,
                          size: 17,
                        ),
                        label: const Text('Add player'),
                      )
                    else if (!_canEdit)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          widget.readOnlyPublic
                              ? 'Public club'
                              : _isSaved
                                  ? 'Squad member'
                                  : 'Read-only',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                  ],
                ),
                if (_canEdit && sortedPlayers.isEmpty)
                  const SizedBox(height: 8),
                GlassSurface(
                  padding: sortedPlayers.isEmpty
                      ? const EdgeInsets.all(18)
                      : const EdgeInsets.symmetric(vertical: 4),
                  child: sortedPlayers.isEmpty
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Build your squad',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _canEdit
                                  ? 'Add players manually or invite teammates with a 6-digit code so they can join and link their stats.'
                                  : 'No players recorded for this team yet.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (_canEdit) ...[
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: _addPlayer,
                                      icon: const Icon(
                                        Icons.person_add_alt_1_rounded,
                                        size: 17,
                                      ),
                                      label: const Text('Add player'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => showInviteTeammatesSheet(
                                        context,
                                        _profile,
                                      ),
                                      icon: const Icon(
                                        Icons.group_add_outlined,
                                        size: 17,
                                      ),
                                      label: const Text('Invite'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < sortedPlayers.length; i++) ...[
                              if (i > 0)
                                Divider(
                                  height: 1,
                                  indent: 64,
                                  color: c.hairlineSubtle,
                                ),
                              Builder(
                                builder: (context) {
                                  final p = sortedPlayers[i];
                                  final player = _profile.playerByName(p);
                                  final meta =
                                      player?.meta ?? _profile.metaFor(p);
                                  final pStats = (player != null
                                          ? statsByPlayerId[player.id]
                                          : null) ??
                                      statsByLower[p.toLowerCase()];
                                  final isClaimed =
                                      _claimedPlayers.contains(p.toLowerCase());
                                  final subParts = <String>[
                                    if (meta.role.isNotEmpty) meta.role,
                                    if (pStats != null)
                                      '${pStats.runs}r · ${pStats.wickets}w',
                                    if (isClaimed) 'Linked',
                                    if (meta.role.isEmpty &&
                                        pStats == null &&
                                        !isClaimed)
                                      _canEdit
                                          ? 'Tap to assign role'
                                          : 'Squad player',
                                  ];
                                  return InkWell(
                                    onTap: () {
                                      if (!_canEdit) {
                                        _openPlayerProfile(p);
                                      } else {
                                        _openPlayerProfileSheet(p, pStats);
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 11,
                                      ),
                                      child: Row(
                                        children: [
                                          CreasePlayerAvatar(
                                            name: p,
                                            size: 38,
                                            highlighted:
                                                meta.designation != null,
                                            avatarUrl:
                                                _memberAvatars[p.toLowerCase()],
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        p,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodyLarge
                                                            ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                      ),
                                                    ),
                                                    if (meta.designation !=
                                                        null) ...[
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 6,
                                                          vertical: 1.5,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color:
                                                              c.pitchGreenSoft,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(6),
                                                        ),
                                                        child: Text(
                                                          meta.designation!,
                                                          style: Theme.of(
                                                                  context)
                                                              .textTheme
                                                              .labelMedium
                                                              ?.copyWith(
                                                                fontSize: 10.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: c
                                                                    .pitchGreen,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                    if (isClaimed) ...[
                                                      const SizedBox(width: 5),
                                                      Icon(
                                                        Icons.verified_rounded,
                                                        size: 15,
                                                        color: c.pitchGreen,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  subParts.join(' · '),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
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
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),

            // TAB 3: MATCHES
            ListView(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 32 + bottomInset),
              children: [
                if (teamMatches.isEmpty)
                  GlassSurface(
                    padding: const EdgeInsets.all(22),
                    child: Text(
                      'No matches recorded for ${_profile.name} yet.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else
                  for (final m in teamMatches)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: CreasePressable(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                (m.status == MatchStatus.completed ||
                                        widget.readOnlyPublic)
                                    ? ScorecardScreen(matchId: m.config.id)
                                    : ScoringScreen(matchId: m.config.id),
                          ),
                        ),
                        child: GlassSurface(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      m.config.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
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
                                            fontSize: 10.5,
                                            color: c.inkPrimary,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                m.resultSummary ??
                                    '${m.activeInnings.battingTeam} ${m.activeInnings.scoreText} (${m.activeInnings.oversText} ov)',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: c.pitchGreen,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
              ],
            ),

            // TAB 4: STATS (TEAM LEADERBOARDS)
            ListView(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 32 + bottomInset),
              children: [
                CreaseSegmentedControl<_TeamStatsBoard>(
                  selected: _statsBoard,
                  onChanged: (v) => setState(() => _statsBoard = v),
                  items: const [
                    (value: _TeamStatsBoard.mvp, label: 'MVP', icon: null),
                    (
                      value: _TeamStatsBoard.batting,
                      label: 'Batting',
                      icon: null,
                    ),
                    (
                      value: _TeamStatsBoard.bowling,
                      label: 'Bowling',
                      icon: null,
                    ),
                    (
                      value: _TeamStatsBoard.boundaries,
                      label: '4s & 6s',
                      icon: null,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        switch (_statsBoard) {
                          _TeamStatsBoard.mvp =>
                            'All-round impact across batting, bowling & fielding',
                          _TeamStatsBoard.batting =>
                            'Top run-scorers for ${_profile.name}',
                          _TeamStatsBoard.bowling =>
                            'Top wicket-takers for ${_profile.name}',
                          _TeamStatsBoard.boundaries =>
                            'Most sixes & fours for ${_profile.name}',
                        },
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: c.inkSecondary),
                      ),
                    ),
                    if (_statsBoard == _TeamStatsBoard.mvp)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _showMvpFormulaSheet(context),
                        icon: const Icon(Icons.info_outline_rounded, size: 15),
                        label: const Text('Formula'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (rankedBoard.isEmpty)
                  GlassSurface(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No stats recorded for ${_profile.name} yet.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else ...[
                  // #1 Leader Hero Card
                  CreasePressable(
                    onTap: () => _openPlayerProfile(rankedBoard.first.name),
                    child: GlassSurface(
                      borderColor: c.pitchGreen.withValues(alpha: 0.45),
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: c.pitchGreen,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '1',
                              style: creaseNumeralStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: c.onPitchGreen,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rankedBoard.first.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  secondaryMetric(rankedBoard.first),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: c.inkSecondary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            primaryMetric(rankedBoard.first),
                            style: creaseNumeralStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: c.pitchGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (rankedBoard.length > 1) ...[
                    const SizedBox(height: 10),
                    GlassSurface(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (var i = 1; i < rankedBoard.length; i++) ...[
                            if (i > 1)
                              Divider(
                                height: 1,
                                indent: 48,
                                color: c.hairlineSubtle,
                              ),
                            InkWell(
                              onTap: () =>
                                  _openPlayerProfile(rankedBoard[i].name),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 11,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      child: Text(
                                        '${i + 1}',
                                        textAlign: TextAlign.center,
                                        style: creaseNumeralStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: c.inkSecondary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            rankedBoard[i].name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            secondaryMetric(rankedBoard[i]),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: c.inkSecondary,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      primaryMetric(rankedBoard[i]),
                                      style: creaseNumeralStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: c.inkPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStatBox extends StatelessWidget {
  const _MiniStatBox({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

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
                color: highlight ? c.pitchGreen : c.inkPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: c.inkSecondary,
                    fontSize: 11,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
