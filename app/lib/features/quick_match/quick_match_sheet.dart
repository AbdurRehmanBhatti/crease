import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/local_event_store.dart';
import '../../domain/models.dart';
import '../../domain/team_profile.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/crease_ui.dart';
import '../../widgets/glass_surface.dart';

/// Quick Match creator: tappable team selectors, overs preset, and instant start.
Future<MatchConfig?> showQuickMatchSheet(
  BuildContext context, {
  Map<String, List<String>>? initialKnownTeams,
  String? defaultMyTeamName,
}) {
  return showModalBottomSheet<MatchConfig>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _QuickMatchSheet(
      initialKnownTeams: initialKnownTeams,
      defaultMyTeamName: defaultMyTeamName,
    ),
  );
}

class _QuickMatchSheet extends StatefulWidget {
  const _QuickMatchSheet({
    this.initialKnownTeams,
    this.defaultMyTeamName,
  });

  final Map<String, List<String>>? initialKnownTeams;
  final String? defaultMyTeamName;

  @override
  State<_QuickMatchSheet> createState() => _QuickMatchSheetState();
}

class _QuickMatchSheetState extends State<_QuickMatchSheet> {
  static const _uuid = Uuid();
  final _strikerCtrl = TextEditingController(text: 'Batter 1');
  final _nonStrikerCtrl = TextEditingController(text: 'Batter 2');
  final _bowlerCtrl = TextEditingController(text: 'Bowler 1');
  final _customOversCtrl = TextEditingController(text: '30');

