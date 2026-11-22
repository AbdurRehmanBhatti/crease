import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/local_event_store.dart';
import '../../domain/models.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/glass_surface.dart';

/// 3-tap Quick Match creator: teams, overs preset, and instant start.
Future<MatchConfig?> showQuickMatchSheet(BuildContext context) {
  return showModalBottomSheet<MatchConfig>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _QuickMatchSheet(),
  );
}

class _QuickMatchSheet extends StatefulWidget {
  const _QuickMatchSheet();

  @override
  State<_QuickMatchSheet> createState() => _QuickMatchSheetState();
}

class _QuickMatchSheetState extends State<_QuickMatchSheet> {
  static const _uuid = Uuid();
  final _teamACtrl = TextEditingController(text: 'Street XI');
  final _teamBCtrl = TextEditingController(text: 'Park XI');
  final _strikerCtrl = TextEditingController(text: 'Batter 1');
  final _nonStrikerCtrl = TextEditingController(text: 'Batter 2');
  final _bowlerCtrl = TextEditingController(text: 'Bowler 1');
  final _customOversCtrl = TextEditingController(text: '30');

  Map<String, List<String>> _knownTeams = {};
  int _overs = 6;
  bool _isCustomOvers = false;
  bool _isTestMatch = false;
  bool _showPlayers = false;

  @override
  void initState() {
    super.initState();
    _loadKnownTeams();
  }

  Future<void> _loadKnownTeams() async {
    final teams = await LocalEventStore.instance.listKnownTeamRosters();
    if (!mounted) return;
    setState(() => _knownTeams = teams);
  }

  Future<void> _openTeamPicker({required bool isBatting}) async {
    final otherSide = (isBatting ? _teamBCtrl.text : _teamACtrl.text)
        .trim()
        .toLowerCase();
    final searchCtrl = TextEditingController();

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final q = searchCtrl.text.trim().toLowerCase();
            final entries = _knownTeams.entries
                .where((e) => q.isEmpty || e.key.toLowerCase().contains(q))
                .toList();
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: GlassSurface(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                fillColor: c.surfaceSheet,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.6,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: c.hairline,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        isBatting
                            ? 'Select batting team'
                            : 'Select bowling team',
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: searchCtrl,
                        onChanged: (_) => setModalState(() {}),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          hintText: 'Search saved teams...',
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Flexible(
                        child: entries.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  'No matching teams.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(ctx).textTheme.bodyMedium,
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: entries.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (ctx, i) {
                                  final e = entries[i];
                                  final disabled =
                                      e.key.toLowerCase() == otherSide;
                                  final count = e.value.length;
                                  return ListTile(
                                    enabled: !disabled,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    title: Text(e.key),
                                    subtitle: Text(
                                      disabled
                                          ? 'Already selected as opposition'
                                          : count > 0
                                              ? '$count saved player${count == 1 ? '' : 's'}'
                                              : 'No saved players yet',
                                    ),
                                    trailing: disabled
                                        ? null
                                        : Icon(
                                            Icons.chevron_right_rounded,
                                            color: c.inkSecondary,
                                          ),
                                    onTap: disabled
                                        ? null
                                        : () => Navigator.pop(ctx, e.key),
                                  );
                                },
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

    if (picked == null || !mounted) return;
    final roster = _knownTeams[picked] ?? const [];
    setState(() {
      if (isBatting) {
        _teamACtrl.text = picked;
        if (roster.isNotEmpty) _strikerCtrl.text = roster[0];
        if (roster.length > 1) _nonStrikerCtrl.text = roster[1];
      } else {
        _teamBCtrl.text = picked;
        if (roster.isNotEmpty) _bowlerCtrl.text = roster[0];
      }
    });
  }

  @override
  void dispose() {
    _teamACtrl.dispose();
    _teamBCtrl.dispose();
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
    final teamA =
        _teamACtrl.text.trim().isEmpty ? 'Team A' : _teamACtrl.text.trim();
    final teamB =
        _teamBCtrl.text.trim().isEmpty ? 'Team B' : _teamBCtrl.text.trim();
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
    final rosterA = savedRosterA.isNotEmpty ? savedRosterA : [striker, nonStriker];
    final rosterB = savedRosterB.isNotEmpty ? savedRosterB : [bowler];
    final opener2A = rosterB.isNotEmpty ? rosterB[0] : 'Opener 1';
    final opener2B = rosterB.length > 1 ? rosterB[1] : 'Opener 2';
    final bowler2 = rosterA.isNotEmpty ? rosterA[0] : 'Bowler 1';

    final config = MatchConfig(
      id: _uuid.v4(),
      teamA: teamA,
      teamB: teamB,
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: GlassSurface(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        fillColor: c.surfaceSheet,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Quick Match',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Start scoring in seconds. Works completely offline.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _teamACtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Batting first',
                        suffixIcon: _knownTeams.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Choose saved team',
                                icon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                ),
                                onPressed: () =>
                                    _openTeamPicker(isBatting: true),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('v'),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _teamBCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Bowling first',
                        suffixIcon: _knownTeams.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Choose saved team',
                                icon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                ),
                                onPressed: () =>
                                    _openTeamPicker(isBatting: false),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Format / Overs',
                  style: Theme.of(context).textTheme.labelMedium),
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
                      checkmarkColor: Colors.white,
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
                    checkmarkColor: Colors.white,
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
                    checkmarkColor: Colors.white,
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
                  decoration: InputDecoration(
                    labelText: 'Custom overs per innings',
                    hintText: 'e.g. 15, 25, 40',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
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
                  decoration: InputDecoration(
                    labelText: 'Striker',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _nonStrikerCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Non-striker',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _bowlerCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Opening bowler',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.pitchGreen,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: _start,
                child: const Text(
                  'Start Scoring',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

