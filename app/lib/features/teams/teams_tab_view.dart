import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../data/local_event_store.dart';
import '../../domain/models.dart';
import '../../domain/stats_engine.dart';
import '../../domain/team_profile.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/crease_ui.dart';
import '../../widgets/glass_surface.dart';
import '../auth/auth_sheet.dart';
import '../profile/player_career_poster.dart';
import '../profile/player_profile_screen.dart';
import '../scorecard/scorecard_screen.dart';
import '../scoring/scoring_screen.dart';
import 'team_invite_sheets.dart';

Future<TeamProfile?> showCreateTeamSheet(
  BuildContext context, {
  List<String> existingTeamNames = const [],
}) {
  return showModalBottomSheet<TeamProfile>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _CreateTeamSheet(existingTeamNames: existingTeamNames),
  );
}

class _CreateTeamSheet extends StatefulWidget {
  const _CreateTeamSheet({this.existingTeamNames = const []});

  final List<String> existingTeamNames;

  @override
  State<_CreateTeamSheet> createState() => _CreateTeamSheetState();
}

class _CreateTeamSheetState extends State<_CreateTeamSheet> {
  static const _uuid = Uuid();
  final _nameCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  bool _isMyTeam = true;
  String? _nameError;
  late Map<String, String> _existingByLower;

  @override
  void initState() {
    super.initState();
    _existingByLower = {
      for (final n in widget.existingTeamNames) n.trim().toLowerCase(): n,
    };
    if (_existingByLower.isEmpty) {
      _loadExistingNames();
    }
  }

