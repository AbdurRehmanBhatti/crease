import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/tournament_engine.dart';
import '../../theme/crease_theme.dart';
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
  final List<String> _teams = ['Lahore Lions', 'Karachi Kites', 'Islamabad Stars'];
  int _overs = 10;

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
        const SnackBar(content: Text('Add at least 2 teams to create a tournament.')),
      );
      return;
    }
    final name = _nameCtrl.text.trim().isEmpty
        ? 'Sunday Tape-Ball Cup'
        : _nameCtrl.text.trim();
    final tournament = Tournament(
      id: _uuid.v4(),
      name: name,
      oversLimit: _overs,
      playersPerSide: 11,
      formatLabel: _formatForOvers(_overs),
      teamRosters: {for (final t in _teams) t: <String>[]},
      createdAt: DateTime.now(),
    );
    Navigator.pop(context, tournament);
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
                'New Tournament',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Points table & NRR update automatically from every ball.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Tournament name',
                  hintText: 'e.g. Ramadan Night Cup',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Overs per match', style: Theme.of(context).textTheme.labelMedium),
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
                      checkmarkColor: Colors.white,
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
                'Teams (${_teams.length})',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final team in _teams)
                    InputChip(
                      label: Text(team),
                      onDeleted: () => setState(() => _teams.remove(team)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _teamCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: '+ Add team name',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onSubmitted: (_) => _addTeam(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _addTeam,
                    child: const Text('Add'),
                  ),
                ],
              ),
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
                onPressed: _create,
                child: const Text(
                  'Create Tournament',
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
