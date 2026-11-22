import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/local_event_store.dart';
import '../../domain/models.dart';
import '../../domain/team_profile.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/glass_surface.dart';
import '../scoring/scoring_screen.dart';

Future<TeamProfile?> showCreateTeamSheet(BuildContext context) {
  return showModalBottomSheet<TeamProfile>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _CreateTeamSheet(),
  );
}

class _CreateTeamSheet extends StatefulWidget {
  const _CreateTeamSheet();

  @override
  State<_CreateTeamSheet> createState() => _CreateTeamSheetState();
}

class _CreateTeamSheetState extends State<_CreateTeamSheet> {
  static const _uuid = Uuid();
  final _nameCtrl = TextEditingController();
  final _playerCtrl = TextEditingController();
  final List<String> _players = [];
  bool _isMyTeam = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _playerCtrl.dispose();
    super.dispose();
  }

  void _addPlayer() {
    final p = _playerCtrl.text.trim();
    if (p.isEmpty) return;
    if (!_players.any((e) => e.toLowerCase() == p.toLowerCase())) {
      setState(() {
        _players.add(p);
        _playerCtrl.clear();
      });
    } else {
      _playerCtrl.clear();
    }
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a team name first.')),
      );
      return;
    }
    Navigator.pop(
      context,
      TeamProfile(
        id: _uuid.v4(),
        name: name,
        isMyTeam: _isMyTeam,
        players: List<String>.from(_players),
        createdAt: DateTime.now(),
      ),
    );
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
              Text('New Team',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 14),
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Team name',
                  hintText: 'e.g. Model Town CC',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('My team'),
                subtitle: const Text('Pin to the top of your Teams list'),
                activeThumbColor: c.pitchGreen,
                value: _isMyTeam,
                onChanged: (v) => setState(() => _isMyTeam = v),
              ),
              const SizedBox(height: 8),
              Text('Squad (${_players.length})',
                  style: Theme.of(context).textTheme.labelMedium),
              if (_players.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in _players)
                      InputChip(
                        label: Text(p),
                        onDeleted: () => setState(() => _players.remove(p)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _playerCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: '+ Add player name',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onSubmitted: (_) => _addPlayer(),
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
                    onPressed: _addPlayer,
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.pitchGreen,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _save,
                child: const Text('Save Team'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TeamsTabView extends StatefulWidget {
  const TeamsTabView({
    super.key,
    required this.savedTeams,
    required this.knownRosters,
    required this.matches,
    required this.onChanged,
  });

  final List<TeamProfile> savedTeams;
  final Map<String, List<String>> knownRosters;
  final List<DerivedMatchState> matches;
  final VoidCallback onChanged;

  @override
  State<TeamsTabView> createState() => _TeamsTabViewState();
}

class _TeamsTabViewState extends State<TeamsTabView> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  ({int played, int won, int lost}) _recordFor(String teamName) {
    var p = 0, w = 0, l = 0;
    final lower = teamName.toLowerCase();
    for (final m in widget.matches) {
      if (m.status != MatchStatus.completed) continue;
      final isA = m.config.teamA.toLowerCase() == lower;
      final isB = m.config.teamB.toLowerCase() == lower;
      if (!isA && !isB) continue;
      p++;
      final summary = (m.resultSummary ?? '').toLowerCase();
      if (summary.startsWith(lower)) {
        w++;
      } else if (!summary.contains('tied')) {
        l++;
      }
    }
    return (played: p, won: w, lost: l);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final savedByName = {
      for (final t in widget.savedTeams) t.name.toLowerCase(): t,
    };
    final allNames = <String>{
      ...widget.savedTeams.map((t) => t.name),
      ...widget.knownRosters.keys,
    }.toList()
      ..sort((a, b) {
        final aMy = savedByName[a.toLowerCase()]?.isMyTeam ?? false;
        final bMy = savedByName[b.toLowerCase()]?.isMyTeam ?? false;
        if (aMy != bMy) return aMy ? -1 : 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = allNames
        .where((name) => q.isEmpty || name.toLowerCase().contains(q))
        .toList();

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              hintText: 'Search all teams...',
              filled: true,
              fillColor: c.surfaceGlass,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: c.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: c.hairline),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            GlassSurface(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No teams found. Tap "+ Team" to create your squad.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            for (final name in filtered) ...[
              Builder(
                builder: (context) {
                  final saved = savedByName[name.toLowerCase()];
                  final roster = widget.knownRosters[name] ??
                      saved?.players ??
                      const <String>[];
                  final rec = _recordFor(name);
                  final isMy = saved?.isMyTeam ?? false;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TeamDetailScreen(
                              teamName: name,
                              savedProfile: saved,
                              initialRoster: roster,
                              matches: widget.matches,
                            ),
                          ),
                        );
                        widget.onChanged();
                      },
                      child: GlassSurface(
                        borderColor: isMy ? c.pitchGreen : c.hairline,
                        borderWidth: isMy ? 1.2 : 1.0,
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                      ),
                                      if (isMy) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: c.pitchGreenSoft,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'MY TEAM',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(
                                                  fontSize: 10,
                                                  color: c.pitchGreen,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${roster.length} player${roster.length == 1 ? '' : 's'} · ${rec.played}M  ${rec.won}W  ${rec.lost}L',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: c.inkSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
        ]),
      ),
    );
  }
}

class TeamDetailScreen extends StatefulWidget {
  const TeamDetailScreen({
    super.key,
    required this.teamName,
    required this.savedProfile,
    required this.initialRoster,
    required this.matches,
  });

  final String teamName;
  final TeamProfile? savedProfile;
  final List<String> initialRoster;
  final List<DerivedMatchState> matches;

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  static const _uuid = Uuid();
  late TeamProfile _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.savedProfile ??
        TeamProfile(
          id: _uuid.v4(),
          name: widget.teamName,
          players: List<String>.from(widget.initialRoster),
          createdAt: DateTime.now(),
        );
  }

  Future<void> _persist(TeamProfile updated) async {
    setState(() => _profile = updated);
    await LocalEventStore.instance.saveTeam(updated);
    LocalEventStore.instance.syncTeamToSupabase(updated.id);
  }

  Future<void> _addPlayer() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add player to ${_profile.name}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Player name'),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                Navigator.pop(ctx, ctrl.text.trim());
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (_profile.players.any((p) => p.toLowerCase() == name.toLowerCase())) {
      return;
    }
    await _persist(_profile.copyWith(players: [..._profile.players, name]));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final lower = _profile.name.toLowerCase();
    final teamMatches = widget.matches
        .where((m) =>
            m.config.teamA.toLowerCase() == lower ||
            m.config.teamB.toLowerCase() == lower)
        .toList();

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        title: Text(_profile.name),
        actions: [
          IconButton(
            tooltip: _profile.isMyTeam ? 'Unpin My Team' : 'Mark as My Team',
            icon: Icon(
              _profile.isMyTeam ? Icons.star_rounded : Icons.star_outline_rounded,
              color: _profile.isMyTeam ? c.pitchGreen : c.inkSecondary,
            ),
            onPressed: () =>
                _persist(_profile.copyWith(isMyTeam: !_profile.isMyTeam)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        children: [
          // Squad card (editable only for My Team; read-only for opposition teams)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  'Squad (${_profile.players.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (_profile.isMyTeam)
                TextButton.icon(
                  onPressed: _addPlayer,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
                  label: const Text('Add player'),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 8),
                  child: Text(
                    'Read-only',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
            ],
          ),
          GlassSurface(
            padding: const EdgeInsets.all(14),
            child: _profile.players.isEmpty
                ? Text(
                    'No players recorded yet.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in _profile.players)
                        _profile.isMyTeam
                            ? InputChip(
                                label: Text(p),
                                onDeleted: () {
                                  final next =
                                      List<String>.from(_profile.players)
                                        ..remove(p);
                                  _persist(_profile.copyWith(players: next));
                                },
                              )
                            : Chip(
                                label: Text(p),
                                visualDensity: VisualDensity.compact,
                              ),
                    ],
                  ),
          ),

          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Match history (${teamMatches.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (teamMatches.isEmpty)
            GlassSurface(
              padding: const EdgeInsets.all(18),
              child: Text(
                'No matches recorded for ${_profile.name} yet.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            for (final m in teamMatches) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ScoringScreen(matchId: m.config.id),
                    ),
                  ),
                  child: GlassSurface(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                m.config.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Text(
                              m.config.formatLabel,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          m.resultSummary ??
                              '${m.activeInnings.battingTeam} ${m.activeInnings.scoreText} (${m.activeInnings.oversText} ov)',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: c.pitchGreen),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }
}
