import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/local_event_store.dart';
import '../../domain/tournament_engine.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/crease_ui.dart';
import '../../widgets/glass_surface.dart';

Future<Tournament?> showCreateTournamentSheet(BuildContext context) {
  return showModalBottomSheet<Tournament>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _CreateTournamentSheet(),
  );
}

class _CreateTournamentSheet extends StatefulWidget {
  const _CreateTournamentSheet();

  @override
  State<_CreateTournamentSheet> createState() => _CreateTournamentSheetState();
}

class _CreateTournamentSheetState extends State<_CreateTournamentSheet> {
  static const _uuid = Uuid();
  final _nameCtrl = TextEditingController();
  final _teamCtrl = TextEditingController();
  final List<String> _teams = [];
  Map<String, List<String>> _knownRosters = {};
  int _overs = 10;

  @override
  void initState() {
    super.initState();
    _loadSavedTeams();
  }

  Future<void> _loadSavedTeams() async {
    final rosters = await LocalEventStore.instance.listKnownTeamRosters();
    if (!mounted) return;
    setState(() => _knownRosters = rosters);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _teamCtrl.dispose();
    super.dispose();
  }

  String _formatForOvers(int overs) => switch (overs) {
        20 => 'T20',
        10 => 'T10',
        50 => 'ODI',
        _ => '${overs}OV',
      };

  void _toggleSavedTeam(String teamName) {
    final idx =
        _teams.indexWhere((t) => t.toLowerCase() == teamName.toLowerCase());
    setState(() {
      if (idx >= 0) {
        _teams.removeAt(idx);
      } else {
        _teams.add(teamName);
      }
    });
  }

  void _addTeam() {
    final name = _teamCtrl.text.trim();
    if (name.isEmpty) return;
    if (_teams.any((t) => t.toLowerCase() == name.toLowerCase())) {
      _teamCtrl.clear();
      return;
    }
    setState(() {
      _teams.add(name);
      _teamCtrl.clear();
    });
  }

  void _create() {
    if (_teams.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select or add at least 2 teams to create a tournament.'),
        ),
      );
      return;
    }
    final name = _nameCtrl.text.trim().isEmpty
        ? 'Sunday Cup'
        : _nameCtrl.text.trim();
    final rosters = <String, List<String>>{};
    for (final t in _teams) {
      final matched = _knownRosters.entries
          .where((e) => e.key.toLowerCase() == t.toLowerCase())
          .firstOrNull;
      rosters[t] = List<String>.from(matched?.value ?? const <String>[]);
    }
    final tournament = Tournament(
      id: _uuid.v4(),
      name: name,
      oversLimit: _overs,
      playersPerSide: 11,
      formatLabel: _formatForOvers(_overs),
      teamRosters: rosters,
      createdAt: DateTime.now(),
    );
    Navigator.pop(context, tournament);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final savedNames = _knownRosters.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final customTeams = _teams
        .where(
          (t) => !savedNames.any((s) => s.toLowerCase() == t.toLowerCase()),
        )
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: GlassSurface(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CreaseRadius.sheet),
        ),
        fillColor: c.surfaceSheet,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CreaseSheetHeader(
                title: 'New tournament',
                subtitle: 'Set overs and pick participating teams.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Tournament name',
                  hintText: 'e.g. Ramadan Night Cup',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Overs per match',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final ov in [5, 6, 8, 10, 15, 20])
                    ChoiceChip(
                      label: Text('$ov'),
                      selected: _overs == ov,
                      selectedColor: c.pitchGreen,
                      labelStyle: TextStyle(
                        color: _overs == ov ? Colors.white : c.inkPrimary,
                        fontWeight:
                            _overs == ov ? FontWeight.w600 : FontWeight.w500,
                      ),
                      side: BorderSide(
                        color: _overs == ov ? c.pitchGreen : c.hairline,
                      ),
                      onSelected: (_) => setState(() => _overs = ov),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Teams (${_teams.length} selected)',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              if (savedNames.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final team in savedNames)
                      Builder(
                        builder: (context) {
                          final selected = _teams.any(
                            (t) => t.toLowerCase() == team.toLowerCase(),
                          );
                          return ChoiceChip(
                            label: Text(team),
                            selected: selected,
                            selectedColor: c.pitchGreen,
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : c.inkPrimary,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w500,
                            ),
                            side: BorderSide(
                              color: selected ? c.pitchGreen : c.hairline,
                            ),
                            onSelected: (_) => _toggleSavedTeam(team),
                          );
                        },
                      ),
                  ],
                ),
              ],
              if (customTeams.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final team in customTeams)
                      InputChip(
                        label: Text(team),
                        onDeleted: () => setState(() => _teams.remove(team)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _teamCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Add another team',
                      ),
                      onSubmitted: (_) => _addTeam(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                    ),
                    onPressed: _addTeam,
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _create,
                child: const Text('Create tournament'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
