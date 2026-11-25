import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../config/app_links.dart';
import '../../../data/local_event_store.dart';
import '../../../domain/tournament_engine.dart';
import '../../../theme/crease_theme.dart';
import '../../../widgets/crease_ui.dart';
import '../../../widgets/glass_surface.dart';

/// Fast 2-tap toss sheet for starting any scheduled League or Knockout fixture.
/// Returns the chosen batting-first team name, or `null` if cancelled.
Future<String?> showStartFixtureSheet(
  BuildContext context, {
  required Tournament tournament,
  required ScheduledFixture fixture,
}) async {
  if (fixture.teamA == null || fixture.teamB == null) return null;
  final teamA = fixture.teamA!;
  final teamB = fixture.teamB!;
  String battingFirst = teamA;

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.crease;
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          return GlassSurface(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(CreaseRadius.sheet),
            ),
            fillColor: c.surfaceSheet,
            padding: EdgeInsets.fromLTRB(
              20,
              14,
              20,
              20 + MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CreaseSheetHeader(
                    title: '${fixture.label} · ${fixture.stage.label}',
                    subtitle: 'Select which team won the toss and bats first.',
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: c.surfaceKey,
                      borderRadius: BorderRadius.circular(CreaseRadius.control),
                      border: Border.all(color: c.hairlineSubtle),
                    ),
                    child: Row(
                      children: [
                        CreaseTeamBadge(name: teamA, size: 32),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            teamA,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(ctx).textTheme.titleSmall,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            'v',
                            style: Theme.of(ctx).textTheme.labelMedium,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            teamB,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: Theme.of(ctx).textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        CreaseTeamBadge(name: teamB, size: 32),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Batting first',
                    style: Theme.of(ctx).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  CreaseSegmentedControl<String>(
                    selected: battingFirst,
                    onChanged: (v) => setModalState(() => battingFirst = v),
                    items: [
                      (value: teamA, label: teamA, icon: null),
                      (value: teamB, label: teamB, icon: null),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(
                      'Start ${tournament.formatLabel} · ${fixture.label}',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  return confirmed == true ? battingFirst : null;
}

/// Symmetrical ad-hoc match picker for Open tournaments (auto-swaps if the
/// same team is tapped in the opposite row).
Future<({String teamA, String teamB, MatchStage stage})?>
    showStartOpenTournamentMatchSheet(
  BuildContext context, {
  required Tournament tournament,
}) async {
  if (tournament.teams.length < 2) return null;

  String teamA = tournament.teams[0];
  String teamB = tournament.teams[1];
  MatchStage stage = MatchStage.league;

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.crease;
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          return GlassSurface(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(CreaseRadius.sheet),
            ),
            fillColor: c.surfaceSheet,
            padding: EdgeInsets.fromLTRB(
              20,
              14,
              20,
              20 + MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const CreaseSheetHeader(title: 'Start tournament match'),
                    const SizedBox(height: 16),
                    Text(
                      'Match stage',
                      style: Theme.of(ctx).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 8),
                    CreaseSegmentedControl<MatchStage>(
                      selected: stage,
                      onChanged: (v) => setModalState(() => stage = v),
                      items: const [
                        (value: MatchStage.league, label: 'League', icon: null),
                        (
                          value: MatchStage.semiFinal,
                          label: 'Semi-Final',
                          icon: null,
                        ),
                        (
                          value: MatchStage.finalMatch,
                          label: 'Final',
                          icon: null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Batting first',
                      style: Theme.of(ctx).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final team in tournament.teams)
                          ChoiceChip(
                            label: Text(team),
                            selected: teamA == team,
                            selectedColor: c.pitchGreen,
                            labelStyle: TextStyle(
                              color:
                                  teamA == team ? Colors.white : c.inkPrimary,
                              fontWeight: teamA == team
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                            side: BorderSide(
                              color: teamA == team ? c.pitchGreen : c.hairline,
                            ),
                            onSelected: (_) => setModalState(() {
                              if (team == teamB) teamB = teamA;
                              teamA = team;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Bowling first',
                      style: Theme.of(ctx).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final team in tournament.teams)
                          ChoiceChip(
                            label: Text(team),
                            selected: teamB == team,
                            selectedColor: c.pitchGreen,
                            labelStyle: TextStyle(
                              color:
                                  teamB == team ? Colors.white : c.inkPrimary,
                              fontWeight: teamB == team
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                            side: BorderSide(
                              color: teamB == team ? c.pitchGreen : c.hairline,
                            ),
                            onSelected: (_) => setModalState(() {
                              if (team == teamA) teamA = teamB;
                              teamB = team;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(
                        'Start ${tournament.formatLabel} · $teamA v $teamB',
                      ),
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

  if (confirmed != true) return null;
  return (teamA: teamA, teamB: teamB, stage: stage);
}

/// Multi-select Search bottom sheet for adding registered Crease teams to a tournament.
/// Returns a map of newly selected team names to their initial rosters, or `null`.
Future<Map<String, List<String>>?> showAddTournamentTeamsSheet(
  BuildContext context, {
  required Tournament tournament,
  required Map<String, List<String>> knownRosters,
}) async {
  final ctrl = TextEditingController();
  final existingNames =
      tournament.teams.map((e) => e.trim().toLowerCase()).toSet();
  final savedTeamProfiles = await LocalEventStore.instance.listTeams();
  final savedIds = {for (final t in savedTeamProfiles) t.id};
  final savedRostersByName = {
    for (final t in savedTeamProfiles) t.name: t.players,
  };
  final availableSaved = savedTeamProfiles
      .map((t) => t.name)
      .where((name) => !existingNames.contains(name.trim().toLowerCase()))
      .toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  if (!context.mounted) {
    ctrl.dispose();
    return null;
  }

  final selectedTeams = <String>[];
  final selectedRosters = <String, List<String>>{};
  var remoteMatches =
      <({String id, String name, String? location, List<String> players})>[];
  var searchingRemote = false;
  Timer? searchDebounce;
  var searchSeq = 0;

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.crease;
      final maxSheetHeight = MediaQuery.sizeOf(ctx).height * 0.78;
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          final query = ctrl.text.trim();
          final qLower = query.toLowerCase();
          final selectedLower =
              selectedTeams.map((e) => e.toLowerCase()).toSet();
          final filteredLocal = query.isEmpty
              ? availableSaved
              : availableSaved
                  .where((name) => name.toLowerCase().contains(qLower))
                  .toList();
          final localLower = availableSaved.map((n) => n.toLowerCase()).toSet();
          final filteredRemote = query.length < 2
              ? const <
                  ({
                    String id,
                    String name,
                    String? location,
                    List<String> players
                  })>[]
              : remoteMatches
                  .where(
                    (r) =>
                        !existingNames.contains(r.name.toLowerCase()) &&
                        !localLower.contains(r.name.toLowerCase()),
                  )
                  .toList();

          final alreadyInTournament =
              query.isNotEmpty && existingNames.contains(qLower);
          final exactLocalMatch = query.isNotEmpty &&
              availableSaved.any((n) => n.toLowerCase() == qLower);
          final exactRemoteMatch = query.isNotEmpty &&
              filteredRemote.any((r) => r.name.toLowerCase() == qLower);
          final totalRows = filteredLocal.length + filteredRemote.length;

          void scheduleRemoteSearch(String text) {
            searchDebounce?.cancel();
            final trimmed = text.trim();
            if (trimmed.length < 2) {
              if (remoteMatches.isNotEmpty || searchingRemote) {
                setModalState(() {
                  remoteMatches = const [];
                  searchingRemote = false;
                });
              }
              return;
            }
            final seq = ++searchSeq;
            setModalState(() => searchingRemote = true);
            searchDebounce = Timer(const Duration(milliseconds: 300), () async {
              final results = await LocalEventStore.instance.searchPublicTeams(
                trimmed,
                excludeIds: savedIds,
              );
              if (!ctx.mounted || seq != searchSeq) return;
              setModalState(() {
                remoteMatches = results;
                searchingRemote = false;
              });
            });
          }

          void toggleTeam(String teamName, List<String> roster) {
            setModalState(() {
              final idx = selectedTeams.indexWhere(
                (e) => e.toLowerCase() == teamName.toLowerCase(),
              );
              if (idx >= 0) {
                final removed = selectedTeams.removeAt(idx);
                selectedRosters.remove(removed);
              } else {
                selectedTeams.add(teamName);
                selectedRosters[teamName] = List<String>.from(roster);
              }
            });
          }

          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxSheetHeight),
            child: GlassSurface(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(CreaseRadius.sheet),
              ),
              fillColor: c.surfaceSheet,
              padding: EdgeInsets.fromLTRB(
                20,
                14,
                20,
                16 + MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CreaseSheetHeader(
                      title: 'Add teams',
                      subtitle: selectedTeams.isEmpty
                          ? 'Search your teams or any registered club on Crease.'
                          : '${selectedTeams.length} selected · Schedule updates automatically',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ctrl,
                      autofocus: availableSaved.isEmpty,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        hintText: 'Search Crease teams',
                        suffixIcon: searchingRemote
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      ctrl.clear();
                                      scheduleRemoteSearch('');
                                      setModalState(() {});
                                    },
                                  ),
                      ),
                      onChanged: (v) {
                        setModalState(() {});
                        scheduleRemoteSearch(v);
                      },
                      onSubmitted: (_) {
                        if (exactLocalMatch || exactRemoteMatch) {
                          final localMatch = availableSaved
                              .where((n) => n.toLowerCase() == qLower)
                              .firstOrNull;
                          if (localMatch != null) {
                            if (!selectedLower.contains(qLower)) {
                              toggleTeam(
                                localMatch,
                                savedRostersByName[localMatch] ?? const [],
                              );
                            }
                          } else {
                            final remoteMatch = filteredRemote
                                .where((r) => r.name.toLowerCase() == qLower)
                                .firstOrNull;
                            if (remoteMatch != null &&
                                !selectedLower.contains(qLower)) {
                              toggleTeam(remoteMatch.name, remoteMatch.players);
                            }
                          }
                          ctrl.clear();
                          scheduleRemoteSearch('');
                          setModalState(() {});
                        }
                      },
                    ),
                    if (selectedTeams.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var i = 0; i < selectedTeams.length; i++) ...[
                              InputChip(
                                label: Text(selectedTeams[i]),
                                visualDensity: VisualDensity.compact,
                                onDeleted: () => setModalState(() {
                                  final removed = selectedTeams[i];
                                  selectedTeams.removeAt(i);
                                  selectedRosters.remove(removed);
                                }),
                              ),
                              if (i != selectedTeams.length - 1)
                                const SizedBox(width: 6),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (alreadyInTournament) ...[
                      const SizedBox(height: 10),
                      Text(
                        '"$query" is already in this tournament.',
                        style: Theme.of(ctx)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: c.wicketRed),
                      ),
                    ] else if (totalRows > 0) ...[
                      const SizedBox(height: 10),
                      Flexible(
                        child: Container(
                          decoration: BoxDecoration(
                            color: c.surfaceKey,
                            borderRadius:
                                BorderRadius.circular(CreaseRadius.control),
                            border: Border.all(color: c.hairlineSubtle),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: totalRows,
                            separatorBuilder: (_, _) =>
                                Divider(height: 1, color: c.hairlineSubtle),
                            itemBuilder: (_, index) {
                              if (index < filteredLocal.length) {
                                final teamName = filteredLocal[index];
                                final isChecked = selectedLower
                                    .contains(teamName.toLowerCase());
                                final roster = savedRostersByName[teamName] ??
                                    const <String>[];
                                return ListTile(
                                  dense: true,
                                  leading: CreaseTeamBadge(
                                    name: teamName,
                                    size: 28,
                                  ),
                                  title: Text(
                                    teamName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    roster.isEmpty
                                        ? 'Your saved team'
                                        : '${roster.length} ${roster.length == 1 ? 'player' : 'players'}',
                                    style: Theme.of(ctx).textTheme.bodySmall,
                                  ),
                                  trailing: Icon(
                                    isChecked
                                        ? Icons.check_circle_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    size: 22,
                                    color: isChecked
                                        ? c.pitchGreen
                                        : c.inkSecondary,
                                  ),
                                  onTap: () => toggleTeam(teamName, roster),
                                );
                              }
                              final remote =
                                  filteredRemote[index - filteredLocal.length];
                              final isChecked = selectedLower
                                  .contains(remote.name.toLowerCase());
                              return ListTile(
                                dense: true,
                                leading: CreaseTeamBadge(
                                  name: remote.name,
                                  size: 28,
                                ),
                                title: Text(
                                  remote.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  [
                                    'On Crease',
                                    if (remote.location != null &&
                                        remote.location!.isNotEmpty)
                                      remote.location!,
                                    if (remote.players.isNotEmpty)
                                      '${remote.players.length} ${remote.players.length == 1 ? 'player' : 'players'}',
                                  ].join(' · '),
                                  style: Theme.of(ctx).textTheme.bodySmall,
                                ),
                                trailing: Icon(
                                  isChecked
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  size: 22,
                                  color: isChecked
                                      ? c.pitchGreen
                                      : c.inkSecondary,
                                ),
                                onTap: () =>
                                    toggleTeam(remote.name, remote.players),
                              );
                            },
                          ),
                        ),
                      ),
                    ] else if (query.isEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Search for any registered team on Crease to add to this tournament.',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ] else if (searchingRemote) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Searching Crease…',
                        textAlign: TextAlign.center,
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ] else if (query.length < 2) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Keep typing to search registered clubs on Crease.',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: c.surfaceKey,
                          borderRadius:
                              BorderRadius.circular(CreaseRadius.control),
                          border: Border.all(color: c.hairlineSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'No Crease team found for "$query"',
                              style: Theme.of(ctx).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Ask their captain to create the team in Crease, then search again to add them.',
                              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                    color: c.inkSecondary,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () {
                                Share.share(
                                  'Create your team "$query" in Crease so I can add you to "${tournament.name}"!\n${CreaseLinks.liveScorecardBaseUrl}',
                                );
                              },
                              icon: const Icon(Icons.share_rounded, size: 17),
                              label: const Text('Invite captain'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: selectedTeams.isEmpty
                          ? null
                          : () => Navigator.pop(ctx, true),
                      child: Text(
                        selectedTeams.isEmpty
                            ? 'Select teams to add'
                            : 'Add ${selectedTeams.length} ${selectedTeams.length == 1 ? 'team' : 'teams'}',
                      ),
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

  searchDebounce?.cancel();
  Future<void>.delayed(const Duration(milliseconds: 500), ctrl.dispose);

  if (confirmed != true || selectedTeams.isEmpty) return null;
  return {
    for (final name in selectedTeams)
      name: List<String>.from(selectedRosters[name] ?? const []),
  };
}

/// Fast batch-add sheet for editing a single team's tournament squad.
Future<void> showAddTournamentPlayersSheet(
  BuildContext context, {
  required String teamName,
  required List<String> initialRoster,
  required List<String> savedClubPlayers,
  required Future<void> Function(List<String> nextRoster) onSaveRoster,
}) async {
  final ctrl = TextEditingController();
  final focusNode = FocusNode();
  final workingRoster = List<String>.from(initialRoster);
  String? errorText;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.crease;
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          final availableFromSaved = savedClubPlayers
              .where(
                (p) => !workingRoster.any(
                  (w) => w.toLowerCase() == p.toLowerCase(),
                ),
              )
              .toList();

          Future<void> addSingleFromSaved(String name) async {
            if (workingRoster.any(
              (p) => p.toLowerCase() == name.toLowerCase(),
            )) {
              return;
            }
            setModalState(() {
              workingRoster.add(name);
              errorText = null;
            });
            await onSaveRoster(workingRoster);
          }

          Future<void> addAllFromSaved() async {
            if (availableFromSaved.isEmpty) return;
            setModalState(() {
              workingRoster.addAll(availableFromSaved);
              errorText = null;
            });
            await onSaveRoster(workingRoster);
          }

          Future<void> submitCurrent() async {
            final raw = ctrl.text.trim();
            if (raw.isEmpty) {
              setModalState(() => errorText = 'Enter a player name.');
              return;
            }
            final parts = raw
                .split(RegExp(r'[,;\n]+'))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            final added = <String>[];
            final duplicates = <String>[];
            for (final name in parts) {
              final exists = workingRoster.any(
                (p) => p.toLowerCase() == name.toLowerCase(),
              );
              if (exists) {
                duplicates.add(name);
              } else {
                workingRoster.add(name);
                added.add(name);
              }
            }
            if (added.isEmpty) {
              setModalState(() {
                errorText = duplicates.length == 1
                    ? '${duplicates.first} is already in this squad.'
                    : 'All entered players are already in this squad.';
              });
              return;
            }
            ctrl.clear();
            setModalState(() {
              errorText = duplicates.isEmpty
                  ? null
                  : 'Skipped duplicate: ${duplicates.join(', ')}';
            });
            await onSaveRoster(workingRoster);
            focusNode.requestFocus();
          }

          return GlassSurface(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(CreaseRadius.sheet),
            ),
            fillColor: c.surfaceSheet,
            padding: EdgeInsets.fromLTRB(
              20,
              14,
              20,
              20 + MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CreaseSheetHeader(
                      title: 'Tournament squad · $teamName',
                      subtitle:
                          '${workingRoster.length} in squad · Changes only affect this tournament',
                    ),
                    const SizedBox(height: 14),
                    if (availableFromSaved.isNotEmpty) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Pick from saved roster',
                              style: Theme.of(ctx).textTheme.labelMedium,
                            ),
                          ),
                          if (availableFromSaved.length > 1)
                            TextButton(
                              onPressed: addAllFromSaved,
                              child: Text(
                                'Add all (${availableFromSaved.length})',
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final p in availableFromSaved)
                            ActionChip(
                              avatar: Icon(
                                Icons.add_rounded,
                                size: 16,
                                color: c.pitchGreen,
                              ),
                              label: Text(p),
                              visualDensity: VisualDensity.compact,
                              side: BorderSide(
                                color: c.pitchGreen.withValues(alpha: 0.4),
                              ),
                              onPressed: () => addSingleFromSaved(p),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ctrl,
                            focusNode: focusNode,
                            autofocus: availableFromSaved.isEmpty,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              hintText: 'Add new or guest (e.g. Ali, Hamza)',
                              errorText: errorText,
                            ),
                            onChanged: (_) {
                              if (errorText != null) {
                                setModalState(() => errorText = null);
                              }
                            },
                            onSubmitted: (_) => submitCurrent(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: submitCurrent,
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                    if (workingRoster.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        'In this tournament (${workingRoster.length})',
                        style: Theme.of(ctx).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 160),
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final p in workingRoster)
                                InputChip(
                                  label: Text(p),
                                  visualDensity: VisualDensity.compact,
                                  onDeleted: () async {
                                    setModalState(
                                      () => workingRoster.remove(p),
                                    );
                                    await onSaveRoster(workingRoster);
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Done'),
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

  Future<void>.delayed(const Duration(milliseconds: 500), () {
    ctrl.dispose();
    focusNode.dispose();
  });
}

Future<bool> showUnlockKnockoutsDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Start knockouts early?'),
      content: const Text(
        'This seeds the knockout bracket using the current Points Table standings right now.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Unlock knockouts'),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<String?> showRenameTournamentDialog(
  BuildContext context, {
  required String currentName,
  required Set<String> otherNamesLower,
}) async {
  final ctrl = TextEditingController(text: currentName);
  String? errorText;
  final nextName = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        void submit() {
          final v = ctrl.text.trim();
          if (v.isEmpty) {
            setDialogState(() => errorText = 'Enter a tournament name.');
            return;
          }
          if (otherNamesLower.contains(v.toLowerCase())) {
            setDialogState(() {
              errorText =
                  'You already have "$v" — try adding a year or season.';
            });
            return;
          }
          Navigator.pop(ctx, v);
        }

        return AlertDialog(
          title: const Text('Rename tournament'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Tournament name',
              errorText: errorText,
            ),
            onChanged: (_) {
              if (errorText != null) setDialogState(() => errorText = null);
            },
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submit,
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
  Future<void>.delayed(const Duration(milliseconds: 500), ctrl.dispose);
  return nextName;
}

Future<String?> showRenameTournamentPlayerDialog(
  BuildContext context, {
  required String teamName,
  required String currentName,
  required List<String> roster,
}) async {
  final ctrl = TextEditingController(text: currentName);
  String? errorText;

  final renamed = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        void submit() {
          final next = ctrl.text.trim();
          if (next.isEmpty) {
            setDialogState(() => errorText = 'Name cannot be empty.');
            return;
          }
          final duplicate = roster.any(
            (p) =>
                p != currentName && p.toLowerCase() == next.toLowerCase(),
          );
          if (duplicate) {
            setDialogState(() => errorText = '$next is already in $teamName.');
            return;
          }
          Navigator.pop(ctx, next);
        }

        return AlertDialog(
          title: Text('Rename player · $teamName'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Player name',
              errorText: errorText,
            ),
            onChanged: (_) {
              if (errorText != null) {
                setDialogState(() => errorText = null);
              }
            },
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submit,
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
  Future<void>.delayed(const Duration(milliseconds: 500), ctrl.dispose);
  return renamed;
}

Future<bool> showDeleteTournamentDialog(
  BuildContext context, {
  required String tournamentName,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete $tournamentName?'),
      content: const Text(
        'This removes the tournament and its schedule. Played matches stay in your match history and player stats.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: ctx.crease.wicketRed,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<bool> showRemoveTournamentTeamDialog(
  BuildContext context, {
  required String teamName,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Remove $teamName?'),
      content: const Text(
        'Removes this team from the tournament schedule. Your saved team and past matches are not affected.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: ctx.crease.wicketRed,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<bool> showDiscardUnstartedMatchDialog(
  BuildContext context, {
  required String label,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Discard $label?'),
      content: const Text(
        'No balls have been bowled yet. Discarding removes this live match and returns the fixture to the schedule.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  return ok == true;
}
