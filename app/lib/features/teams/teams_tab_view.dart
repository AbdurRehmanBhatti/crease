import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../data/local_event_store.dart';
import '../../domain/models.dart';
import '../../domain/stats_engine.dart';
import '../../domain/team_profile.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/crease_ui.dart';
import '../../widgets/glass_surface.dart';
import '../scoring/scoring_screen.dart';
import 'team_invite_sheets.dart';

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
  bool _isMyTeam = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
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
        players: const [],
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
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(CreaseRadius.sheet)),
        fillColor: c.surfaceSheet,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CreaseSheetHeader(
              title: 'New team',
              subtitle: 'You can add players or share an invite code next.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: 'Team name',
                hintText: 'e.g. Model Town CC',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('My team'),
              subtitle: const Text('Pin to the top of your teams list'),
              activeThumbColor: c.pitchGreen,
              value: _isMyTeam,
              onChanged: (v) => setState(() => _isMyTeam = v),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _save,
              child: const Text('Create team'),
            ),
          ],
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

    final hasMyTeam = widget.savedTeams.any((t) => t.isMyTeam);

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          if (!hasMyTeam) ...[
            GlassSurface(
              borderColor: c.pitchGreen.withValues(alpha: 0.3),
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set up your squad',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manage captain and keeper roles, or join an existing team with a 6-digit code.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            final team = await showCreateTeamSheet(context);
                            if (team == null) return;
                            await LocalEventStore.instance.saveTeam(team);
                            LocalEventStore.instance.syncTeamToSupabase(team.id);
                            if (!context.mounted) return;
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => TeamDetailScreen(
                                  teamName: team.name,
                                  savedProfile: team,
                                  initialRoster: team.players,
                                  matches: widget.matches,
                                ),
                              ),
                            );
                            widget.onChanged();
                          },
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Create team'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final joined = await showJoinTeamSheet(context);
                            if (joined) widget.onChanged();
                          },
                          icon: const Icon(Icons.group_add_outlined, size: 18),
                          label: const Text('Join code'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (allNames.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      hintText: 'Search teams',
                      fillColor: c.surfaceGlass,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.pitchGreen,
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: () async {
                    final joined = await showJoinTeamSheet(context);
                    if (joined) widget.onChanged();
                  },
                  icon: const Icon(Icons.group_add_outlined, size: 18),
                  label: const Text('Join'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (filtered.isEmpty)
              GlassSurface(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No teams matching "${_searchCtrl.text.trim()}".',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              for (final name in filtered)
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
                      child: CreasePressable(
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
                          borderColor: isMy
                              ? c.pitchGreen.withValues(alpha: 0.4)
                              : c.hairline,
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              CreaseTeamBadge(
                                name: name,
                                size: 42,
                                highlighted: isMy,
                              ),
                              const SizedBox(width: 12),
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
                                              'My team',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelMedium
                                                  ?.copyWith(
                                                    fontSize: 10.5,
                                                    color: c.pitchGreen,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${roster.length} player${roster.length == 1 ? '' : 's'} · ${rec.played}M  ${rec.won}W  ${rec.lost}L',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
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
  Set<String> _claimedPlayers = const {};

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
    _loadClaimed();
  }

  Future<void> _loadClaimed() async {
    final claimed =
        await LocalEventStore.instance.fetchClaimedPlayersForTeam(_profile.id);
    if (!mounted) return;
    setState(() => _claimedPlayers = claimed);
  }

  Future<void> _confirmUnlinkPlayer(String playerName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Unlink $playerName?'),
        content: const Text(
          'This removes the linked account from this player spot so the right teammate can claim it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await LocalEventStore.instance.unlinkTeamPlayer(_profile.id, playerName);
      await _loadClaimed();
    } catch (_) {}
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

  int _designationOrder(String? d) => switch (d) {
        'C' => 0,
        'VC' => 1,
        'WK' => 2,
        _ => 3,
      };

  Future<void> _openPlayerProfileSheet(
    String playerName,
    PlayerCareerStats? stats,
  ) async {
    final initialMeta = _profile.metaFor(playerName);
    final isClaimed = _claimedPlayers.contains(playerName.toLowerCase());
    var role = initialMeta.role;
    var designation = initialMeta.designation;

    await showModalBottomSheet<void>(
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
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: c.hairline,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        CreaseTeamBadge(
                          name: playerName,
                          size: 48,
                          highlighted: true,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      playerName,
                                      style: Theme.of(ctx).textTheme.titleLarge,
                                    ),
                                  ),
                                  if (isClaimed) ...[
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.verified_rounded,
                                      size: 18,
                                      color: c.pitchGreen,
                                    ),
                                  ],
                                ],
                              ),
                              Text(
                                '${_profile.name}${role.isNotEmpty ? ' · $role' : ''}',
                                style: Theme.of(ctx).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        if (stats != null)
                          IconButton(
                            tooltip: 'Share player card',
                            icon: const Icon(Icons.share_rounded, size: 20),
                            onPressed: () {
                              Share.share(
                                '$playerName (${_profile.name})\n'
                                'Matches: ${stats.matchesPlayed} · Runs: ${stats.runs} (SR ${stats.strikeRate.toStringAsFixed(1)}) · '
                                'Wickets: ${stats.wickets} (Econ ${stats.economy.toStringAsFixed(1)}) · '
                                'MVP: ${stats.mvpPoints} pts\nTracked with Crease',
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (stats != null) ...[
                      Row(
                        children: [
                          _MiniStatBox(
                            label: 'Matches',
                            value: '${stats.matchesPlayed}',
                          ),
                          const SizedBox(width: 8),
                          _MiniStatBox(label: 'Runs', value: '${stats.runs}'),
                          const SizedBox(width: 8),
                          _MiniStatBox(
                            label: 'Wickets',
                            value: '${stats.wickets}',
                          ),
                          const SizedBox(width: 8),
                          _MiniStatBox(
                            label: 'MVP',
                            value: '${stats.mvpPoints}',
                            highlight: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      Text(
                        'No match stats recorded yet for $playerName.',
                        style: Theme.of(ctx).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_profile.isMyTeam && _profile.isOwner) ...[
                      Text(
                        'Team designation',
                        style: Theme.of(ctx).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final d in <String?>[
                            null,
                            ...SquadPlayerMeta.designations,
                          ])
                            ChoiceChip(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              labelPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              label: Text(
                                d == null
                                    ? 'None'
                                    : d == 'C'
                                        ? 'Captain'
                                        : d == 'VC'
                                            ? 'Vice-Capt'
                                            : 'Keeper',
                              ),
                              selected: designation == d,
                              selectedColor: c.pitchGreen,
                              labelStyle: TextStyle(
                                fontSize: 12.5,
                                color: designation == d
                                    ? Colors.white
                                    : c.inkPrimary,
                                fontWeight: designation == d
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                              side: BorderSide(
                                color: designation == d
                                    ? c.pitchGreen
                                    : c.hairline,
                              ),
                              onSelected: (_) =>
                                  setModalState(() => designation = d),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Playing role',
                        style: Theme.of(ctx).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final r in SquadPlayerMeta.roles)
                            ChoiceChip(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              labelPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              label: Text(r == 'Wicket-keeper' ? 'Keeper' : r),
                              selected: role == r,
                              selectedColor: c.pitchGreen,
                              labelStyle: TextStyle(
                                fontSize: 12.5,
                                color: role == r ? Colors.white : c.inkPrimary,
                                fontWeight: role == r
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                              side: BorderSide(
                                color: role == r ? c.pitchGreen : c.hairline,
                              ),
                              onSelected: (_) => setModalState(
                                () => role = role == r ? '' : r,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: () async {
                          final updated = _profile.withUpdatedPlayerMeta(
                            playerName,
                            SquadPlayerMeta(
                              role: role,
                              designation: designation,
                            ),
                          );
                          await _persist(updated);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: const Text('Save player role'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (isClaimed)
                            Expanded(
                              child: TextButton(
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  await _confirmUnlinkPlayer(playerName);
                                },
                                child: const Text('Unlink account'),
                              ),
                            ),
                          Expanded(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: c.wicketRed,
                              ),
                              onPressed: () async {
                                if (isClaimed) {
                                  try {
                                    await LocalEventStore.instance
                                        .unlinkTeamPlayer(
                                      _profile.id,
                                      playerName,
                                    );
                                  } catch (_) {}
                                }
                                final nextPlayers =
                                    List<String>.from(_profile.players)
                                      ..remove(playerName);
                                await _persist(
                                  _profile.copyWith(players: nextPlayers),
                                );
                                await _loadClaimed();
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                              child: const Text('Remove player'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
    final statsList = StatsEngine.derive(teamMatches, teamName: _profile.name);
    final statsByLower = {
      for (final s in statsList) s.name.toLowerCase(): s,
    };

    final sortedPlayers = List<String>.from(_profile.players)
      ..sort((a, b) {
        final da = _designationOrder(_profile.metaFor(a).designation);
        final db = _designationOrder(_profile.metaFor(b).designation);
        if (da != db) return da.compareTo(db);
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        title: Text(_profile.name),
        actions: [
          if (_profile.isMyTeam && _profile.isOwner)
            IconButton(
              tooltip: 'Invite teammates',
              icon: const Icon(Icons.group_add_outlined),
              onPressed: () => showInviteTeammatesSheet(context, _profile),
            ),
          IconButton(
            tooltip: _profile.isMyTeam ? 'Unpin My Team' : 'Mark as My Team',
            icon: Icon(
              _profile.isMyTeam
                  ? Icons.push_pin_rounded
                  : Icons.push_pin_outlined,
              size: 20,
              color: _profile.isMyTeam ? c.pitchGreen : c.inkSecondary,
            ),
            onPressed: () =>
                _persist(_profile.copyWith(isMyTeam: !_profile.isMyTeam)),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Squad (${_profile.players.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (_profile.isMyTeam && _profile.isOwner)
                TextButton.icon(
                  onPressed: _addPlayer,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
                  label: const Text('Add player'),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _profile.isMyTeam ? 'Squad member' : 'Read-only',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
            ],
          ),
          GlassSurface(
            padding: sortedPlayers.isEmpty
                ? const EdgeInsets.all(18)
                : const EdgeInsets.symmetric(vertical: 4),
            child: sortedPlayers.isEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Build your squad',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _profile.isMyTeam && _profile.isOwner
                            ? 'Add players manually or invite teammates with a 6-digit code so they can join and link their stats.'
                            : 'No players recorded for this team yet.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (_profile.isMyTeam && _profile.isOwner) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _addPlayer,
                                icon: const Icon(
                                  Icons.person_add_alt_1_rounded,
                                  size: 17,
                                ),
                                label: const Text('Add player'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    showInviteTeammatesSheet(context, _profile),
                                icon: const Icon(
                                  Icons.group_add_outlined,
                                  size: 17,
                                ),
                                label: const Text('Invite'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  )
                : Column(
                    children: [
                      for (var i = 0; i < sortedPlayers.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            indent: 64,
                            color: c.hairlineSubtle,
                          ),
                        Builder(
                          builder: (context) {
                            final p = sortedPlayers[i];
                            final meta = _profile.metaFor(p);
                            final pStats = statsByLower[p.toLowerCase()];
                            final isClaimed =
                                _claimedPlayers.contains(p.toLowerCase());
                            final subParts = <String>[
                              if (meta.role.isNotEmpty) meta.role,
                              if (pStats != null)
                                '${pStats.runs}r · ${pStats.wickets}w',
                              if (isClaimed) 'Linked',
                              if (meta.role.isEmpty &&
                                  pStats == null &&
                                  !isClaimed)
                                (_profile.isMyTeam && _profile.isOwner)
                                    ? 'Tap to assign role'
                                    : 'Squad player',
                            ];
                            return InkWell(
                              onTap: () => _openPlayerProfileSheet(p, pStats),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 11,
                                ),
                                child: Row(
                                  children: [
                                    CreaseTeamBadge(
                                      name: p,
                                      size: 38,
                                      highlighted: meta.designation != null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  p,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyLarge
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                              ),
                                              if (meta.designation != null) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 1.5,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: c.pitchGreenSoft,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                  ),
                                                  child: Text(
                                                    meta.designation!,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelMedium
                                                        ?.copyWith(
                                                          fontSize: 10.5,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: c.pitchGreen,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                              if (isClaimed) ...[
                                                const SizedBox(width: 5),
                                                Icon(
                                                  Icons.verified_rounded,
                                                  size: 15,
                                                  color: c.pitchGreen,
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            subParts.join(' · '),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: c.inkSecondary,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 18,
                                      color: c.inkSecondary,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
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
            for (final m in teamMatches)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: CreasePressable(
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
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: c.pillMutedBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                m.config.formatLabel,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      fontSize: 10.5,
                                      color: c.inkPrimary,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          m.resultSummary ??
                              '${m.activeInnings.battingTeam} ${m.activeInnings.scoreText} (${m.activeInnings.oversText} ov)',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: c.pitchGreen,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _MiniStatBox extends StatelessWidget {
  const _MiniStatBox({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: c.surfaceKey,
          borderRadius: BorderRadius.circular(CreaseRadius.control),
          border: Border.all(color: c.hairlineSubtle),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: creaseNumeralStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: highlight ? c.pitchGreen : c.inkPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: c.inkSecondary,
                    fontSize: 11,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
