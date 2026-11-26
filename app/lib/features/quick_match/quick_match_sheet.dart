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
  final _strikerCtrl = TextEditingController();
  final _nonStrikerCtrl = TextEditingController();
  final _bowlerCtrl = TextEditingController();
  final _customOversCtrl = TextEditingController(text: '30');

  String? _teamA;
  String? _teamB;
  String? _teamAId;
  String? _teamBId;
  String? _teamALocation;
  String? _teamBLocation;
  List<String> _teamARoster = const [];
  List<String> _teamBRoster = const [];
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
      _teamARoster = List<String>.from(roster);
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
        if (_teamARoster.isEmpty) {
          _teamARoster = List<String>.from(_knownTeams[_teamA!] ?? const []);
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
      final prevARoster = _teamARoster;
      _teamA = _teamB;
      _teamAId = _teamBId;
      _teamALocation = _teamBLocation;
      _teamARoster = _teamBRoster;
      _teamB = prevA;
      _teamBId = prevAId;
      _teamBLocation = prevALoc;
      _teamBRoster = prevARoster;
      _strikerCtrl.clear();
      _nonStrikerCtrl.clear();
      _bowlerCtrl.clear();
    });
  }

  Future<void> _openTeamPicker({required bool isBatting}) async {
    final otherSideName = ((isBatting ? _teamB : _teamA) ?? '').trim();
    final otherSide = otherSideName.toLowerCase();
    final otherSideId = isBatting ? _teamBId : _teamAId;
    final searchCtrl = TextEditingController();
    var remoteMatches = <({
      String id,
      String name,
      String? location,
      String profileCode,
      List<String> players,
    })>[];
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
            final qNormalized = q.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
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
            final remoteEntries = qNormalized.length < 4
                ? const <({
                    String id,
                    String name,
                    String? location,
                    String profileCode,
                    List<String> players,
                  })>[]
                : remoteMatches;

            final matchesOpposition =
                q.isNotEmpty && otherSide.isNotEmpty && qLower == otherSide;
            final exactLocalMatch = q.isNotEmpty && localLower.contains(qLower);
            final exactRemoteMatch = q.isNotEmpty &&
                remoteEntries.any(
                  (r) =>
                      r.name.toLowerCase() == qLower ||
                      r.profileCode
                              .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
                              .toLowerCase() ==
                          qNormalized,
                );
            final showCreateTop = q.isNotEmpty &&
                !matchesOpposition &&
                !exactLocalMatch &&
                !exactRemoteMatch;
            final totalRows = (showCreateTop ? 1 : 0) +
                localEntries.length +
                remoteEntries.length;

            void scheduleSearch(String text) {
              debounce?.cancel();
              final trimmed = text.trim();
              final norm = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
              if (norm.length < 4) {
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
              debounce = Timer(const Duration(milliseconds: 280), () async {
                final hit = await LocalEventStore.instance
                    .lookupTeamByProfileCode(trimmed);
                if (!ctx.mounted || seq != searchSeq) return;
                setModalState(() {
                  remoteMatches = (hit != null && !_savedTeamIds.contains(hit.id))
                      ? [
                          (
                            id: hit.id,
                            name: hit.name,
                            location: hit.location,
                            profileCode: hit.profileCode,
                            players: hit.squad.map((p) => p.displayName).toList(),
                          ),
                        ]
                      : const [];
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
                  .where((r) => r.id != otherSideId)
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
                            'Pick a saved team, enter an opponent\'s Team ID (e.g. BX-4K9M), or type a new name.',
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
                          hintText: 'Team name or Team ID (e.g. BX-4K9M)',
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
                                      tooltip: 'Clear search',
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
                                            remoteItem!.profileCode,
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
    final roster = List<String>.from(picked.players);
    final finalPickedName = picked.name.trim();

    setState(() {
      if (isBatting) {
        _teamA = finalPickedName;
        _teamAId = picked.id;
        _teamALocation = picked.location;
        _teamARoster = roster;
        _strikerCtrl.clear();
        _nonStrikerCtrl.clear();
      } else {
        _teamB = finalPickedName;
        _teamBId = picked.id;
        _teamBLocation = picked.location;
        _teamBRoster = roster;
        _bowlerCtrl.clear();
      }
    });
  }

  Future<void> _openOpeningPlayerPicker({
    required String title,
    required String? teamName,
    required List<String> roster,
    required TextEditingController controller,
    String? excludePlayer,
    required bool isBattingSide,
  }) async {
    final current = controller.text.trim();
    final excludeLower = excludePlayer?.trim().toLowerCase();
    final searchCtrl = TextEditingController();
    final squad = roster
        .where((p) => p.trim().isNotEmpty && !LocalEventStore.isPlaceholderPlayerName(p))
        .toList();

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        final maxSheetHeight = MediaQuery.sizeOf(ctx).height * 0.65;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final q = searchCtrl.text.trim();
            final qLower = q.toLowerCase();
            final filtered = squad
                .where((p) => q.isEmpty || p.toLowerCase().contains(qLower))
                .toList();
            final exactInSquad =
                q.isNotEmpty && squad.any((p) => p.toLowerCase() == qLower);
            final matchesExcluded =
                q.isNotEmpty && excludeLower != null && qLower == excludeLower;
            final showCustom =
                q.isNotEmpty && !exactInSquad && !matchesExcluded;

            void submitQuery() {
              if (q.isEmpty || matchesExcluded) return;
              final exact = squad
                  .where((p) => p.toLowerCase() == qLower)
                  .firstOrNull;
              Navigator.pop(ctx, exact ?? q);
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxSheetHeight),
                child: GlassSurface(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(CreaseRadius.sheet),
                  ),
                  fillColor: c.surfaceSheet,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CreaseSheetHeader(
                          title: title,
                          subtitle: teamName != null && teamName.isNotEmpty
                              ? teamName
                              : 'Pick from squad or type a player name',
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: searchCtrl,
                          autofocus: squad.isEmpty,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.done,
                          onChanged: (_) => setModalState(() {}),
                          onSubmitted: (_) => submitQuery(),
                          decoration: InputDecoration(
                            hintText: squad.isEmpty
                                ? 'Type player name'
                                : 'Search squad or type a name',
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 19,
                            ),
                            suffixIcon: searchCtrl.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      searchCtrl.clear();
                                      setModalState(() {});
                                    },
                                  ),
                          ),
                        ),
                        if (matchesExcluded) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Already selected for the other crease end.',
                            style: Theme.of(ctx)
                                .textTheme
                                .labelMedium
                                ?.copyWith(color: c.inkSecondary),
                          ),
                        ],
                        if (showCustom || filtered.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Flexible(
                            child: Container(
                              decoration: BoxDecoration(
                                color: c.surfaceKey,
                                borderRadius: BorderRadius.circular(
                                  CreaseRadius.control,
                                ),
                                border: Border.all(color: c.hairline),
                              ),
                              child: ListView.separated(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                itemCount:
                                    (showCustom ? 1 : 0) + filtered.length,
                                separatorBuilder: (_, _) => Divider(
                                  height: 1,
                                  indent: 14,
                                  endIndent: 14,
                                  color: c.hairline,
                                ),
                                itemBuilder: (ctx, i) {
                                  if (showCustom && i == 0) {
                                    return ListTile(
                                      dense: true,
                                      leading: Container(
                                        width: 28,
                                        height: 28,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: c.pitchGreen
                                              .withValues(alpha: 0.14),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.person_add_alt_1_rounded,
                                          size: 15,
                                          color: c.pitchGreen,
                                        ),
                                      ),
                                      title: Text(
                                        'Use "$q"',
                                        style: TextStyle(
                                          color: c.pitchGreen,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      onTap: () => Navigator.pop(ctx, q),
                                    );
                                  }
                                  final name =
                                      filtered[i - (showCustom ? 1 : 0)];
                                  final isExcluded = excludeLower != null &&
                                      name.toLowerCase() == excludeLower;
                                  final isSelected =
                                      name.toLowerCase() ==
                                          current.toLowerCase();
                                  return ListTile(
                                    dense: true,
                                    enabled: !isExcluded,
                                    title: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                      ),
                                    ),
                                    subtitle: isExcluded
                                        ? const Text('Already on crease')
                                        : null,
                                    trailing: isSelected
                                        ? Icon(
                                            Icons.check_rounded,
                                            size: 18,
                                            color: c.pitchGreen,
                                          )
                                        : null,
                                    onTap: isExcluded
                                        ? null
                                        : () => Navigator.pop(ctx, name),
                                  );
                                },
                              ),
                            ),
                          ),
                        ] else if (squad.isEmpty && q.isEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            'No saved squad yet — type a name above and tap done.',
                            style: Theme.of(ctx)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: c.inkSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    Future<void>.delayed(const Duration(milliseconds: 500), searchCtrl.dispose);
    if (picked == null || picked.trim().isEmpty || !mounted) return;
    final clean = picked.trim();
    setState(() {
      controller.text = clean;
      final targetRoster = isBattingSide ? _teamARoster : _teamBRoster;
      if (!targetRoster.any((p) => p.toLowerCase() == clean.toLowerCase())) {
        final updated = [...targetRoster, clean];
        if (isBattingSide) {
          _teamARoster = updated;
        } else {
          _teamBRoster = updated;
        }
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

  String get _openingPlayersPreview {
    final s = _strikerCtrl.text.trim();
    final ns = _nonStrikerCtrl.text.trim();
    final bw = _bowlerCtrl.text.trim();
    final batters = [if (s.isNotEmpty) s, if (ns.isNotEmpty) ns].join(', ');
    if (batters.isEmpty && bw.isEmpty) {
      return 'Pick from squad, or set on the scoring pad';
    }
    if (batters.isNotEmpty && bw.isNotEmpty) return '$batters · $bw';
    return batters.isNotEmpty ? batters : bw;
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

    final striker = _strikerCtrl.text.trim();
    final nonStriker = _nonStrikerCtrl.text.trim();
    final bowler = _bowlerCtrl.text.trim();

    final dir = LocalEventStore.instance.directory;
    final adHoc = <String, String>{};

    String? resolveIdForSide(String name, String? teamId) {
      final clean = name.trim();
      if (clean.isEmpty) return null;
      if (teamId != null && teamId.isNotEmpty) {
        final match = dir
            .activePlayersForTeam(teamId)
            .where((p) => p.displayName.trim().toLowerCase() == clean.toLowerCase())
            .firstOrNull;
        if (match != null) return match.id;
      }
      for (final e in adHoc.entries) {
        if (e.value.trim().toLowerCase() == clean.toLowerCase()) return e.key;
      }
      final newId = _uuid.v4();
      adHoc[newId] = clean;
      return newId;
    }

    final squadAIds = (_teamAId != null && _teamAId!.isNotEmpty)
        ? dir.activePlayersForTeam(_teamAId!).map((p) => p.id).toList()
        : <String>[];
    final squadBIds = (_teamBId != null && _teamBId!.isNotEmpty)
        ? dir.activePlayersForTeam(_teamBId!).map((p) => p.id).toList()
        : <String>[];

    final striker1Id = resolveIdForSide(striker, _teamAId);
    final nonStriker1Id = resolveIdForSide(nonStriker, _teamAId);
    final bowler1Id = resolveIdForSide(bowler, _teamBId);

    final rosterAIds = <String>[
      ...squadAIds,
      if (striker1Id != null && !squadAIds.contains(striker1Id)) striker1Id,
      if (nonStriker1Id != null && !squadAIds.contains(nonStriker1Id))
        nonStriker1Id,
    ];
    final rosterBIds = <String>[
      ...squadBIds,
      if (bowler1Id != null && !squadBIds.contains(bowler1Id)) bowler1Id,
    ];

    final config = MatchConfig(
      id: _uuid.v4(),
      teamA: teamA,
      teamB: teamB,
      teamAId: _teamAId,
      teamBId: _teamBId,
      battingFirstSide: MatchSide.a,
      oversLimit: oversLimit,
      playersPerSide: 11,
      formatLabel: _isTestMatch ? 'TEST' : _formatForOvers(oversLimit),
      openingStriker1Id: striker1Id,
      openingNonStriker1Id: nonStriker1Id,
      openingBowler1Id: bowler1Id,
      teamAPlayerIds: rosterAIds,
      teamBPlayerIds: rosterBIds,
      adHocPlayers: adHoc,
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
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _TeamSelectorTile(
                          label: 'Batting first',
                          teamName: _teamA,
                          subtitle: (_teamA != null &&
                                  _teamB != null &&
                                  _teamA!.trim().toLowerCase() ==
                                      _teamB!.trim().toLowerCase())
                              ? _teamALocation
                              : null,
                          onTap: () => _openTeamPicker(isBatting: true),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Center(
                          child: IconButton(
                            tooltip: 'Swap batting & bowling',
                            visualDensity: VisualDensity.compact,
                            onPressed: (_teamA != null || _teamB != null)
                                ? _swapTeams
                                : null,
                            icon: Icon(
                              Icons.swap_horiz_rounded,
                              size: 20,
                              color: (_teamA != null || _teamB != null)
                                  ? c.inkPrimary
                                  : c.inkSecondary,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: _TeamSelectorTile(
                          label: 'Bowling first',
                          teamName: _teamB,
                          subtitle: (_teamA != null &&
                                  _teamB != null &&
                                  _teamA!.trim().toLowerCase() ==
                                      _teamB!.trim().toLowerCase())
                              ? _teamBLocation
                              : null,
                          onTap: () => _openTeamPicker(isBatting: false),
                        ),
                      ),
                    ],
                  ),
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
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: c.surfaceKey,
                    borderRadius: BorderRadius.circular(CreaseRadius.control),
                    border: Border.all(color: c.hairline),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CreasePressable(
                        onTap: () =>
                            setState(() => _showPlayers = !_showPlayers),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Opening players',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                color: c.inkPrimary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Optional',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: c.inkSecondary,
                                              ),
                                        ),
                                      ],
                                    ),
                                    if (!_showPlayers) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        _openingPlayersPreview,
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
                                _showPlayers
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: c.inkSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: _showPlayers
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Divider(height: 1, color: c.hairline),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      10,
                                      12,
                                      12,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _PlayerSelectorField(
                                                label: 'Striker',
                                                playerName:
                                                    _strikerCtrl.text.trim(),
                                                placeholder: 'Select batter',
                                                onTap: () =>
                                                    _openOpeningPlayerPicker(
                                                  title: 'Select striker',
                                                  teamName: _teamA,
                                                  roster: _teamARoster,
                                                  controller: _strikerCtrl,
                                                  excludePlayer:
                                                      _nonStrikerCtrl.text,
                                                  isBattingSide: true,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: _PlayerSelectorField(
                                                label: 'Non-striker',
                                                playerName:
                                                    _nonStrikerCtrl.text.trim(),
                                                placeholder: 'Select batter',
                                                onTap: () =>
                                                    _openOpeningPlayerPicker(
                                                  title: 'Select non-striker',
                                                  teamName: _teamA,
                                                  roster: _teamARoster,
                                                  controller: _nonStrikerCtrl,
                                                  excludePlayer:
                                                      _strikerCtrl.text,
                                                  isBattingSide: true,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        _PlayerSelectorField(
                                          label: 'Opening bowler',
                                          playerName: _bowlerCtrl.text.trim(),
                                          placeholder: 'Select bowler',
                                          onTap: () =>
                                              _openOpeningPlayerPicker(
                                            title: 'Select opening bowler',
                                            teamName: _teamB,
                                            roster: _teamBRoster,
                                            controller: _bowlerCtrl,
                                            isBattingSide: false,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
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
    this.subtitle,
    required this.onTap,
  });

  final String label;
  final String? teamName;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final hasTeam = teamName != null && teamName!.isNotEmpty;
    final cleanSub = subtitle?.trim();
    final hasSub = hasTeam && cleanSub != null && cleanSub.isNotEmpty;
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hasTeam ? teamName! : 'Select team',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: hasTeam ? c.inkPrimary : c.inkSecondary,
                              fontWeight:
                                  hasTeam ? FontWeight.w600 : FontWeight.w500,
                            ),
                      ),
                      if (hasSub)
                        Text(
                          cleanSub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontSize: 10,
                                    color: c.inkSecondary,
                                  ),
                        ),
                    ],
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

class _PlayerSelectorField extends StatelessWidget {
  const _PlayerSelectorField({
    required this.label,
    required this.playerName,
    required this.placeholder,
    required this.onTap,
  });

  final String label;
  final String playerName;
  final String placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final display = playerName.isEmpty ? placeholder : playerName;
    final isPlaceholder =
        playerName.isEmpty || LocalEventStore.isPlaceholderPlayerName(playerName);
    return CreasePressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(
          color: c.surfaceSheet,
          borderRadius: BorderRadius.circular(CreaseRadius.control - 2),
          border: Border.all(color: c.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: c.inkSecondary,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isPlaceholder ? c.inkSecondary : c.inkPrimary,
                          fontWeight:
                              isPlaceholder ? FontWeight.w400 : FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.unfold_more_rounded,
              size: 16,
              color: c.inkSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
