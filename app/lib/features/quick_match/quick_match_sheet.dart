import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

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

  int _overs = 6;
  bool _showPlayers = false;

  @override
  void dispose() {
    _teamACtrl.dispose();
    _teamBCtrl.dispose();
    _strikerCtrl.dispose();
    _nonStrikerCtrl.dispose();
    _bowlerCtrl.dispose();
    super.dispose();
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

    final striker = _strikerCtrl.text.trim().isEmpty
        ? 'Batter 1'
        : _strikerCtrl.text.trim();
    final nonStriker = _nonStrikerCtrl.text.trim().isEmpty
        ? 'Batter 2'
        : _nonStrikerCtrl.text.trim();
    final bowler = _bowlerCtrl.text.trim().isEmpty
        ? 'Bowler 1'
        : _bowlerCtrl.text.trim();

    final config = MatchConfig(
      id: _uuid.v4(),
      teamA: teamA,
      teamB: teamB,
      oversLimit: _overs,
      playersPerSide: 11,
      formatLabel: _formatForOvers(_overs),
      battingFirstTeam: teamA,
      openingStrikerInnings1: striker,
      openingNonStrikerInnings1: nonStriker,
      openingBowlerInnings1: bowler,
      teamAPlayers: [striker, nonStriker],
      teamBPlayers: [bowler],
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
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Overs', style: Theme.of(context).textTheme.labelMedium),
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