  Future<void> _loadExistingNames() async {
    final teams = await LocalEventStore.instance.listTeams();
    if (!mounted) return;
    setState(() {
      _existingByLower = {
        for (final t in teams) t.name.trim().toLowerCase(): t.name,
      };
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Enter a team name.');
      return;
    }
    final existing = _existingByLower[name.toLowerCase()];
    if (existing != null) {
      setState(
        () => _nameError =
            'You already have "$existing" — open it from Teams to edit or pin it.',
      );
      return;
    }
    final loc = _locationCtrl.text.trim();
    Navigator.pop(
      context,
      TeamProfile(
        id: _uuid.v4(),
        name: name,
        location: loc.isEmpty ? null : loc,
        isMyTeam: _isMyTeam,
        squad: const [],
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
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: 'Team name',
                hintText: 'e.g. Model Town CC',
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationCtrl,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: 'City or area (optional)',
                hintText: 'e.g. Lahore, Model Town',
                prefixIcon: Icon(Icons.location_on_outlined, size: 19),
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

  ({int played, int won, int lost}) _recordFor(
    String teamName, {
    String? teamId,
  }) {
    var p = 0, w = 0, l = 0;
    for (final m in widget.matches) {
      if (m.status != MatchStatus.completed) continue;
      final side = m.config.sideForTeam(
        teamId: teamId,
        teamName: teamName,
      );
      if (side == null) continue;
      p++;
      if (m.winnerSide == side) {
        w++;
      } else if (m.winnerSide != null) {
        l++;
      }
    }
    return (played: p, won: w, lost: l);
  }

  Widget _buildTeamCard(
    BuildContext context, {
    required String name,
    required List<String> roster,
    required TeamProfile? saved,
    String? location,
    String? badgeLabel,
    String? customSubtitle,
    bool readOnlyPublic = false,
    String? publicTeamId,
  }) {
    final c = context.crease;
    final rec = _recordFor(name, teamId: publicTeamId ?? saved?.id);
    final isMy = !readOnlyPublic && (saved?.isMyTeam ?? false);
    final loc = (location ?? saved?.location)?.trim();
    final hasLoc = loc != null && loc.isNotEmpty;
    final defaultSubtitle =
        '${hasLoc ? '$loc · ' : ''}${roster.length} player${roster.length == 1 ? '' : 's'} · ${rec.played}M  ${rec.won}W  ${rec.lost}L';
    final subtitle = customSubtitle ?? defaultSubtitle;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CreasePressable(
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TeamDetailScreen(
                teamName: name,
                savedProfile: readOnlyPublic
                    ? TeamProfile(
                        id: publicTeamId ?? '',
                        name: name,
                        location: hasLoc ? loc : null,
                        isMyTeam: false,
                        isOwner: false,
                        squad: const [],
                        createdAt: DateTime.now(),
                      )
                    : saved,
                initialRoster: roster,
                matches: widget.matches,
                readOnlyPublic: readOnlyPublic,
              ),
            ),
          );
          if (!readOnlyPublic) widget.onChanged();
        },
        child: GlassSurface(
          borderColor:
              isMy ? c.pitchGreen.withValues(alpha: 0.4) : c.hairline,
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
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (badgeLabel != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isMy ? c.pitchGreenSoft : c.pillMutedBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badgeLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    fontSize: 10.5,
                                    color: isMy ? c.pitchGreen : c.inkSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
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
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;

    final rawQuery = _searchCtrl.text.trim();
    final q = rawQuery.toLowerCase();

    final myTeams = widget.savedTeams
        .where(
          (t) =>
              q.isEmpty ||
              t.name.toLowerCase().contains(q) ||
              (t.location?.toLowerCase().contains(q) ?? false),
        )
        .toList()
      ..sort((a, b) {
        if (a.isMyTeam != b.isMyTeam) return a.isMyTeam ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    final hasSavedTeams = widget.savedTeams.isNotEmpty;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          if (!hasSavedTeams) ...[
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
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 46),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          onPressed: () async {
                            final team = await showCreateTeamSheet(
                              context,
                              existingTeamNames: widget.savedTeams
                                  .map((t) => t.name)
                                  .toList(),
                            );
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
                          label: const Text(
                            'Create team',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 46),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          onPressed: () async {
                            final joined = await showJoinTeamSheet(context);
                            if (joined) widget.onChanged();
                          },
                          icon: const Icon(Icons.group_add_outlined, size: 18),
                          label: const Text(
                            'Join code',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (hasSavedTeams) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      hintText: 'Search your teams…',
                      fillColor: c.surfaceGlass,
                      isDense: true,
                      suffixIcon: rawQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear filter',
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                            ),
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
            const SizedBox(height: 12),
          ],
          if (myTeams.isEmpty && rawQuery.isNotEmpty)
            GlassSurface(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No teams in your list match "$rawQuery".\nUse the top search bar to find public clubs on Crease.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            for (final team in myTeams)
              _buildTeamCard(
                context,
                name: team.name,
                roster: team.players,
                saved: team,
                badgeLabel: team.isMyTeam
                    ? 'My team'
                    : (!team.isOwner ? 'Joined' : null),
              ),
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
    this.readOnlyPublic = false,
  });

  final String teamName;
  final TeamProfile? savedProfile;
  final List<String> initialRoster;
  final List<DerivedMatchState> matches;
  final bool readOnlyPublic;

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

enum _WinLossScope { all, batFirst, bowlFirst }

enum _TeamStatsBoard { mvp, batting, bowling, boundaries }

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  static const _uuid = Uuid();
  late TeamProfile _profile;
  late bool _isSaved;
  Set<String> _claimedPlayers = const {};
  Map<String, String> _memberAvatars = const {};
  _WinLossScope _winLossScope = _WinLossScope.all;
  _TeamStatsBoard _statsBoard = _TeamStatsBoard.mvp;

  bool get _canEdit => !widget.readOnlyPublic && _isSaved && _profile.isOwner;

  @override
  void initState() {
    super.initState();
    _isSaved = widget.savedProfile != null;
    _profile = widget.savedProfile ??
        TeamProfile(
          id: _uuid.v4(),
          name: widget.teamName,
          squad: const [],
          createdAt: DateTime.now(),
        );
    _loadClaimed();
    if (widget.readOnlyPublic && _profile.id.isNotEmpty) {
      _hydratePublicProfile();
    }
  }

  Future<void> _hydratePublicProfile() async {
    final full =
        await LocalEventStore.instance.fetchPublicTeamProfile(_profile.id);
    if (!mounted || full == null) return;
    setState(() {
      _profile = full.copyWith(isMyTeam: false, isOwner: false);
      _syncClaimedFromSquad();
    });
  }

  void _syncClaimedFromSquad() {
    _claimedPlayers = {
      for (final p in _profile.squad)
        if (p.isLinked) p.displayName.toLowerCase(),
    };
    _memberAvatars = {
      for (final p in _profile.squad)
        if (p.avatarUrl != null && p.avatarUrl!.isNotEmpty)
          p.displayName.toLowerCase(): p.avatarUrl!,
    };
  }

  Future<void> _loadClaimed() async {
    if (_isSaved && !widget.readOnlyPublic && _profile.id.isNotEmpty) {
      final latest = await LocalEventStore.instance.getTeam(_profile.id);
      if (mounted && latest != null) {
        setState(() {
          _profile = latest;
          _syncClaimedFromSquad();
        });
        return;
      }
    }
    if (!mounted) return;
    setState(_syncClaimedFromSquad);
  }

  Future<void> _confirmUnlinkPlayer(
    String playerName, {
    bool isSelf = false,
  }) async {
    final target = _profile.playerByName(playerName);
    if (target == null) return;
    var isUnlinking = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final c = ctx.crease;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return PopScope(
              canPop: !isUnlinking,
              child: AlertDialog(
                title: Text(
                  isSelf
                      ? 'Unlink your account from $playerName?'
                      : 'Unlink $playerName?',
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSelf
                          ? 'This releases your account from $playerName so you can claim the right player spot.'
                          : 'This removes the linked account from this player spot so the right teammate can claim it.',
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: TextStyle(fontSize: 12.5, color: c.wicketRed),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: isUnlinking ? null : () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      disabledBackgroundColor:
                          isUnlinking ? c.pitchGreen : null,
                      disabledForegroundColor:
                          isUnlinking ? c.onPitchGreen : null,
                    ),
                    onPressed: isUnlinking
                        ? null
                        : () async {
                            setDialogState(() {
                              isUnlinking = true;
                              errorText = null;
                            });
                            try {
                              await LocalEventStore.instance
                                  .unlinkTeamPlayer(target.id);
                              await _loadClaimed();
                              if (ctx.mounted) Navigator.pop(ctx);
                            } catch (_) {
                              if (ctx.mounted) {
                                setDialogState(() {
                                  isUnlinking = false;
                                  errorText =
                                      'Could not unlink right now. Check connection and retry.';
                                });
                              }
                            }
                          },
                    child: isUnlinking
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: c.onPitchGreen,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('Unlinking…'),
                            ],
                          )
                        : const Text('Unlink'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _persist(TeamProfile updated) async {
    setState(() {
      _profile = updated;
      _isSaved = true;
    });
    await LocalEventStore.instance.saveTeam(updated);
    LocalEventStore.instance.syncTeamToSupabase(updated.id);
  }

  Future<void> _editTeam() async {
    final otherTeams = await LocalEventStore.instance.listTeams();
    final otherNamesLower = otherTeams
        .where((t) => t.id != _profile.id)
        .map((t) => t.name.trim().toLowerCase())
        .toSet();
    if (!mounted) return;

    final nameCtrl = TextEditingController(text: _profile.name);
    final locCtrl = TextEditingController(text: _profile.location ?? '');
    String? errorText;
    final result = await showDialog<({String name, String? location})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void submit() {
            final trimmed = nameCtrl.text.trim();
            if (trimmed.isEmpty) {
              setDialogState(() => errorText = 'Enter a team name.');
              return;
            }
            if (otherNamesLower.contains(trimmed.toLowerCase())) {
              setDialogState(
                () => errorText = 'You already have a team named "$trimmed".',
              );
              return;
            }
            final loc = locCtrl.text.trim();
            Navigator.pop(
              ctx,
              (name: trimmed, location: loc.isEmpty ? null : loc),
            );
          }

          return AlertDialog(
            title: const Text('Edit team'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Team name',
                    errorText: errorText,
                  ),
                  onChanged: (_) {
                    if (errorText != null) {
                      setDialogState(() => errorText = null);
                    }
                  },
                  onSubmitted: (_) => submit(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: locCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'City or area (optional)',
                    hintText: 'e.g. Lahore, Model Town',
                    prefixIcon: Icon(Icons.location_on_outlined, size: 19),
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ],
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
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      nameCtrl.dispose();
      locCtrl.dispose();
    });
    if (result == null) return;
    await _persist(
      _profile.copyWith(
        name: result.name,
        location: result.location,
        clearLocation: result.location == null,
      ),
    );
  }

  Future<void> _confirmDeleteTeam() async {
    final c = context.crease;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${_profile.name}?'),
        content: const Text(
          'This removes the saved team, squad roles, and invite code. Past matches, scorecards, and player career stats will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.wicketRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deletedName = _profile.name;
    await LocalEventStore.instance.deleteTeam(_profile.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted "$deletedName".')),
    );
    Navigator.of(context).pop();
  }

  Future<void> _confirmLeaveTeam() async {
    final c = context.crease;
    var isLeaving = false;
    String? errorText;

    final left = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return PopScope(
              canPop: !isLeaving,
              child: AlertDialog(
                title: Text('Leave ${_profile.name}?'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This removes the team from your device and unlinks your spot. You can rejoin later with an invite code.',
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: TextStyle(fontSize: 12.5, color: c.wicketRed),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed:
                        isLeaving ? null : () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.wicketRed,
                      disabledBackgroundColor: isLeaving ? c.wicketRed : null,
                      disabledForegroundColor:
                          isLeaving ? Colors.white : null,
                    ),
                    onPressed: isLeaving
                        ? null
                        : () async {
                            setDialogState(() {
                              isLeaving = true;
                              errorText = null;
                            });
                            try {
                              await LocalEventStore.instance
                                  .leaveTeam(_profile.id);
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } catch (_) {
                              if (ctx.mounted) {
                                setDialogState(() {
                                  isLeaving = false;
                                  errorText =
                                      'Could not leave right now. Check connection and retry.';
                                });
                              }
                            }
                          },
                    child: isLeaving
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('Leaving…'),
                            ],
                          )
                        : const Text('Leave'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (left != true || !mounted) return;
    final leftName = _profile.name;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Left "$leftName".')),
    );
    Navigator.of(context).pop();
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
    Future<void>.delayed(const Duration(milliseconds: 500), ctrl.dispose);
    if (name == null || name.isEmpty) return;
    if (_profile.players.any((p) => p.toLowerCase() == name.toLowerCase())) {
      return;
    }
    if (!_isSaved) {
      await _persist(_profile);
    }
    await LocalEventStore.instance.addPlayerToClub(
      teamId: _profile.id,
      displayName: name,
    );
    await _loadClaimed();
  }

  int _designationOrder(String? d) => switch (d) {
        'C' => 0,
        'VC' => 1,
        'WK' => 2,
        _ => 3,
      };

  Future<String?> _renamePlayer(
    String oldName, {
    bool hasStats = false,
  }) async {
    final ctrl = TextEditingController(text: oldName);
    String? errorText;
    final renamed = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void submit() {
            final clean = ctrl.text.trim();
            if (clean.isEmpty) {
              setDialogState(() => errorText = 'Enter a player name.');
              return;
            }
            if (clean.toLowerCase() == oldName.toLowerCase() &&
                clean == oldName) {
              Navigator.pop(ctx);
              return;
            }
            final duplicate = _profile.players.any(
              (p) =>
                  p.toLowerCase() == clean.toLowerCase() &&
                  p.toLowerCase() != oldName.toLowerCase(),
            );
            if (duplicate) {
              setDialogState(
                () => errorText = '"$clean" is already in this squad.',
              );
              return;
            }
            Navigator.pop(ctx, clean);
          }

          return AlertDialog(
            title: const Text('Rename player'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
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
                if (hasStats) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Updates across your squad, past scorecards, and career stats automatically.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
              ],
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
    if (renamed == null || renamed.isEmpty || renamed == oldName) return null;

    final target = _profile.playerByName(oldName);
    if (target == null) return null;
    await LocalEventStore.instance.renamePlayer(target.id, renamed);
    await _loadClaimed();
    return renamed;
  }

  Future<void> _openPlayerProfileSheet(
    String playerName,
    PlayerCareerStats? stats,
  ) async {
    var currentName = playerName;
    final initialMeta = _profile.metaFor(currentName);
    final isClaimed = _claimedPlayers.contains(currentName.toLowerCase());
    final initialTarget = _profile.playerByName(currentName);
    final signedInUid = LocalEventStore.instance.signedInUserId;
    final isSelfClaimed = initialTarget != null &&
        signedInUid != null &&
        initialTarget.userId == signedInUid;
    final initialRole = initialMeta.role.trim();
    final initialDesignation =
        (initialMeta.designation != null &&
                initialMeta.designation!.trim().isNotEmpty)
            ? initialMeta.designation!.trim()
            : null;
    var role = initialRole;
    var designation = initialDesignation;
    var isSaving = false;
    String? saveError;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final normalizedDes =
                (designation != null && designation!.trim().isNotEmpty)
                    ? designation!.trim()
                    : null;
            final hasChanges =
                role != initialRole || normalizedDes != initialDesignation;

            return PopScope(
              canPop: !isSaving,
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
                        CreasePlayerAvatar(
                          name: currentName,
                          size: 48,
                          highlighted: true,
                          avatarUrl: _memberAvatars[currentName.toLowerCase()],
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
                                      currentName,
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
                                  ] else if (_canEdit) ...[
                                    const SizedBox(width: 2),
                                    IconButton(
                                      tooltip: 'Rename player',
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      icon: Icon(
                                        Icons.edit_outlined,
                                        size: 17,
                                        color: c.inkSecondary,
                                      ),
                                      onPressed: () async {
                                        final updated = await _renamePlayer(
                                          currentName,
                                          hasStats: stats != null,
                                        );
                                        if (updated != null && ctx.mounted) {
                                          setModalState(
                                            () => currentName = updated,
                                          );
                                        }
                                      },
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
                              PlayerCareerPoster.sharePlayerCard(
                                playerName: currentName,
                                stats: stats,
                                role: role,
                                teamName: _profile.name,
                              );
                            },
                          ),
                        IconButton(
                          tooltip: 'Full profile',
                          icon: const Icon(Icons.open_in_new_rounded, size: 19),
                          onPressed: () {
                            Navigator.pop(ctx);
                            final player = _profile.playerByName(currentName);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PlayerProfileScreen(
                                  playerName: currentName,
                                  playerId: player?.id,
                                  userId: player?.userId,
                                  role: role,
                                  teams: [_profile.name],
                                  isVerified: isClaimed,
                                  matches: widget.matches,
                                ),
                              ),
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
                        'No match stats recorded yet for $currentName.',
                        style: Theme.of(ctx).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_canEdit) ...[
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
                              onSelected: isSaving
                                  ? null
                                  : (_) => setModalState(() {
                                      designation = d;
                                      saveError = null;
                                    }),
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
                              onSelected: isSaving
                                  ? null
                                  : (_) => setModalState(() {
                                      role = role == r ? '' : r;
                                      saveError = null;
                                    }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (saveError != null) ...[
                        Text(
                          saveError!,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: c.wicketRed,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      FilledButton(
                        style: FilledButton.styleFrom(
                          disabledBackgroundColor:
                              isSaving ? c.pitchGreen : null,
                          disabledForegroundColor:
                              isSaving ? c.onPitchGreen : null,
                        ),
                        onPressed: (!hasChanges || isSaving)
                            ? null
                            : () async {
                                setModalState(() {
                                  isSaving = true;
                                  saveError = null;
                                });
                                try {
                                  final target =
                                      _profile.playerByName(currentName);
                                  if (target != null) {
                                    await LocalEventStore.instance
                                        .updatePlayerRole(
                                      target.id,
                                      role: role,
                                      designation: normalizedDes,
                                    );
                                    await _loadClaimed();
                                  }
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } catch (_) {
                                  if (ctx.mounted) {
                                    setModalState(() {
                                      isSaving = false;
                                      saveError =
                                          'Could not save player role. Please try again.';
                                    });
                                  }
                                }
                              },
                        child: isSaving
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
                                  const Text('Saving…'),
                                ],
                              )
                            : const Text('Save player role'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (isClaimed)
                            Expanded(
                              child: TextButton(
                                onPressed: isSaving
                                    ? null
                                    : () async {
                                        Navigator.pop(ctx);
                                        await _confirmUnlinkPlayer(currentName);
                                      },
                                child: const Text('Unlink account'),
                              ),
                            ),
                          Expanded(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: c.wicketRed,
                              ),
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      final target =
                                          _profile.playerByName(currentName);
                                      if (target == null) return;
                                      setModalState(() {
                                        isSaving = true;
                                        saveError = null;
                                      });
                                      try {
                                        if (isClaimed) {
                                          await LocalEventStore.instance
                                              .unlinkTeamPlayer(target.id);
                                        }
                                        await LocalEventStore.instance
                                            .archivePlayer(target.id);
                                        await _loadClaimed();
                                        if (ctx.mounted) Navigator.pop(ctx);
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context)
                                          ..hideCurrentSnackBar()
                                          ..showSnackBar(
                                            SnackBar(
                                              duration:
                                                  const Duration(seconds: 4),
                                              content: Text(
                                                'Removed $currentName from ${_profile.name}',
                                              ),
                                              action: SnackBarAction(
                                                label: 'Undo',
                                                onPressed: () async {
                                                  await LocalEventStore.instance
                                                      .savePlayer(
                                                    target.copyWith(
                                                      archived: false,
                                                    ),
                                                  );
                                                  await _loadClaimed();
                                                },
                                              ),
                                            ),
                                          );
                                      } catch (_) {
                                        if (ctx.mounted) {
                                          setModalState(() {
                                            isSaving = false;
                                            saveError =
                                                'Could not remove player. Check connection and try again.';
                                          });
                                        }
                                      }
                                    },
                              child: const Text('Remove player'),
                            ),
                          ),
                        ],
                      ),
                    ] else if (!widget.readOnlyPublic &&
                        _isSaved &&
                        isSelfClaimed) ...[
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: c.wicketRed,
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _confirmUnlinkPlayer(currentName, isSelf: true);
                        },
                        child: const Text('Unlink my account'),
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
  }

  String? _matchOutcomeForTeam(DerivedMatchState m) {
    if (m.status != MatchStatus.completed) return null;
    final side = m.config.sideForTeam(
      teamId: _profile.id.isNotEmpty ? _profile.id : null,
      teamName: _profile.name,
    );
    if (side == null) return null;
    if (m.config.isAbandoned) return 'NR';
    if (m.winnerSide == side) return 'W';
    if (m.winnerSide != null) return 'L';
    final summary = (m.resultSummary ?? '').toLowerCase();
    if (summary.contains('tied') || summary.contains('draw')) return 'T';
    if (summary.contains('abandoned') || summary.contains('no result')) {
      return 'NR';
    }
    return 'L';
  }

  ({int played, int won, int lost, int tied}) _winLossStats(
    List<DerivedMatchState> teamMatches,
  ) {
    var played = 0, won = 0, lost = 0, tied = 0;
    for (final m in teamMatches) {
      if (m.status != MatchStatus.completed) continue;
      final side = m.config.sideForTeam(
        teamId: _profile.id.isNotEmpty ? _profile.id : null,
        teamName: _profile.name,
      );
      if (side == null) continue;
      final battedFirst = m.config.battingFirstSide == side;
      if (_winLossScope == _WinLossScope.batFirst && !battedFirst) continue;
      if (_winLossScope == _WinLossScope.bowlFirst && battedFirst) continue;
      final outcome = _matchOutcomeForTeam(m);
      if (outcome == null || outcome == 'NR') continue;
      played++;
      if (outcome == 'W') {
        won++;
      } else if (outcome == 'T') {
        tied++;
      } else {
        lost++;
      }
    }
    return (played: played, won: won, lost: lost, tied: tied);
  }

  void _openPlayerProfile(String playerName, {String? playerId}) {
    final player = (playerId != null && playerId.isNotEmpty)
        ? (_profile.playerById(playerId) ?? _profile.playerByName(playerName))
        : _profile.playerByName(playerName);
    final meta = player?.meta ?? _profile.metaFor(playerName);
    final isClaimed =
        player?.isLinked ?? _claimedPlayers.contains(playerName.toLowerCase());
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerProfileScreen(
          playerName: player?.displayName ?? playerName,
          playerId: player?.id ?? playerId,
          userId: player?.userId,
          role: meta.role,
          teams: [_profile.name],
          isVerified: isClaimed,
          avatarUrl: player?.avatarUrl ?? _memberAvatars[playerName.toLowerCase()],
          matches: widget.matches,
        ),
      ),
    );
  }

  void _showMvpFormulaSheet(BuildContext context) {
    final c = context.crease;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GlassSurface(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CreaseRadius.sheet),
        ),
        fillColor: c.surfaceSheet,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CreaseSheetHeader(
              title: 'How MVP points work',
              subtitle: 'Derived directly from ball-by-ball match events.',
            ),
            const SizedBox(height: 12),
            for (final item in const [
              ('1 run scored', '+1 pt'),
              ('Four (4)', '+1 bonus'),
              ('Six (6)', '+2 bonus'),
              ('Half-century (50+)', '+10 bonus'),
              ('Century (100+)', '+25 bonus'),
              ('Wicket taken', '+20 pts'),
              ('Maiden over', '+10 pts'),
              ('Catch / Stumping / Run-out', '+8 pts'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(item.$1, style: Theme.of(ctx).textTheme.bodyMedium),
                    Text(
                      item.$2,
                      style: creaseNumeralStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: c.pitchGreen,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final teamMatches = widget.matches
        .where(
          (m) => m.config.involvesTeam(
            teamId: _profile.id.isNotEmpty ? _profile.id : null,
            teamName: _profile.name,
          ),
        )
        .toList()
      ..sort((a, b) => b.config.createdAt.compareTo(a.config.createdAt));

    final statsList = LocalEventStore.instance.deriveStats(
      teamMatches,
      teamId: _profile.id.isNotEmpty ? _profile.id : null,
      teamName: _profile.name,
    );
    final cleanStatsList = statsList
        .where((s) => !LocalEventStore.isPlaceholderPlayerName(s.name))
        .toList();
    final statsByPlayerId = {
      for (final s in statsList)
        if (s.playerId.isNotEmpty) s.playerId: s,
    };
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

    final recentForm = teamMatches
        .map(_matchOutcomeForTeam)
        .whereType<String>()
        .take(5)
        .toList();
    final wl = _winLossStats(teamMatches);
    final topScorer = StatsEngine.byRuns(cleanStatsList).firstOrNull;
    final topBowler = StatsEngine.byWickets(cleanStatsList)
        .where((p) => p.wickets > 0)
        .firstOrNull;

    final rankedBoard = switch (_statsBoard) {
      _TeamStatsBoard.mvp => StatsEngine.byMvp(cleanStatsList),
      _TeamStatsBoard.batting => StatsEngine.byRuns(cleanStatsList),
      _TeamStatsBoard.bowling => StatsEngine.byWickets(cleanStatsList),
      _TeamStatsBoard.boundaries => StatsEngine.bySixes(cleanStatsList),
    };

    String primaryMetric(PlayerCareerStats p) => switch (_statsBoard) {
          _TeamStatsBoard.mvp => '${p.mvpPoints} pts',
          _TeamStatsBoard.batting => '${p.runs}',
          _TeamStatsBoard.bowling => '${p.wickets} wkts',
          _TeamStatsBoard.boundaries => '${p.sixes}×6 · ${p.fours}×4',
        };

    String secondaryMetric(PlayerCareerStats p) => switch (_statsBoard) {
          _TeamStatsBoard.mvp =>
            '${p.runs}r · ${p.wickets}w · ${p.fieldingDismissals}f',
          _TeamStatsBoard.batting =>
            'SR ${p.strikeRate.toStringAsFixed(0)} · HS ${p.highestScoreText} · ${p.inningsBatted} inn',
          _TeamStatsBoard.bowling =>
            '${p.oversBowledText} ov · Econ ${p.economy.toStringAsFixed(1)} · Best ${p.bestBowlingText}',
          _TeamStatsBoard.boundaries =>
            '${p.runs} runs (${p.ballsFaced}b) · SR ${p.strikeRate.toStringAsFixed(0)}',
        };

    final statusPillLabel = widget.readOnlyPublic
        ? 'Public club'
        : _profile.isMyTeam
            ? 'My Team'
            : _profile.isOwner
                ? 'Saved team'
                : 'Squad member';

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: c.ground,
        appBar: AppBar(
          title: (_profile.location != null && _profile.location!.isNotEmpty)
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _profile.location!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                )
              : Text(_profile.name),
          actions: [
            if (_canEdit)
              IconButton(
                tooltip: 'Invite teammates',
                icon: const Icon(Icons.group_add_outlined),
                onPressed: () => showInviteTeammatesSheet(context, _profile),
              ),
            if (!widget.readOnlyPublic)
              CreaseMenuButton<String>(
                sheetTitle: _profile.name,
                tooltip: 'Team options',
                items: [
                  if (_profile.isOwner)
                    CreaseMenuItem(
                      value: 'toggle_pin',
                      label: _profile.isMyTeam
                          ? 'Unpin from My Team'
                          : 'Set as My Team',
                      subtitle: _profile.isMyTeam
                          ? 'Stop pre-filling in Quick Match'
                          : 'Pin to top & pre-fill in Quick Match',
                      icon: _profile.isMyTeam
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                    ),
                  if (_canEdit) ...[
                    const CreaseMenuItem(
                      value: 'edit',
                      label: 'Edit team',
                      subtitle: 'Update name or city',
                      icon: Icons.edit_outlined,
                    ),
                    const CreaseMenuItem(
                      value: 'delete',
                      label: 'Delete team',
                      subtitle: 'Keeps past matches and player stats',
                      icon: Icons.delete_outline_rounded,
                      isDestructive: true,
                    ),
                  ],
                  if (_isSaved && !_profile.isOwner)
                    const CreaseMenuItem(
                      value: 'leave',
                      label: 'Leave team',
                      subtitle: 'Removes this team from your device',
                      icon: Icons.logout_rounded,
                      isDestructive: true,
                    ),
                ],
                onSelected: (action) {
                  if (action == 'toggle_pin') {
                    _persist(_profile.copyWith(isMyTeam: !_profile.isMyTeam));
                  } else if (action == 'edit') {
                    _editTeam();
                  } else if (action == 'delete') {
                    _confirmDeleteTeam();
                  } else if (action == 'leave') {
                    _confirmLeaveTeam();
                  }
                },
              ),
          ],
          bottom: TabBar(
            indicatorColor: c.pitchGreen,
            labelColor: c.inkPrimary,
            unselectedLabelColor: c.inkSecondary,
            dividerColor: c.hairlineSubtle,
            labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
            unselectedLabelStyle:
                Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Players'),
              Tab(text: 'Matches'),
              Tab(text: 'Stats'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // TAB 1: OVERVIEW
            ListView(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 32 + bottomInset),
              children: [
                if (!widget.readOnlyPublic &&
                    !_profile.isMyTeam &&
                    _profile.isOwner) ...[
                  GlassSurface(
                    borderColor: c.pitchGreen.withValues(alpha: 0.3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isSaved
                                    ? 'Make this your main team?'
                                    : 'Play for this team?',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Keeps it pinned at the top & ready for quick matches.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: c.inkSecondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          onPressed: () =>
                              _persist(_profile.copyWith(isMyTeam: true)),
                          child: const Text('Pin team'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Club Hero Card
                GlassSurface(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CreaseTeamBadge(
                            name: _profile.name,
                            size: 52,
                            highlighted: _profile.isMyTeam,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _profile.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _profile.isMyTeam
                                            ? c.pitchGreenSoft
                                            : c.pillMutedBg,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        statusPillLabel,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: _profile.isMyTeam
                                                  ? c.pitchGreen
                                                  : c.inkSecondary,
                                            ),
                                      ),
                                    ),
                                    if (_profile.profileCode != null &&
                                        _profile.profileCode!.isNotEmpty)
                                      CreasePressable(
                                        onTap: () {
                                          final code = _profile.profileCode!;
                                          Clipboard.setData(
                                            ClipboardData(text: code),
                                          );
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Team ID $code copied · share with opponents at the toss',
                                              ),
                                            ),
                                          );
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: c.surfaceKey,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border:
                                                Border.all(color: c.hairline),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'ID: ${_profile.profileCode!}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelMedium
                                                    ?.copyWith(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: c.inkPrimary,
                                                    ),
                                              ),
                                              const SizedBox(width: 4),
                                              Icon(
                                                Icons.copy_rounded,
                                                size: 11,
                                                color: c.inkSecondary,
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    else if (!widget.readOnlyPublic &&
                                        _profile.isOwner &&
                                        !isSignedInAccount())
                                      CreasePressable(
                                        onTap: () async {
                                          final ok =
                                              await requireSignedInAccount(
                                            context,
                                            title: 'Sign in for a Team ID',
                                            subtitle:
                                                'Get a shareable Team ID so opponents can link matches to ${_profile.name}.',
                                          );
                                          if (!ok || !mounted) return;
                                          await LocalEventStore.instance
                                              .syncTeamToSupabase(_profile.id);
                                          final refreshed = (await LocalEventStore
                                                  .instance
                                                  .listTeams())
                                              .where((t) => t.id == _profile.id)
                                              .firstOrNull;
                                          if (refreshed != null && mounted) {
                                            setState(() => _profile = refreshed);
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: c.surfaceKey,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border:
                                                Border.all(color: c.hairline),
                                          ),
                                          child: Text(
                                            'Sign in for Team ID',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: c.pitchGreen,
                                                ),
                                          ),
                                        ),
                                      ),
                                    Text(
                                      '${_profile.players.length} player${_profile.players.length == 1 ? '' : 's'} · ${teamMatches.length} match${teamMatches.length == 1 ? '' : 'es'}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: c.inkSecondary),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Divider(height: 1, color: c.hairlineSubtle),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            'Recent form',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const Spacer(),
                          if (recentForm.isEmpty)
                            Text(
                              'No completed matches yet',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: c.inkSecondary),
                            )
                          else
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final code in recentForm)
                                  Container(
                                    width: 26,
                                    height: 26,
                                    margin: const EdgeInsets.only(left: 6),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: code == 'W'
                                          ? c.pitchGreenSoft
                                          : code == 'L'
                                              ? c.wicketRedSoft
                                              : c.pillMutedBg,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      code,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                            color: code == 'W'
                                                ? c.pitchGreen
                                                : code == 'L'
                                                    ? c.wicketRed
                                                    : c.inkSecondary,
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Win / Loss Ratio Card
                Text(
                  'Win / Loss ratio',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                GlassSurface(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CreaseSegmentedControl<_WinLossScope>(
                        selected: _winLossScope,
                        onChanged: (v) => setState(() => _winLossScope = v),
                        items: const [
                          (
                            value: _WinLossScope.all,
                            label: 'All',
                            icon: null,
                          ),
                          (
                            value: _WinLossScope.batFirst,
                            label: 'Bat 1st',
                            icon: null,
                          ),
                          (
                            value: _WinLossScope.bowlFirst,
                            label: 'Bowl 1st',
                            icon: null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Builder(
                        builder: (context) {
                          final wonPct =
                              wl.played > 0 ? (wl.won * 100 / wl.played) : 0.0;
                          final lostPct =
                              wl.played > 0 ? (wl.lost * 100 / wl.played) : 0.0;
                          final wonFlex = wl.played > 0
                              ? (wonPct * 10).round().clamp(0, 1000)
                              : 0;
                          final lostFlex = wl.played > 0
                              ? (lostPct * 10).round().clamp(0, 1000)
                              : 0;
                          final tiedFlex = wl.played > 0
                              ? (1000 - wonFlex - lostFlex).clamp(0, 1000)
                              : 1000;
                          return Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Won ${wonPct.toStringAsFixed(0)}%',
                                    style: creaseNumeralStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: wl.won > 0
                                          ? c.pitchGreen
                                          : c.inkSecondary,
                                    ),
                                  ),
                                  Text(
                                    'Lost ${lostPct.toStringAsFixed(0)}%',
                                    style: creaseNumeralStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: wl.lost > 0
                                          ? c.wicketRed
                                          : c.inkSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  height: 9,
                                  child: Row(
                                    children: [
                                      if (wonFlex > 0)
                                        Expanded(
                                          flex: wonFlex,
                                          child: Container(color: c.pitchGreen),
                                        ),
                                      if (tiedFlex > 0)
                                        Expanded(
                                          flex: tiedFlex,
                                          child: Container(
                                            color: c.pillMutedBg,
                                          ),
                                        ),
                                      if (lostFlex > 0)
                                        Expanded(
                                          flex: lostFlex,
                                          child: Container(
                                            color: c.wicketRed
                                                .withValues(alpha: 0.72),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _MiniStatBox(
                                    label: 'Matches',
                                    value: '${wl.played}',
                                  ),
                                  const SizedBox(width: 8),
                                  _MiniStatBox(
                                    label: 'Won',
                                    value: '${wl.won}',
                                    highlight: wl.won > 0,
                                  ),
                                  const SizedBox(width: 8),
                                  _MiniStatBox(
                                    label: 'Lost',
                                    value: '${wl.lost}',
                                  ),
                                  if (wl.tied > 0) ...[
                                    const SizedBox(width: 8),
                                    _MiniStatBox(
                                      label: 'Tied',
                                      value: '${wl.tied}',
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Top Performers Card
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Top performers',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (topScorer != null || topBowler != null)
                      Builder(
                        builder: (tabCtx) => TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () =>
                              DefaultTabController.of(tabCtx).animateTo(3),
                          child: const Text('See all →'),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (topScorer == null && topBowler == null)
                  GlassSurface(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      'Score a match with ${_profile.name} to see top batters and bowlers.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else
                  GlassSurface(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (final entry in [
                          if (topScorer != null)
                            (
                              label: 'Top batter',
                              player: topScorer,
                              metric: '${topScorer.runs} runs',
                              sub:
                                  'SR ${topScorer.strikeRate.toStringAsFixed(0)} · HS ${topScorer.highestScoreText}',
                            ),
                          if (topBowler != null)
                            (
                              label: 'Top bowler',
                              player: topBowler,
                              metric: '${topBowler.wickets} wkts',
                              sub:
                                  'Econ ${topBowler.economy.toStringAsFixed(1)} · Best ${topBowler.bestBowlingText}',
                            ),
                        ].indexed) ...[
                          if (entry.$1 > 0)
                            Divider(
                              height: 1,
                              indent: 64,
                              color: c.hairlineSubtle,
                            ),
                          InkWell(
                            onTap: () =>
                                _openPlayerProfile(entry.$2.player.name),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  CreasePlayerAvatar(
                                    name: entry.$2.player.name,
                                    size: 38,
                                    highlighted: entry.$1 == 0,
                                    avatarUrl: _memberAvatars[
                                        entry.$2.player.name.toLowerCase()],
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.$2.label.toUpperCase(),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.6,
                                                color: c.pitchGreen,
                                              ),
                                        ),
                                        Text(
                                          entry.$2.player.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        Text(
                                          entry.$2.sub,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: c.inkSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    entry.$2.metric,
                                    style: creaseNumeralStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: entry.$1 == 0
                                          ? c.pitchGreen
                                          : c.inkPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: c.inkSecondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),

            // TAB 2: PLAYERS
            ListView(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 32 + bottomInset),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Players (${_profile.players.length})',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (_canEdit && sortedPlayers.isNotEmpty)
                      TextButton.icon(
                        onPressed: _addPlayer,
                        icon: const Icon(
                          Icons.person_add_alt_1_rounded,
                          size: 17,
                        ),
                        label: const Text('Add player'),
                      )
                    else if (!_canEdit)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          widget.readOnlyPublic
                              ? 'Public club'
                              : _isSaved
                                  ? 'Squad member'
                                  : 'Read-only',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                  ],
                ),
                if (_canEdit && sortedPlayers.isEmpty)
                  const SizedBox(height: 8),
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
                              _canEdit
                                  ? 'Add players manually or invite teammates with a 6-digit code so they can join and link their stats.'
                                  : 'No players recorded for this team yet.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (_canEdit) ...[
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
                                      onPressed: () => showInviteTeammatesSheet(
                                        context,
                                        _profile,
                                      ),
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
                                  final player = _profile.playerByName(p);
                                  final meta =
                                      player?.meta ?? _profile.metaFor(p);
                                  final pStats = (player != null
                                          ? statsByPlayerId[player.id]
                                          : null) ??
                                      statsByLower[p.toLowerCase()];
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
                                      _canEdit
                                          ? 'Tap to assign role'
                                          : 'Squad player',
                                  ];
                                  return InkWell(
                                    onTap: () {
                                      if (!_canEdit) {
                                        _openPlayerProfile(p);
                                      } else {
                                        _openPlayerProfileSheet(p, pStats);
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 11,
                                      ),
                                      child: Row(
                                        children: [
                                          CreasePlayerAvatar(
                                            name: p,
                                            size: 38,
                                            highlighted:
                                                meta.designation != null,
                                            avatarUrl:
                                                _memberAvatars[p.toLowerCase()],
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
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodyLarge
                                                            ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                      ),
                                                    ),
                                                    if (meta.designation !=
                                                        null) ...[
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 6,
                                                          vertical: 1.5,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color:
                                                              c.pitchGreenSoft,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(6),
                                                        ),
                                                        child: Text(
                                                          meta.designation!,
                                                          style: Theme.of(
                                                                  context)
                                                              .textTheme
                                                              .labelMedium
                                                              ?.copyWith(
                                                                fontSize: 10.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: c
                                                                    .pitchGreen,
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
              ],
            ),

            // TAB 3: MATCHES
            ListView(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 32 + bottomInset),
              children: [
                if (teamMatches.isEmpty)
                  GlassSurface(
                    padding: const EdgeInsets.all(22),
                    child: Text(
                      'No matches recorded for ${_profile.name} yet.',
                      textAlign: TextAlign.center,
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
                            builder: (_) =>
                                (m.status == MatchStatus.completed ||
                                        widget.readOnlyPublic)
                                    ? ScorecardScreen(matchId: m.config.id)
                                    : ScoringScreen(matchId: m.config.id),
                          ),
                        ),
                        child: GlassSurface(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      m.config.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
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

            // TAB 4: STATS (TEAM LEADERBOARDS)
            ListView(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 32 + bottomInset),
              children: [
                CreaseSegmentedControl<_TeamStatsBoard>(
                  selected: _statsBoard,
                  onChanged: (v) => setState(() => _statsBoard = v),
                  items: const [
                    (value: _TeamStatsBoard.mvp, label: 'MVP', icon: null),
                    (
                      value: _TeamStatsBoard.batting,
                      label: 'Batting',
                      icon: null,
                    ),
                    (
                      value: _TeamStatsBoard.bowling,
                      label: 'Bowling',
                      icon: null,
                    ),
                    (
                      value: _TeamStatsBoard.boundaries,
                      label: '4s & 6s',
                      icon: null,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        switch (_statsBoard) {
                          _TeamStatsBoard.mvp =>
                            'All-round impact across batting, bowling & fielding',
                          _TeamStatsBoard.batting =>
                            'Top run-scorers for ${_profile.name}',
                          _TeamStatsBoard.bowling =>
                            'Top wicket-takers for ${_profile.name}',
                          _TeamStatsBoard.boundaries =>
                            'Most sixes & fours for ${_profile.name}',
                        },
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: c.inkSecondary),
                      ),
                    ),
                    if (_statsBoard == _TeamStatsBoard.mvp)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _showMvpFormulaSheet(context),
                        icon: const Icon(Icons.info_outline_rounded, size: 15),
                        label: const Text('Formula'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (rankedBoard.isEmpty)
                  GlassSurface(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No stats recorded for ${_profile.name} yet.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else ...[
                  // #1 Leader Hero Card
                  CreasePressable(
                    onTap: () => _openPlayerProfile(rankedBoard.first.name),
                    child: GlassSurface(
                      borderColor: c.pitchGreen.withValues(alpha: 0.45),
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: c.pitchGreen,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '1',
                              style: creaseNumeralStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: c.onPitchGreen,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rankedBoard.first.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  secondaryMetric(rankedBoard.first),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: c.inkSecondary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            primaryMetric(rankedBoard.first),
                            style: creaseNumeralStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: c.pitchGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (rankedBoard.length > 1) ...[
                    const SizedBox(height: 10),
                    GlassSurface(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (var i = 1; i < rankedBoard.length; i++) ...[
                            if (i > 1)
                              Divider(
                                height: 1,
                                indent: 48,
                                color: c.hairlineSubtle,
                              ),
                            InkWell(
                              onTap: () =>
                                  _openPlayerProfile(rankedBoard[i].name),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 11,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      child: Text(
                                        '${i + 1}',
                                        textAlign: TextAlign.center,
                                        style: creaseNumeralStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: c.inkSecondary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            rankedBoard[i].name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            secondaryMetric(rankedBoard[i]),
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
                                    const SizedBox(width: 8),
                                    Text(
                                      primaryMetric(rankedBoard[i]),
                                      style: creaseNumeralStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: c.inkPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ],
        ),
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
