import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../data/local_event_store.dart';
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
  bool _togglingVisibility = false;
  late bool _readOnly;
  RealtimeChannel? _publicRealtimeChannel;

  @override
  void initState() {
    super.initState();
    _readOnly = widget.readOnlyPublic;
    _load();
  }

  @override
  void dispose() {
    final ch = _publicRealtimeChannel;
    if (ch != null) {
      try {
        Supabase.instance.client.removeChannel(ch);
      } catch (_) {}
    }
    super.dispose();
  }

  void _subscribePublicTournamentUpdates() {
    if (_publicRealtimeChannel != null || !_readOnly) return;
    try {
      final client = Supabase.instance.client;
      _publicRealtimeChannel = client
          .channel('tournament-live-${widget.tournamentId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'matches',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tournament_id',
              value: widget.tournamentId,
            ),
            callback: (_) => _refreshRemoteInMemory(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'match_live_summary',
            callback: (payload) {
              final changedId =
                  (payload.newRecord['match_id'] ?? payload.oldRecord['match_id'])
                      ?.toString();
              if (changedId != null &&
                  _matches.any((m) => m.config.id == changedId)) {
                _refreshRemoteInMemory();
              }
            },
          )
          .subscribe();
    } catch (_) {}
  }

  Future<void> _refreshRemoteInMemory() async {
    final snap = await LocalEventStore.instance.fetchRemoteTournament(
      widget.tournamentId,
    );
    if (!mounted || snap == null) return;
    setState(() {
      _tournament = snap.tournament;
      _matches = snap.matches;
    });
  }

  Future<void> _toggleTournamentVisibility(bool goPublic) async {
    final t = _tournament;
    if (t == null || _togglingVisibility) return;
    HapticFeedback.selectionClick();
    setState(() => _togglingVisibility = true);
    try {
      final nextVis = goPublic
          ? BroadcastVisibility.public
          : BroadcastVisibility.unlisted;
      final updated = await LocalEventStore.instance.setTournamentVisibility(
        t.id,
        nextVis,
      );
      if (!mounted) return;
      if (updated != null) {
        setState(() => _tournament = updated);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                goPublic
                    ? 'Tournament & its live matches are now public on the Live tab.'
                    : 'Tournament switched to Unlisted (link only).',
              ),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _togglingVisibility = false);
    }
  }

  Future<void> _load() async {
    final store = LocalEventStore.instance;
    if (!widget.readOnlyPublic) {
      final localTournament = await store.getTournament(widget.tournamentId);
      if (localTournament != null) {
        await store.refreshDirectory();
        final unlockedEarly = await store.isTournamentKnockoutsUnlockedEarly(
          widget.tournamentId,
        );
        final matchConfigs =
            await store.listMatchesForTournament(widget.tournamentId);
        final derived = <DerivedMatchState>[];
        for (final cfg in matchConfigs) {
          final events = await store.getBallEvents(cfg.id);
          derived.add(store.deriveMatch(cfg, events));
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
    final snap = await store.fetchRemoteTournament(widget.tournamentId);
    if (!mounted) return;
    setState(() {
      _tournament = snap?.tournament;
      _matches = snap?.matches ?? const [];
      _unlockKnockoutsEarly = false;
      _readOnly = widget.readOnlyPublic || !(snap?.isOwner ?? false);
      _loading = false;
    });
    if (_readOnly && snap != null) {
      _subscribePublicTournamentUpdates();
    }
  }

  Future<void> _launchMatch({
    required Tournament tournament,
    required String battingFirst,
    required String bowlingFirst,
    required MatchStage stage,
    int? fixtureIndex,
  }) async {
    final entryA = tournament.entryForName(battingFirst);
    final entryB = tournament.entryForName(bowlingFirst);
    final dir = LocalEventStore.instance.directory;
    final rosterAIds = (entryA?.teamId != null && entryA!.teamId!.isNotEmpty)
        ? dir.activePlayersForTeam(entryA.teamId!).map((p) => p.id).toList()
        : const <String>[];
    final rosterBIds = (entryB?.teamId != null && entryB!.teamId!.isNotEmpty)
        ? dir.activePlayersForTeam(entryB.teamId!).map((p) => p.id).toList()
        : const <String>[];

    final matchConfig = MatchConfig(
      id: _uuid.v4(),
      teamA: battingFirst,
      teamB: bowlingFirst,
      teamAId: entryA?.teamId,
      teamBId: entryB?.teamId,
      battingFirstSide: MatchSide.a,
      oversLimit: tournament.oversLimit,
      playersPerSide: tournament.playersPerSide,
      lastManStands: tournament.lastManStands,
      maxOversPerBowler: tournament.maxOversPerBowler,
      formatLabel: tournament.formatLabel,
      teamAPlayerIds: rosterAIds,
      teamBPlayerIds: rosterBIds,
      tournamentId: tournament.id,
      tournamentStage: stage.name,
      fixtureIndex: fixtureIndex,
      isTestMatch: tournament.oversLimit == 0,
      visibility: tournament.visibility,
      venue: tournament.location,
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
                        IconButton(
                          tooltip: 'Clear date',
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 40, minHeight: 40),
                          onPressed: onClear,
                          icon: Icon(
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
    final savedTeams = await LocalEventStore.instance.listTeams();
    final teamByLower = {
      for (final st in savedTeams) st.name.trim().toLowerCase(): st,
    };
    if (!mounted) return;
    final added = await showAddTournamentTeamsSheet(
      context,
      tournament: t,
      knownRosters: knownRosters,
    );
    if (added == null || added.isEmpty) return;
    final latest = _tournament;
    if (latest == null) return;
    final nextEntries = List<TournamentTeamEntry>.from(latest.entries);
    final existingLower =
        nextEntries.map((e) => e.displayName.trim().toLowerCase()).toSet();
    final now = DateTime.now();
    for (final entry in added.entries) {
      final clean = entry.key.trim();
      if (clean.isEmpty || existingLower.contains(clean.toLowerCase())) {
        continue;
      }
      final saved = teamByLower[clean.toLowerCase()];
      nextEntries.add(
        TournamentTeamEntry(
          id: _uuid.v4(),
          tournamentId: latest.id,
          teamId: saved?.id,
          adHocName: saved == null ? clean : null,
          resolvedTeamName: saved?.name ?? clean,
          seedOrder: nextEntries.length,
          createdAt: now,
        ),
      );
      existingLower.add(clean.toLowerCase());
    }
    final updated = latest.copyWith(entries: nextEntries);
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
    final nextEntries = t.entries
        .where((e) => e.displayName.toLowerCase() != teamName.toLowerCase())
        .toList();
    final updated = t.copyWith(entries: nextEntries);
    await LocalEventStore.instance.saveTournament(updated);
    LocalEventStore.instance.syncTournamentToSupabase(updated.id);
    if (!mounted) return;
    setState(() => _tournament = updated);
  }

  Future<void> _saveTeamRoster(String teamName, List<String> nextRoster) async {
    final t = _tournament;
    if (t == null) return;
    final entry = t.entryForName(teamName);
    if (entry?.teamId == null) return;
    final existing = await LocalEventStore.instance.listPlayersForTeam(entry!.teamId!);
    final existingByLower = {
      for (final p in existing) p.displayName.trim().toLowerCase(): p,
    };
    final nextLower = nextRoster.map((n) => n.trim().toLowerCase()).toSet();
    for (final name in nextRoster) {
      final clean = name.trim();
      if (clean.isNotEmpty && !existingByLower.containsKey(clean.toLowerCase())) {
        await LocalEventStore.instance.addPlayerToClub(
          teamId: entry.teamId!,
          displayName: clean,
        );
      }
    }
    for (final p in existing) {
      if (!nextLower.contains(p.displayName.trim().toLowerCase())) {
        await LocalEventStore.instance.archivePlayer(p.id);
      }
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openAddPlayersSheet(String teamName) async {
    final t = _tournament;
    if (t == null) return;
    final entry = t.entryForName(teamName);
    final currentRoster = (entry?.teamId != null)
        ? LocalEventStore.instance.directory
            .activePlayersForTeam(entry!.teamId!)
            .map((p) => p.displayName)
            .toList()
        : const <String>[];
    if (!mounted) return;
    await showAddTournamentPlayersSheet(
      context,
      teamName: teamName,
      initialRoster: currentRoster,
      savedClubPlayers: currentRoster,
      onSaveRoster: (next) => _saveTeamRoster(teamName, next),
    );
  }

  Future<void> _renamePlayerInRoster(String teamName, String currentName) async {
    final t = _tournament;
    if (t == null) return;
    final entry = t.entryForName(teamName);
    if (entry?.teamId == null) return;
    final squad =
        LocalEventStore.instance.directory.activePlayersForTeam(entry!.teamId!);
    final target = squad
        .where((p) => p.displayName == currentName)
        .firstOrNull;
    if (target == null) return;
    final renamed = await showRenameTournamentPlayerDialog(
      context,
      teamName: teamName,
      currentName: currentName,
      roster: squad.map((p) => p.displayName).toList(),
    );
    if (renamed == null || renamed == currentName) return;
    await LocalEventStore.instance.renamePlayer(target.id, renamed);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _removePlayerFromRoster(
    String teamName,
    String playerName,
  ) async {
    final t = _tournament;
    if (t == null) return;
    final entry = t.entryForName(teamName);
    if (entry?.teamId == null) return;
    final squad =
        LocalEventStore.instance.directory.activePlayersForTeam(entry!.teamId!);
    final target = squad
        .where((p) => p.displayName == playerName)
        .firstOrNull;
    if (target == null) return;
    await LocalEventStore.instance.archivePlayer(target.id);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed $playerName from $teamName'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await LocalEventStore.instance.savePlayer(
                target.copyWith(archived: false),
              );
              if (mounted) setState(() {});
            },
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
    final mergedResolved = <String, String>{
      for (final m in _matches) ...m.resolvedPlayerNames,
      ...LocalEventStore.instance.directory.playerNamesById,
    };
    final mvpList = StatsEngine.byMvp(
      StatsEngine.derive(
        _matches,
        playerNamesById: mergedResolved,
        playerUserIdsById: LocalEventStore.instance.directory.playerUserIdsById,
      ),
    );
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
            body: Column(
              children: [
                if (!_readOnly)
                  _TournamentVisibilityBar(
                    isPublic: t.isPublicLive,
                    teamCount: t.teams.length,
                    busy: _togglingVisibility,
                    onToggle: _toggleTournamentVisibility,
                  ),
                Expanded(
                  child: TabBarView(
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
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TournamentVisibilityBar extends StatelessWidget {
  const _TournamentVisibilityBar({
    required this.isPublic,
    required this.teamCount,
    required this.busy,
    required this.onToggle,
  });

  final bool isPublic;
  final int teamCount;
  final bool busy;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final readyForLiveTab = teamCount >= 2;
    return Container(
      decoration: BoxDecoration(
        color: isPublic ? c.pitchGreenSoft.withValues(alpha: 0.45) : c.surfaceSheet,
        border: Border(bottom: BorderSide(color: c.hairlineSubtle)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          if (isPublic) ...[
            if (readyForLiveTab)
              const CreaseLiveDot(size: 7)
            else
              Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: c.pitchGreen,
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                readyForLiveTab
                    ? 'Public on Live tab · Fixtures live'
                    : 'Add 2+ teams to go live',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: c.pitchGreen,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
              ),
            ),
          ] else ...[
            Icon(
              Icons.lock_outline_rounded,
              size: 14,
              color: c.inkSecondary,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'Unlisted · Link only',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: c.inkSecondary,
                      fontSize: 12,
                    ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          if (busy)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: c.pitchGreen,
              ),
            )
          else
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: isPublic ? c.inkSecondary : c.pitchGreen,
                minimumSize: const Size(48, 36),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => onToggle(!isPublic),
              child: Text(
                isPublic ? 'Make unlisted' : 'Go live',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
