import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/local_event_store.dart';
import '../../domain/cricket_engine.dart';
import '../../domain/models.dart';
import '../../domain/stats_engine.dart';
import '../../domain/tournament_engine.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/crease_ui.dart';
import '../scorecard/scorecard_screen.dart';
import '../scoring/scoring_screen.dart';
import 'sheets/tournament_sheets.dart';
import 'tournament_poster.dart';
import 'widgets/tournament_fixtures_tab.dart';
import 'widgets/tournament_standings_tab.dart';
import 'widgets/tournament_teams_tab.dart';

class TournamentDetailScreen extends StatefulWidget {
  const TournamentDetailScreen({
    super.key,
    required this.tournamentId,
    this.readOnlyPublic = false,
  });

  final String tournamentId;
  final bool readOnlyPublic;

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen> {
  static const _uuid = Uuid();

  Tournament? _tournament;
  List<DerivedMatchState> _matches = [];
  bool _loading = true;
  bool _unlockKnockoutsEarly = false;
  late bool _readOnly;

  @override
  void initState() {
    super.initState();
    _readOnly = widget.readOnlyPublic;
    _load();
  }

  Future<void> _load() async {
    final store = LocalEventStore.instance;
    if (!widget.readOnlyPublic) {
      final localTournament = await store.getTournament(widget.tournamentId);
      if (localTournament != null) {
        final unlockedEarly = await store.isTournamentKnockoutsUnlockedEarly(
          widget.tournamentId,
        );
        final matchConfigs =
            await store.listMatchesForTournament(widget.tournamentId);
        final derived = <DerivedMatchState>[];
        for (final cfg in matchConfigs) {
          final events = await store.getBallEvents(cfg.id);
          derived.add(CricketEngine.derive(cfg, events));
        }
        if (!mounted) return;
        setState(() {
          _tournament = localTournament;
          _matches = derived;
          _unlockKnockoutsEarly = unlockedEarly;
          _readOnly = false;
          _loading = false;
        });
        return;
      }
    }

    // Public or shared tournament not owned locally — load strictly in memory
    // so another user's tournament/matches never pollute local SQLite.
    final snap = await store.fetchPublicTournamentSnapshot(widget.tournamentId);
    if (!mounted) return;
    setState(() {
      _tournament = snap?.tournament;
      _matches = snap?.matches ?? const [];
      _unlockKnockoutsEarly = false;
      _readOnly = widget.readOnlyPublic || !(snap?.isOwner ?? false);
      _loading = false;
    });
  }

  Future<void> _launchMatch({
    required Tournament tournament,
    required String battingFirst,
    required String bowlingFirst,
    required MatchStage stage,
    int? fixtureIndex,
  }) async {
    final rosterA = List<String>.from(
      tournament.teamRosters[battingFirst] ?? const [],
    );
    final rosterB = List<String>.from(
      tournament.teamRosters[bowlingFirst] ?? const [],
    );
    final striker1 = rosterA.isNotEmpty ? rosterA[0] : 'Batter 1';
    final nonStriker1 = rosterA.length > 1 ? rosterA[1] : 'Batter 2';
    final bowler1 = rosterB.isNotEmpty ? rosterB[0] : 'Bowler 1';
    final striker2 = rosterB.isNotEmpty ? rosterB[0] : 'Opener 1';
    final nonStriker2 = rosterB.length > 1 ? rosterB[1] : 'Opener 2';
    final bowler2 = rosterA.isNotEmpty ? rosterA[0] : 'Bowler 1';

    final matchConfig = MatchConfig(
      id: _uuid.v4(),
      teamA: battingFirst,
      teamB: bowlingFirst,
      oversLimit: tournament.oversLimit,
      playersPerSide: tournament.playersPerSide,
      formatLabel: tournament.formatLabel,
      battingFirstTeam: battingFirst,
      openingStrikerInnings1: striker1,
      openingNonStrikerInnings1: nonStriker1,
      openingBowlerInnings1: bowler1,
      openingStrikerInnings2: striker2,
      openingNonStrikerInnings2: nonStriker2,
      openingBowlerInnings2: bowler2,
      teamAPlayers: rosterA.isEmpty ? [striker1, nonStriker1] : rosterA,
      teamBPlayers: rosterB.isEmpty ? [bowler1] : rosterB,
      tournamentId: tournament.id,
      tournamentStage: stage.name,
      fixtureIndex: fixtureIndex,
      isTestMatch: tournament.oversLimit == 0,
      createdAt: DateTime.now(),
    );

    await LocalEventStore.instance.saveMatch(matchConfig);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScoringScreen(matchId: matchConfig.id)),
    );
    _load();
  }

  Future<void> _openStartFixtureSheet(ScheduledFixture fixture) async {
    final t = _tournament;
    if (t == null || fixture.teamA == null || fixture.teamB == null) return;
    final battingFirst = await showStartFixtureSheet(
      context,
      tournament: t,
      fixture: fixture,
    );
    if (battingFirst == null) return;
    final bowlingFirst =
        battingFirst == fixture.teamA ? fixture.teamB! : fixture.teamA!;
    await _launchMatch(
      tournament: t,
      battingFirst: battingFirst,
      bowlingFirst: bowlingFirst,
      stage: fixture.stage,
      fixtureIndex: fixture.fixtureIndex,
    );
  }

  Future<void> _startOpenTournamentMatch() async {
    final t = _tournament;
    if (t == null || t.teams.length < 2) return;
    final picked = await showStartOpenTournamentMatchSheet(
      context,
      tournament: t,
    );
    if (picked == null) return;
    await _launchMatch(
      tournament: t,
      battingFirst: picked.teamA,
      bowlingFirst: picked.teamB,
      stage: picked.stage,
    );
  }

  Future<void> _openExistingMatch(String matchId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _readOnly
            ? ScorecardScreen(matchId: matchId)
            : ScoringScreen(matchId: matchId),
      ),
    );
    _load();
  }

  Future<void> _confirmUnlockKnockoutsEarly() async {
    final ok = await showUnlockKnockoutsDialog(context);
    if (!ok || !mounted) return;
    await LocalEventStore.instance.setTournamentKnockoutsUnlockedEarly(
      widget.tournamentId,
      true,
    );
    if (!mounted) return;
    setState(() => _unlockKnockoutsEarly = true);
  }

  Future<void> _editTournamentDetails() async {
    final t = _tournament;
    if (t == null) return;
    final allTournaments = await LocalEventStore.instance.listTournaments();
    final otherNames = allTournaments
        .where((other) => other.id != t.id)
        .map((other) => other.name.trim().toLowerCase())
        .toSet();
    if (!mounted) return;

    final nameCtrl = TextEditingController(text: t.name);
    final locCtrl = TextEditingController(text: t.location ?? '');
    DateTime? startDate = t.startDate;
    DateTime? endDate = t.endDate;
    String? errorText;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> pickDate({required bool isStart}) async {
              final now = DateTime.now();
              final initial = isStart
                  ? (startDate ?? now)
                  : (endDate ?? startDate ?? now);
              final firstDate = isStart
                  ? DateTime(now.year - 2)
                  : (startDate ?? DateTime(now.year - 2));
              final picked = await showDatePicker(
                context: ctx,
                initialDate: initial.isBefore(firstDate) ? firstDate : initial,
                firstDate: firstDate,
                lastDate: DateTime(now.year + 5),
              );
              if (picked == null || !ctx.mounted) return;
              setModalState(() {
                if (isStart) {
                  startDate = picked;
                  if (endDate != null && endDate!.isBefore(picked)) {
                    endDate = picked;
                  }
                } else {
                  endDate = picked;
                }
              });
            }

            void submit() {
              final trimmed = nameCtrl.text.trim();
              if (trimmed.isEmpty) {
                setModalState(() => errorText = 'Enter a tournament name.');
                return;
              }
              if (otherNames.contains(trimmed.toLowerCase())) {
                setModalState(
                  () => errorText =
                      'You already have a tournament named "$trimmed".',
                );
                return;
              }
              Navigator.pop(ctx, true);
            }

            Widget dateTile({
              required String label,
              required DateTime? value,
              required VoidCallback onTap,
              required VoidCallback? onClear,
            }) {
              final hasValue = value != null;
              return InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(CreaseRadius.control),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: c.surfaceKey,
                    borderRadius: BorderRadius.circular(CreaseRadius.control),
                    border: Border.all(
                      color: hasValue
                          ? c.pitchGreen.withValues(alpha: 0.45)
                          : c.hairline,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 15,
                        color: hasValue ? c.pitchGreen : c.inkSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          hasValue ? Tournament.formatShortDate(value) : label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                color:
                                    hasValue ? c.inkPrimary : c.inkSecondary,
                                fontWeight: hasValue
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                        ),
                      ),
                      if (onClear != null)
                        GestureDetector(
                          onTap: onClear,
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: c.inkSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: c.surfaceSheet,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(CreaseRadius.sheet),
                  ),
                  border: Border(top: BorderSide(color: c.hairline)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const CreaseSheetHeader(
                        title: 'Edit tournament',
                        subtitle: 'Update name, venue, or schedule dates.',
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameCtrl,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Tournament name',
                          errorText: errorText,
                        ),
                        onChanged: (_) {
                          if (errorText != null) {
                            setModalState(() => errorText = null);
                          }
                        },
                        onSubmitted: (_) => submit(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: locCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Venue or city (optional)',
                          hintText: 'e.g. Model Town Ground, Lahore',
                          prefixIcon:
                              Icon(Icons.location_on_outlined, size: 19),
                        ),
                        onSubmitted: (_) => submit(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: dateTile(
                              label: 'Start date',
                              value: startDate,
                              onTap: () => pickDate(isStart: true),
                              onClear: startDate == null
                                  ? null
                                  : () => setModalState(() => startDate = null),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: dateTile(
                              label: 'End date',
                              value: endDate,
                              onTap: () => pickDate(isStart: false),
                              onClear: endDate == null
                                  ? null
                                  : () => setModalState(() => endDate = null),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: submit,
                        child: const Text('Save changes'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    final nextName = nameCtrl.text.trim();
    final nextLoc = locCtrl.text.trim();
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      nameCtrl.dispose();
      locCtrl.dispose();
    });
    if (saved != true) return;

    final updated = t.copyWith(
      name: nextName,
      location: nextLoc.isEmpty ? null : nextLoc,
      clearLocation: nextLoc.isEmpty,
      startDate: startDate,
      clearStartDate: startDate == null,
      endDate: endDate,
      clearEndDate: endDate == null,
    );
    await LocalEventStore.instance.saveTournament(updated);
    LocalEventStore.instance.syncTournamentToSupabase(updated.id);
    if (!mounted) return;
    setState(() => _tournament = updated);
  }

  Future<void> _shareTournament(
    Tournament t,
    TournamentOverview overview,
    PlayerCareerStats? mvp,
  ) async {
    await TournamentPoster.shareTournament(
      tournament: t,
      overview: overview,
      mvp: mvp,
    );
  }

  Future<void> _confirmDeleteTournament() async {
    final t = _tournament;
    if (t == null) return;
    final ok = await showDeleteTournamentDialog(
      context,
      tournamentName: t.name,
    );
    if (!ok) return;
    await LocalEventStore.instance.deleteTournament(t.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _openAddTeamSheet() async {
    final t = _tournament;
    if (t == null) return;
    final knownRosters = await LocalEventStore.instance.listKnownTeamRosters();
    if (!mounted) return;
    final added = await showAddTournamentTeamsSheet(
      context,
      tournament: t,
      knownRosters: knownRosters,
    );
    if (added == null || added.isEmpty) return;
    final latest = _tournament;
    if (latest == null) return;
    final updatedRosters = {
      for (final e in latest.teamRosters.entries)
        e.key: List<String>.from(e.value),
    };
    for (final entry in added.entries) {
      if (updatedRosters.keys
          .any((k) => k.toLowerCase() == entry.key.toLowerCase())) {
        continue;
      }
      updatedRosters[entry.key] = List<String>.from(entry.value);
    }
    final updated = latest.copyWith(teamRosters: updatedRosters);
    await LocalEventStore.instance.saveTournament(updated);
    LocalEventStore.instance.syncTournamentToSupabase(updated.id);
    if (!mounted) return;
    setState(() => _tournament = updated);
  }

  Future<void> _confirmRemoveTeamFromTournament(String teamName) async {
    final t = _tournament;
    if (t == null || t.teams.length <= 2) return;
    final ok = await showRemoveTournamentTeamDialog(
      context,
      teamName: teamName,
    );
    if (!ok) return;
    final updatedRosters = {
      for (final e in t.teamRosters.entries) e.key: List<String>.from(e.value),
    }..remove(teamName);
    final updated = t.copyWith(teamRosters: updatedRosters);
    await LocalEventStore.instance.saveTournament(updated);
    LocalEventStore.instance.syncTournamentToSupabase(updated.id);
    if (!mounted) return;
    setState(() => _tournament = updated);
  }

  Future<void> _saveTeamRoster(String teamName, List<String> nextRoster) async {
    final t = _tournament;
    if (t == null) return;
    final updatedRosters = {
      for (final e in t.teamRosters.entries) e.key: List<String>.from(e.value),
    };
    updatedRosters[teamName] = List<String>.from(nextRoster);
    final updated = t.copyWith(teamRosters: updatedRosters);
    await LocalEventStore.instance.saveTournament(updated);
    LocalEventStore.instance.syncTournamentToSupabase(updated.id);
    if (!mounted) return;
    setState(() => _tournament = updated);
  }

  Future<void> _openAddPlayersSheet(String teamName) async {
    final t = _tournament;
    if (t == null) return;
    final savedTeams = await LocalEventStore.instance.listTeams();
    final savedClubPlayers = <String>[];
    for (final st in savedTeams) {
      if (st.name.trim().toLowerCase() == teamName.trim().toLowerCase()) {
        for (final p in st.players) {
          final trimmed = p.trim();
          if (trimmed.isNotEmpty &&
              !savedClubPlayers.any(
                (e) => e.toLowerCase() == trimmed.toLowerCase(),
              )) {
            savedClubPlayers.add(trimmed);
          }
        }
      }
    }
    if (!mounted) return;
    await showAddTournamentPlayersSheet(
      context,
      teamName: teamName,
      initialRoster: t.teamRosters[teamName] ?? const [],
      savedClubPlayers: savedClubPlayers,
      onSaveRoster: (next) => _saveTeamRoster(teamName, next),
    );
  }

  Future<void> _renamePlayerInRoster(String teamName, String currentName) async {
    final t = _tournament;
    if (t == null) return;
    final roster = List<String>.from(t.teamRosters[teamName] ?? const []);
    final idx = roster.indexOf(currentName);
    if (idx < 0) return;
    final renamed = await showRenameTournamentPlayerDialog(
      context,
      teamName: teamName,
      currentName: currentName,
      roster: roster,
    );
    if (renamed == null || renamed == currentName) return;
    roster[idx] = renamed;
    await _saveTeamRoster(teamName, roster);
  }

  Future<void> _removePlayerFromRoster(
    String teamName,
    String playerName,
  ) async {
    final t = _tournament;
    if (t == null) return;
    final previous = List<String>.from(t.teamRosters[teamName] ?? const []);
    final next = List<String>.from(previous)..remove(playerName);
    await _saveTeamRoster(teamName, next);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text("Removed $playerName from this tournament's squad"),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _saveTeamRoster(teamName, previous),
          ),
        ),
      );
  }

  Future<void> _confirmDiscardUnstartedMatch(
    DerivedMatchState match,
    String label,
  ) async {
    final ok = await showDiscardUnstartedMatchDialog(context, label: label);
    if (!ok) return;
    await LocalEventStore.instance.deleteMatch(match.config.id);
    if (!mounted) return;
    _load();
  }

  void _handleTapFixture(ScheduledFixture f) {
    if (f.match != null) {
      _openExistingMatch(f.match!.config.id);
    } else if (!_readOnly && f.isReadyToStart) {
      _openStartFixtureSheet(f);
    }
  }

  Widget? _buildPrimaryFab(
    BuildContext context,
    Tournament t,
    TournamentOverview overview,
  ) {
    final c = context.crease;
    final liveFixture = overview.allFixtures
        .where((f) => f.isLive && f.match != null)
        .firstOrNull;
    final liveOpenMatch = t.structure == TournamentStructure.open
        ? overview.extraMatches
            .where((m) => m.status == MatchStatus.live)
            .firstOrNull
        : null;
    final nextReadyFixture =
        overview.allFixtures.where((f) => f.isReadyToStart).firstOrNull;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fabFg = isDark ? const Color(0xFF07120D) : Colors.white;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(CreaseRadius.control + 2),
    );

    if (liveFixture != null) {
      return FloatingActionButton.extended(
        backgroundColor: c.pitchGreen,
        foregroundColor: fabFg,
        elevation: 2,
        shape: shape,
        onPressed: () => _openExistingMatch(liveFixture.match!.config.id),
        icon: const Icon(Icons.sports_cricket_rounded),
        label: Text(
          'Resume ${liveFixture.label}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    }
    if (liveOpenMatch != null) {
      return FloatingActionButton.extended(
        backgroundColor: c.pitchGreen,
        foregroundColor: fabFg,
        elevation: 2,
        shape: shape,
        onPressed: () => _openExistingMatch(liveOpenMatch.config.id),
        icon: const Icon(Icons.sports_cricket_rounded),
        label: const Text(
          'Resume live match',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    }
    if (t.structure == TournamentStructure.open && t.teams.length >= 2) {
      return FloatingActionButton.extended(
        backgroundColor: c.pitchGreen,
        foregroundColor: fabFg,
        elevation: 2,
        shape: shape,
        onPressed: _startOpenTournamentMatch,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text(
          'Start match',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    }
    if (nextReadyFixture != null) {
      return FloatingActionButton.extended(
        backgroundColor: c.pitchGreen,
        foregroundColor: fabFg,
        elevation: 2,
        shape: shape,
        onPressed: () => _openStartFixtureSheet(nextReadyFixture),
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(
          'Start ${nextReadyFixture.label}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;

    if (_loading) {
      return Scaffold(
        backgroundColor: c.ground,
        appBar: AppBar(),
        body: const Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              CreaseSkeletonBox(height: 220),
              SizedBox(height: 12),
              CreaseSkeletonBox(height: 96),
            ],
          ),
        ),
      );
    }

    final t = _tournament;
    if (t == null) {
      return Scaffold(
        backgroundColor: c.ground,
        appBar: AppBar(title: const Text('Tournament')),
        body: const Center(child: Text('Tournament not found.')),
      );
    }

    final overview = TournamentEngine.deriveOverview(
      t,
      _matches,
      forceUnlockKnockouts: _unlockKnockoutsEarly,
    );
    final mvpList = StatsEngine.byMvp(StatsEngine.derive(_matches));
    final tournamentMvp = mvpList.isNotEmpty ? mvpList.first : null;
    final isPureKnockout = t.structure == TournamentStructure.knockout;

    final tabs = isPureKnockout
        ? const [Tab(text: 'Bracket'), Tab(text: 'Teams')]
        : const [
            Tab(text: 'Standings'),
            Tab(text: 'Fixtures'),
            Tab(text: 'Teams'),
          ];
    final teamsTabIndex = tabs.length - 1;

    return DefaultTabController(
      key: ValueKey('tabs-${t.id}'),
      length: tabs.length,
      initialIndex: t.teams.length < 2 ? teamsTabIndex : 0,
      child: Builder(
        builder: (tabCtx) {
          final tabController = DefaultTabController.of(tabCtx);
          return Scaffold(
            backgroundColor: c.ground,
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    [
                      '${t.structure.shortLabel} · ${t.formatLabel} · ${t.teams.length} teams',
                      if (t.location != null && t.location!.isNotEmpty)
                        t.location!,
                      if (t.dateRangeLabel != null) t.dateRangeLabel!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Share tournament',
                  icon: const Icon(Icons.share_rounded, size: 20),
                  onPressed: () =>
                      _shareTournament(t, overview, tournamentMvp),
                ),
                if (!_readOnly)
                  CreaseMenuButton<String>(
                    sheetTitle: t.name,
                    tooltip: 'Tournament options',
                    onSelected: (value) {
                      if (value == 'edit') {
                        _editTournamentDetails();
                      } else if (value == 'delete') {
                        _confirmDeleteTournament();
                      }
                    },
                    items: const [
                      CreaseMenuItem(
                        value: 'edit',
                        label: 'Edit details',
                        subtitle: 'Update name, venue, or dates',
                        icon: Icons.edit_outlined,
                      ),
                      CreaseMenuItem(
                        value: 'delete',
                        label: 'Delete tournament',
                        subtitle: 'Played matches & stats stay in your history',
                        icon: Icons.delete_outline_rounded,
                        isDestructive: true,
                      ),
                    ],
                  ),
              ],
              bottom: TabBar(
                labelColor: c.inkPrimary,
                indicatorColor: c.pitchGreen,
                indicatorWeight: 2.5,
                unselectedLabelColor: c.inkSecondary,
                dividerColor: c.hairlineSubtle,
                labelStyle: Theme.of(context).textTheme.titleSmall,
                tabs: tabs,
              ),
            ),
            floatingActionButton: _readOnly
                ? null
                : ListenableBuilder(
                    listenable: tabController,
                    builder: (_, _) {
                      if (tabController.index == teamsTabIndex) {
                        return const SizedBox.shrink();
                      }
                      return _buildPrimaryFab(context, t, overview) ??
                          const SizedBox.shrink();
                    },
                  ),
            body: TabBarView(
              children: [
                if (!isPureKnockout)
                  TournamentStandingsTab(
                    tournament: t,
                    overview: overview,
                    tournamentMvp: tournamentMvp,
                    onAddTeams: _openAddTeamSheet,
                    onTapFixture: _handleTapFixture,
                    onUnlockKnockoutsEarly: _confirmUnlockKnockoutsEarly,
                    readOnly: _readOnly,
                  ),
                TournamentFixturesTab(
                  tournament: t,
                  overview: overview,
                  tournamentMvp: isPureKnockout ? tournamentMvp : null,
                  onAddTeams: _openAddTeamSheet,
                  onTapFixture: _handleTapFixture,
                  onTapExtraMatch: (m) => _openExistingMatch(m.config.id),
                  onDiscardLiveMatch: _confirmDiscardUnstartedMatch,
                  onUnlockKnockoutsEarly: _confirmUnlockKnockoutsEarly,
                  readOnly: _readOnly,
                ),
                TournamentTeamsTab(
                  tournament: t,
                  canEditTeams: !_readOnly &&
                      (t.structure == TournamentStructure.open ||
                          _matches.isEmpty),
                  playedTeams: {
                    for (final m in _matches) ...[
                      m.config.teamA.toLowerCase(),
                      m.config.teamB.toLowerCase(),
                    ],
                  },
                  onAddTeam: _openAddTeamSheet,
                  onRemoveTeam: _confirmRemoveTeamFromTournament,
                  onAddPlayer: _openAddPlayersSheet,
                  onRenamePlayer: _renamePlayerInRoster,
                  onRemovePlayer: _removePlayerFromRoster,
                  readOnly: _readOnly,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