  String? _teamA;
  String? _teamB;
  String? _teamAId;
  String? _teamBId;
  String? _teamALocation;
  String? _teamBLocation;
  Map<String, List<String>> _knownTeams = {};
  Set<String> _savedTeamIds = {};
  Map<String, String> _savedTeamIdByLowerName = {};
  Map<String, String> _savedTeamLocationByLowerName = {};
  int _overs = 6;
  bool _isCustomOvers = false;
  bool _isTestMatch = false;
  bool _showPlayers = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialKnownTeams != null) {
      _knownTeams = {
        for (final e in widget.initialKnownTeams!.entries)
          e.key: List<String>.from(e.value),
      };
    }
    final myTeam = widget.defaultMyTeamName?.trim();
    if (myTeam != null && myTeam.isNotEmpty) {
      _teamA = myTeam;
      final roster = _knownTeams[myTeam] ?? const [];
      if (roster.isNotEmpty) _strikerCtrl.text = roster[0];
      if (roster.length > 1) _nonStrikerCtrl.text = roster[1];
    }
    _loadKnownTeams();
  }

  Future<void> _loadKnownTeams() async {
    final results = await Future.wait([
      LocalEventStore.instance.listKnownTeamRosters(),
      LocalEventStore.instance.listTeams(),
    ]);
    final teams = results[0] as Map<String, List<String>>;
    final savedTeams = results[1] as List<TeamProfile>;
    if (!mounted) return;
    final savedIds = <String>{};
    final idByLower = <String, String>{};
    final locByLower = <String, String>{};
    for (final t in savedTeams) {
      final name = t.name.trim();
      final loc = t.location?.trim();
      savedIds.add(t.id);
      if (name.isNotEmpty) {
        idByLower.putIfAbsent(name.toLowerCase(), () => t.id);
        if (loc != null && loc.isNotEmpty) {
          locByLower.putIfAbsent(name.toLowerCase(), () => loc);
        }
      }
    }
    setState(() {
      _knownTeams = teams;
      _savedTeamIds = savedIds;
      _savedTeamIdByLowerName = idByLower;
      _savedTeamLocationByLowerName = locByLower;
      if (_teamA != null) {
        final key = _teamA!.trim().toLowerCase();
        _teamAId ??= idByLower[key];
        _teamALocation ??= locByLower[key];
        final roster = _knownTeams[_teamA!] ?? const [];
        if (_strikerCtrl.text == 'Batter 1' && roster.isNotEmpty) {
          _strikerCtrl.text = roster[0];
        }
        if (_nonStrikerCtrl.text == 'Batter 2' && roster.length > 1) {
          _nonStrikerCtrl.text = roster[1];
        }
      }
    });
  }

  void _swapTeams() {
    if (_teamA == null && _teamB == null) return;
    setState(() {
      final prevA = _teamA;
      final prevAId = _teamAId;
      final prevALoc = _teamALocation;
      _teamA = _teamB;
      _teamAId = _teamBId;
      _teamALocation = _teamBLocation;
      _teamB = prevA;
      _teamBId = prevAId;
      _teamBLocation = prevALoc;
      final rosterA = _teamA != null ? (_knownTeams[_teamA!] ?? const []) : const <String>[];
      final rosterB = _teamB != null ? (_knownTeams[_teamB!] ?? const []) : const <String>[];
      _strikerCtrl.text = rosterA.isNotEmpty ? rosterA[0] : 'Batter 1';
      _nonStrikerCtrl.text = rosterA.length > 1 ? rosterA[1] : 'Batter 2';
      _bowlerCtrl.text = rosterB.isNotEmpty ? rosterB[0] : 'Bowler 1';
    });
  }

  Future<void> _openTeamPicker({required bool isBatting}) async {
    final otherSideName = ((isBatting ? _teamB : _teamA) ?? '').trim();
    final otherSide = otherSideName.toLowerCase();
    final otherSideId = isBatting ? _teamBId : _teamAId;
    final otherSideLocation = (isBatting ? _teamBLocation : _teamALocation)?.trim();
    final searchCtrl = TextEditingController();
    var remoteMatches =
        <({String id, String name, String? location, List<String> players})>[];
    var searchingRemote = false;
    Timer? debounce;
    var searchSeq = 0;

    final picked = await showModalBottomSheet<
        ({String? id, String name, String? location, List<String> players})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        final maxSheetHeight = MediaQuery.sizeOf(ctx).height * 0.72;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final q = searchCtrl.text.trim();
            final qLower = q.toLowerCase();
            final localEntries = _knownTeams.entries
                .where(
                  (e) => q.isEmpty || e.key.toLowerCase().contains(qLower),
                )
                .toList()
              ..sort(
                (a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()),
              );
            final localLower =
                _knownTeams.keys.map((k) => k.toLowerCase()).toSet();
            final remoteEntries = q.length < 2
                ? const <
                    ({
                      String id,
                      String name,
                      String? location,
                      List<String> players
                    })>[]
                : remoteMatches;

            final matchesOpposition =
                q.isNotEmpty && otherSide.isNotEmpty && qLower == otherSide;
            final exactLocalMatch = q.isNotEmpty && localLower.contains(qLower);
            final exactRemoteMatch = q.isNotEmpty &&
                remoteEntries.any((r) => r.name.toLowerCase() == qLower);
            final showCreateTop = q.isNotEmpty &&
                !matchesOpposition &&
                !exactLocalMatch &&
                !exactRemoteMatch;
            final showCreateBottom = q.isNotEmpty &&
                !matchesOpposition &&
                !exactLocalMatch &&
                exactRemoteMatch;
            final totalRows = (showCreateTop ? 1 : 0) +
                localEntries.length +
                remoteEntries.length +
                (showCreateBottom ? 1 : 0);

            void scheduleSearch(String text) {
              debounce?.cancel();
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
              debounce = Timer(const Duration(milliseconds: 300), () async {
                final results = await LocalEventStore.instance.searchPublicTeams(
                  trimmed,
                  excludeIds: _savedTeamIds,
                  dedupeByName: false,
                );
                if (!ctx.mounted || seq != searchSeq) return;
                setModalState(() {
                  remoteMatches = results;
                  searchingRemote = false;
                });
              });
            }

            void selectFromSubmit() {
              if (q.isEmpty) return;
              final localHit = localEntries
                  .where((e) => e.key.toLowerCase() == qLower)
                  .firstOrNull;
              if (localHit != null) {
                final hitId = _savedTeamIdByLowerName[localHit.key.toLowerCase()];
                final sameTeam = (hitId != null && otherSideId != null)
                    ? hitId == otherSideId
                    : localHit.key.toLowerCase() == otherSide;
                if (!sameTeam) {
                  Navigator.pop(
                    ctx,
                    (
                      id: hitId,
                      name: localHit.key,
                      location: _savedTeamLocationByLowerName[
                          localHit.key.toLowerCase()],
                      players: localHit.value,
                    ),
                  );
                  return;
                }
              }
              final remoteHit = remoteEntries
                  .where(
                    (r) =>
                        r.name.toLowerCase() == qLower && r.id != otherSideId,
                  )
                  .firstOrNull;
              if (remoteHit != null) {
                Navigator.pop(
                  ctx,
                  (
                    id: remoteHit.id,
                    name: remoteHit.name,
                    location: remoteHit.location,
                    players: remoteHit.players,
                  ),
                );
                return;
              }
              if (matchesOpposition) return;
              Navigator.pop(
                ctx,
                (
                  id: null,
                  name: q,
                  location: null,
                  players: const <String>[],
                ),
              );
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
                        title: isBatting
                            ? 'Select batting team'
                            : 'Select bowling team',
                        subtitle:
                            'Search teams on Crease or enter a new team name.',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: searchCtrl,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (v) {
                          setModalState(() {});
                          scheduleSearch(v);
                        },
                        onSubmitted: (_) => selectFromSubmit(),
                        decoration: InputDecoration(
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 20),
                          hintText: 'Search or enter team name',
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
                              : q.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        searchCtrl.clear();
                                        scheduleSearch('');
                                        setModalState(() {});
                                      },
                                    ),
                        ),
                      ),
                      if (totalRows == 0) ...[
                        const SizedBox(height: 14),
                        Text(
                          matchesOpposition
                              ? '"$q" is already selected as the opposition.'
                              : q.length < 2
                                  ? 'Type a team name to search Crease or start with a new team.'
                                  : searchingRemote
                                      ? 'Searching Crease…'
                                      : 'No saved teams match "$q".',
                          textAlign: TextAlign.center,
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                color: matchesOpposition ? c.wicketRed : null,
                              ),
                        ),
                      ] else ...[
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
                              itemBuilder: (ctx, i) {
                                var cursor = i;
                                if (showCreateTop) {
                                  if (cursor == 0) {
                                    return ListTile(
                                      dense: true,
                                      leading: Container(
                                        width: 30,
                                        height: 30,
                                        decoration: BoxDecoration(
                                          color: c.pitchGreenSoft,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.add_rounded,
                                          size: 18,
                                          color: c.pitchGreen,
                                        ),
                                      ),
                                      title: Text(
                                        'Use "$q" as new team',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(ctx)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(color: c.pitchGreen),
                                      ),
                                      onTap: () => Navigator.pop(
                                        ctx,
                                        (
                                          id: null,
                                          name: q,
                                          location: null,
                                          players: const <String>[],
                                        ),
                                      ),
                                    );
                                  }
                                  cursor--;
                                }
                                if (showCreateBottom &&
                                    cursor ==
                                        localEntries.length +
                                            remoteEntries.length) {
                                  return ListTile(
                                    dense: true,
                                    leading: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: c.pillMutedBg,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.add_rounded,
                                        size: 18,
                                        color: c.inkSecondary,
                                      ),
                                    ),
                                    title: Text(
                                      'Use "$q" as new team',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(ctx).textTheme.titleSmall,
                                    ),
                                    subtitle: const Text(
                                      'Start with a blank roster',
                                    ),
                                    onTap: () => Navigator.pop(
                                      ctx,
                                      (
                                        id: null,
                                        name: q,
                                        location: null,
                                        players: const <String>[],
                                      ),
                                    ),
                                  );
                                }
                                final isLocal = cursor < localEntries.length;
                                final remoteItem = isLocal
                                    ? null
                                    : remoteEntries[
                                        cursor - localEntries.length];
                                final name = isLocal
                                    ? localEntries[cursor].key
                                    : remoteItem!.name;
                                final players = isLocal
                                    ? localEntries[cursor].value
                                    : remoteItem!.players;
                                final rowId = isLocal
                                    ? _savedTeamIdByLowerName[
                                        name.toLowerCase()]
                                    : remoteItem!.id;
                                final rowLocation = isLocal
                                    ? _savedTeamLocationByLowerName[
                                        name.toLowerCase()]
                                    : remoteItem!.location;
                                final disabled = (rowId != null &&
                                        otherSideId != null)
                                    ? rowId == otherSideId
                                    : (isLocal &&
                                        name.toLowerCase() == otherSide);
                                final count = players.length;
                                final sub = disabled
                                    ? 'Already selected as opposition'
                                    : isLocal
                                        ? [
                                            if (rowLocation != null &&
                                                rowLocation.isNotEmpty)
                                              rowLocation,
                                            if (count > 0)
                                              '$count saved player${count == 1 ? '' : 's'}'
                                            else
                                              'Your saved team',
                                          ].join(' · ')
                                        : [
                                            'On Crease',
                                            if (rowLocation != null &&
                                                rowLocation.isNotEmpty)
                                              rowLocation,
                                            if (count > 0)
                                              '$count player${count == 1 ? '' : 's'}',
                                          ].join(' · ');
                                return ListTile(
                                  dense: true,
                                  enabled: !disabled,
                                  leading: CreaseTeamBadge(
                                    name: name,
                                    size: 30,
                                  ),
                                  title: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(sub),
                                  trailing: disabled
                                      ? null
                                      : Icon(
                                          Icons.chevron_right_rounded,
                                          color: c.inkSecondary,
                                        ),
                                  onTap: disabled
                                      ? null
                                      : () => Navigator.pop(
                                            ctx,
                                            (
                                              id: rowId,
                                              name: name,
                                              location: rowLocation,
                                              players: players,
                                            ),
                                          ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    debounce?.cancel();
    Future<void>.delayed(const Duration(milliseconds: 500), searchCtrl.dispose);

    if (picked == null || !mounted) return;
    final roster = picked.players;
    var finalPickedName = picked.name.trim();

    // Keep the already-selected opposition's display name untouched so your
    // primary team stays clean; disambiguate only the newly picked second side
    // using its location (if distinct) or "(2)".
    if (otherSide.isNotEmpty && finalPickedName.toLowerCase() == otherSide) {
      final pickedLoc = picked.location?.trim() ?? '';
      final otherLoc = otherSideLocation ?? '';
      final sameLoc = pickedLoc.isNotEmpty &&
          otherLoc.isNotEmpty &&
          pickedLoc.toLowerCase() == otherLoc.toLowerCase();
      if (pickedLoc.isNotEmpty && !sameLoc) {
        finalPickedName = '$finalPickedName ($pickedLoc)';
      } else {
        finalPickedName = '$finalPickedName (2)';
      }
    }

    setState(() {
      if (roster.isNotEmpty) {
        _knownTeams[finalPickedName] = List<String>.from(roster);
      }
      if (isBatting) {
        _teamA = finalPickedName;
        _teamAId = picked.id;
        _teamALocation = picked.location;
        _strikerCtrl.text = roster.isNotEmpty ? roster[0] : 'Batter 1';
        _nonStrikerCtrl.text = roster.length > 1 ? roster[1] : 'Batter 2';
      } else {
        _teamB = finalPickedName;
        _teamBId = picked.id;
        _teamBLocation = picked.location;
        _bowlerCtrl.text = roster.isNotEmpty ? roster[0] : 'Bowler 1';
      }
    });
  }

  @override
  void dispose() {
    _strikerCtrl.dispose();
    _nonStrikerCtrl.dispose();
    _bowlerCtrl.dispose();
    _customOversCtrl.dispose();
    super.dispose();
  }

  int get _resolvedOvers {
    if (!_isCustomOvers) return _overs;
    final parsed = int.tryParse(_customOversCtrl.text.trim()) ?? 20;
    return parsed.clamp(1, 450);
  }

  String _formatForOvers(int overs) => switch (overs) {
        20 => 'T20',
        10 => 'T10',
        50 => 'ODI',
        _ => '${overs}OV',
      };

  void _start() {
    final teamA = _teamA?.trim() ?? '';
    final teamB = _teamB?.trim() ?? '';
    if (teamA.isEmpty || teamB.isEmpty) return;
    final oversLimit = _isTestMatch ? 0 : _resolvedOvers;

    final striker = _strikerCtrl.text.trim().isEmpty
        ? 'Batter 1'
        : _strikerCtrl.text.trim();
    final nonStriker = _nonStrikerCtrl.text.trim().isEmpty
        ? 'Batter 2'
        : _nonStrikerCtrl.text.trim();
    final bowler = _bowlerCtrl.text.trim().isEmpty
        ? 'Bowler 1'
        : _bowlerCtrl.text.trim();

    final savedRosterA = List<String>.from(_knownTeams[teamA] ?? const []);
    final savedRosterB = List<String>.from(_knownTeams[teamB] ?? const []);
    final rosterA =
        savedRosterA.isNotEmpty ? savedRosterA : [striker, nonStriker];
    final rosterB = savedRosterB.isNotEmpty ? savedRosterB : [bowler];
    final opener2A = rosterB.isNotEmpty ? rosterB[0] : 'Opener 1';
    final opener2B = rosterB.length > 1 ? rosterB[1] : 'Opener 2';
    final bowler2 = rosterA.isNotEmpty ? rosterA[0] : 'Bowler 1';

    final config = MatchConfig(
      id: _uuid.v4(),
      teamA: teamA,
      teamB: teamB,
      teamAId: _teamAId,
      teamBId: _teamBId,
      oversLimit: oversLimit,
      playersPerSide: 11,
      formatLabel: _isTestMatch ? 'TEST' : _formatForOvers(oversLimit),
      battingFirstTeam: teamA,
      openingStrikerInnings1: striker,
      openingNonStrikerInnings1: nonStriker,
      openingBowlerInnings1: bowler,
      openingStrikerInnings2: opener2A,
      openingNonStrikerInnings2: opener2B,
      openingBowlerInnings2: bowler2,
      teamAPlayers: rosterA,
      teamBPlayers: rosterB,
      isTestMatch: _isTestMatch,
      createdAt: DateTime.now(),
    );
    Navigator.pop(context, config);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final canStart = _teamA != null && _teamB != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: GlassSurface(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CreaseRadius.sheet),
        ),
        fillColor: c.surfaceSheet,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CreaseSheetHeader(
                  title: 'New match',
                  subtitle: 'Pick both teams and overs to open the scoring pad.',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _TeamSelectorTile(
                        label: 'Batting first',
                        teamName: _teamA,
                        onTap: () => _openTeamPicker(isBatting: true),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: IconButton(
                        tooltip: 'Swap batting & bowling',
                        visualDensity: VisualDensity.compact,
                        onPressed:
                            (_teamA != null || _teamB != null) ? _swapTeams : null,
                        icon: Icon(
                          Icons.swap_horiz_rounded,
                          size: 20,
                          color: (_teamA != null || _teamB != null)
                              ? c.inkPrimary
                              : c.inkSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _TeamSelectorTile(
                        label: 'Bowling first',
                        teamName: _teamB,
                        onTap: () => _openTeamPicker(isBatting: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Format / overs',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in const [
                      (5, '5'),
                      (6, '6'),
                      (8, '8'),
                      (10, 'T10'),
                      (20, 'T20'),
                      (50, 'ODI (50)'),
                    ])
                      ChoiceChip(
                        label: Text(entry.$2),
                        selected: !_isTestMatch &&
                            !_isCustomOvers &&
                            _overs == entry.$1,
                        selectedColor: c.pitchGreen,
                        labelStyle: TextStyle(
                          color: (!_isTestMatch &&
                                  !_isCustomOvers &&
                                  _overs == entry.$1)
                              ? Colors.white
                              : c.inkPrimary,
                          fontWeight: (!_isTestMatch &&
                                  !_isCustomOvers &&
                                  _overs == entry.$1)
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                        side: BorderSide(
                          color: (!_isTestMatch &&
                                  !_isCustomOvers &&
                                  _overs == entry.$1)
                              ? c.pitchGreen
                              : c.hairline,
                        ),
                        onSelected: (_) => setState(() {
                          _isTestMatch = false;
                          _isCustomOvers = false;
                          _overs = entry.$1;
                        }),
                      ),
                    ChoiceChip(
                      label: const Text('Test (4 inn)'),
                      selected: _isTestMatch,
                      selectedColor: c.pitchGreen,
                      labelStyle: TextStyle(
                        color: _isTestMatch ? Colors.white : c.inkPrimary,
                        fontWeight:
                            _isTestMatch ? FontWeight.w600 : FontWeight.w500,
                      ),
                      side: BorderSide(
                        color: _isTestMatch ? c.pitchGreen : c.hairline,
                      ),
                      onSelected: (_) => setState(() {
                        _isTestMatch = true;
                        _isCustomOvers = false;
                      }),
                    ),
                    ChoiceChip(
                      label: const Text('Custom'),
                      selected: !_isTestMatch && _isCustomOvers,
                      selectedColor: c.pitchGreen,
                      labelStyle: TextStyle(
                        color: (!_isTestMatch && _isCustomOvers)
                            ? Colors.white
                            : c.inkPrimary,
                        fontWeight: (!_isTestMatch && _isCustomOvers)
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                      side: BorderSide(
                        color: (!_isTestMatch && _isCustomOvers)
                            ? c.pitchGreen
                            : c.hairline,
                      ),
                      onSelected: (_) => setState(() {
                        _isTestMatch = false;
                        _isCustomOvers = true;
                      }),
                    ),
                  ],
                ),
                if (!_isTestMatch && _isCustomOvers) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _customOversCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Custom overs per innings',
                      hintText: 'e.g. 15, 25, 40',
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextButton.icon(
                  style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                  onPressed: () => setState(() => _showPlayers = !_showPlayers),
                  icon: Icon(
                    _showPlayers
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                  ),
                  label: const Text('Opening batters & bowler (optional)'),
                ),
                if (_showPlayers) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _strikerCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Striker'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nonStrikerCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Non-striker'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _bowlerCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration:
                        const InputDecoration(labelText: 'Opening bowler'),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: canStart ? _start : null,
                  child: Text(
                    canStart ? 'Start scoring' : 'Select both teams to start',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamSelectorTile extends StatelessWidget {
  const _TeamSelectorTile({
    required this.label,
    required this.teamName,
    required this.onTap,
  });

  final String label;
  final String? teamName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final hasTeam = teamName != null && teamName!.isNotEmpty;
    return CreasePressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: c.surfaceKey,
          borderRadius: BorderRadius.circular(CreaseRadius.control),
          border: Border.all(
            color: hasTeam ? c.pitchGreen.withValues(alpha: 0.45) : c.hairline,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: 11,
                    color: c.inkSecondary,
                  ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (hasTeam)
                  CreaseTeamBadge(name: teamName!, size: 24)
                else
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.pillMutedBg,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      Icons.search_rounded,
                      size: 14,
                      color: c.inkSecondary,
                    ),
                  ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    hasTeam ? teamName! : 'Select team',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: hasTeam ? c.inkPrimary : c.inkSecondary,
                          fontWeight:
                              hasTeam ? FontWeight.w600 : FontWeight.w500,
                        ),
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: c.inkSecondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
