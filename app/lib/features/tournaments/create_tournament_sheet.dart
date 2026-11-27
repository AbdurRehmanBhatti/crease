import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../data/local_event_store.dart';
import '../../domain/models.dart';
import '../../domain/tournament_engine.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/crease_ui.dart';
import '../../widgets/glass_surface.dart';
import '../live/widgets/live_broadcast_toggle.dart';

Future<Tournament?> showCreateTournamentSheet(BuildContext context) {
  return showModalBottomSheet<Tournament>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
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
  final _locationCtrl = TextEditingController();
  final _customOversCtrl = TextEditingController(text: '30');
  DateTime? _startDate;
  DateTime? _endDate;
  Set<String> _existingTournamentNames = {};
  String? _nameError;
  int _overs = 10;
  bool _isCustomOvers = false;
  bool _isTestMatch = false;
  TournamentStructure _structure = TournamentStructure.leagueKnockout;
  int _roundsPerPair = 1;
  int _knockoutQualifiers = 4;
  bool _isPublicLive = false;
  bool _creating = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _loadExistingNames();
  }

  Future<void> _loadExistingNames() async {
    final tournaments = await LocalEventStore.instance.listTournaments();
    if (!mounted) return;
    setState(() {
      _existingTournamentNames =
          tournaments.map((t) => t.name.trim().toLowerCase()).toSet();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    _customOversCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_startDate ?? now)
        : (_endDate ?? _startDate ?? now);
    final firstDate = isStart
        ? DateTime(now.year - 2)
        : (_startDate ?? DateTime(now.year - 2));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(firstDate) ? firstDate : initial,
      firstDate: firstDate,
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  int get _resolvedOvers {
    if (_isTestMatch) return 0;
    if (!_isCustomOvers) return _overs;
    final parsed = int.tryParse(_customOversCtrl.text.trim()) ?? 20;
    return parsed.clamp(1, 450);
  }

  String _formatForOvers(int overs) => switch (overs) {
        0 => 'TEST',
        20 => 'T20',
        10 => 'T10',
        50 => 'ODI',
        _ => '${overs}OV',
      };

  String _summaryText() {
    if (_structure == TournamentStructure.open) {
      return 'Flexible schedule with live Points Table & NRR';
    }
    if (_structure == TournamentStructure.knockout) {
      return 'Single-elimination bracket with auto-byes';
    }
    final koText = switch (_knockoutQualifiers) {
      4 => ' + Semis & Final',
      2 => ' + Final',
      _ => ' (league only)',
    };
    return '$_roundsPerPair× round-robin$koText';
  }

  Future<void> _create() async {
    if (_creating) return;
    final name = _nameCtrl.text.trim().isEmpty
        ? 'Sunday Cup'
        : _nameCtrl.text.trim();
    if (_existingTournamentNames.contains(name.toLowerCase())) {
      setState(() {
        _nameError =
            'You already have "$name" — try adding a year or season.';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    setState(() {
      _creating = true;
      _submitError = null;
    });

    final oversLimit = _resolvedOvers;
    final loc = _locationCtrl.text.trim();
    final tournament = Tournament(
      id: _uuid.v4(),
      name: name,
      location: loc.isEmpty ? null : loc,
      startDate: _startDate,
      endDate: _endDate,
      oversLimit: oversLimit,
      playersPerSide: 11,
      formatLabel: _formatForOvers(oversLimit),
      entries: const [],
      structure: _structure,
      roundsPerPair: _roundsPerPair,
      knockoutQualifiers:
          _structure == TournamentStructure.leagueKnockout
              ? _knockoutQualifiers
              : 0,
      visibility: _isPublicLive
          ? BroadcastVisibility.public
          : BroadcastVisibility.unlisted,
      createdAt: DateTime.now(),
    );

    try {
      await LocalEventStore.instance.saveTournament(tournament);
      await LocalEventStore.instance
          .syncTournamentToSupabase(tournament.id)
          .timeout(const Duration(seconds: 6), onTimeout: () {});
      if (!mounted) return;
      Navigator.pop(context, tournament);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _submitError = 'Could not create tournament. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final canCreate = _nameCtrl.text.trim().isNotEmpty;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return PopScope(
      canPop: !_creating,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
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
                  AbsorbPointer(
                    absorbing: _creating,
                    child: const CreaseSheetHeader(
                      title: 'New tournament',
                      subtitle:
                          'Set name, format, and overs — you can add teams next.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: AbsorbPointer(
                      absorbing: _creating,
                      child: AnimatedOpacity(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 160),
                        opacity: _creating ? 0.55 : 1.0,
                        child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _nameCtrl,
                          autofocus: true,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: 'Tournament name',
                            hintText: 'e.g. Ramadan Night Cup 2026',
                            errorText: _nameError,
                          ),
                          onChanged: (_) => setState(() => _nameError = null),
                          onSubmitted: (_) {
                            if (canCreate) _create();
                          },
                        ),
                const SizedBox(height: 16),
                Text(
                  'Tournament format',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                CreaseSegmentedControl<TournamentStructure>(
                  selected: _structure,
                  onChanged: (v) => setState(() => _structure = v),
                  items: const [
                    (
                      value: TournamentStructure.leagueKnockout,
                      label: 'League + KO',
                      icon: null,
                    ),
                    (
                      value: TournamentStructure.knockout,
                      label: 'Knockout',
                      icon: null,
                    ),
                    (
                      value: TournamentStructure.open,
                      label: 'Open',
                      icon: null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Format / overs per match',
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
                if (_structure == TournamentStructure.leagueKnockout) ...[
                  const SizedBox(height: 16),
                  Text(
                    'League rounds',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in const [(1, '1×'), (2, '2×')])
                        ChoiceChip(
                          label: Text(entry.$2),
                          selected: _roundsPerPair == entry.$1,
                          selectedColor: c.pitchGreen,
                          labelStyle: TextStyle(
                            color: _roundsPerPair == entry.$1
                                ? Colors.white
                                : c.inkPrimary,
                            fontWeight: _roundsPerPair == entry.$1
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                          side: BorderSide(
                            color: _roundsPerPair == entry.$1
                                ? c.pitchGreen
                                : c.hairline,
                          ),
                          onSelected: (_) => setState(
                            () => _roundsPerPair = entry.$1,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Knockout stage',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _koChip(context, value: 4, label: 'Top 4'),
                      _koChip(context, value: 2, label: 'Final'),
                      _koChip(context, value: 0, label: 'None'),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _locationCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Venue or city (optional)',
                    hintText: 'e.g. Model Town Ground, Lahore',
                    prefixIcon: Icon(Icons.location_on_outlined, size: 19),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DatePill(
                        label: 'Start date',
                        value: _startDate != null
                            ? Tournament.formatShortDate(_startDate!)
                            : null,
                        onTap: () => _pickDate(isStart: true),
                        onClear: _startDate == null
                            ? null
                            : () => setState(() => _startDate = null),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DatePill(
                        label: 'End date',
                        value: _endDate != null
                            ? Tournament.formatShortDate(_endDate!)
                            : null,
                        onTap: () => _pickDate(isStart: false),
                        onClear: _endDate == null
                            ? null
                            : () => setState(() => _endDate = null),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                LiveBroadcastToggleTile(
                  isPublic: _isPublicLive,
                  isTournament: true,
                  onChanged: (v) => setState(() => _isPublicLive = v),
                ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                      ),
                    ),
                  ),
                Divider(height: 1, color: c.hairlineSubtle),
                const SizedBox(height: 10),
                if (_submitError != null) ...[
                  Text(
                    _submitError!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: c.wicketRed,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: c.pitchGreen,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _summaryText(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: c.inkSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _creating ? c.pitchGreen : null,
                    foregroundColor: _creating ? c.onPitchGreen : null,
                    disabledBackgroundColor:
                        _creating ? c.pitchGreen : c.surfaceKey,
                    disabledForegroundColor:
                        _creating ? c.onPitchGreen : c.inkSecondary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: (canCreate && !_creating) ? _create : null,
                  child: _creating
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: c.onPitchGreen,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text('Creating tournament…'),
                          ],
                        )
                      : const Text('Create tournament'),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _koChip(
    BuildContext context, {
    required int value,
    required String label,
  }) {
    final c = context.crease;
    final selected = _knockoutQualifiers == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: c.pitchGreen,
      labelStyle: TextStyle(
        color: selected ? Colors.white : c.inkPrimary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
      side: BorderSide(color: selected ? c.pitchGreen : c.hairline),
      onSelected: (_) => setState(() => _knockoutQualifiers = value),
    );
  }
}

class _DatePill extends StatelessWidget {
  const _DatePill({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final hasValue = value != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CreaseRadius.control),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: c.surfaceKey,
          borderRadius: BorderRadius.circular(CreaseRadius.control),
          border: Border.all(
            color: hasValue ? c.pitchGreen.withValues(alpha: 0.45) : c.hairline,
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
                value ?? label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: hasValue ? c.inkPrimary : c.inkSecondary,
                      fontWeight:
                          hasValue ? FontWeight.w600 : FontWeight.w400,
                    ),
              ),
            ),
            if (onClear != null)
              IconButton(
                tooltip: 'Clear date',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
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
}
