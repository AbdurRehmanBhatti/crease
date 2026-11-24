import 'package:flutter/material.dart';

import '../../../domain/tournament_engine.dart';
import '../../../theme/crease_theme.dart';
import '../../../widgets/crease_ui.dart';
import '../../../widgets/glass_surface.dart';

class TournamentTeamsTab extends StatefulWidget {
  const TournamentTeamsTab({
    super.key,
    required this.tournament,
    required this.canEditTeams,
    required this.playedTeams,
    required this.onAddTeam,
    required this.onRemoveTeam,
    required this.onAddPlayer,
    required this.onRenamePlayer,
    required this.onRemovePlayer,
    this.readOnly = false,
  });

  final Tournament tournament;
  final bool canEditTeams;
  final Set<String> playedTeams;
  final VoidCallback onAddTeam;
  final ValueChanged<String> onRemoveTeam;
  final ValueChanged<String> onAddPlayer;
  final void Function(String teamName, String playerName) onRenamePlayer;
  final void Function(String teamName, String playerName) onRemovePlayer;
  final bool readOnly;

  @override
  State<TournamentTeamsTab> createState() => _TournamentTeamsTabState();
}

class _TournamentTeamsTabState extends State<TournamentTeamsTab> {
  final Set<String> _expandedTeams = {};

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final teams = widget.tournament.teams;

    if (teams.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: GlassSurface(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.pitchGreenSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.groups_2_outlined,
                    size: 22,
                    color: c.pitchGreen,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.readOnly
                      ? 'No teams added yet'
                      : 'Add participating teams',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  widget.readOnly
                      ? 'The organizer has not added teams to this tournament yet.'
                      : 'Select at least 2 teams to generate fixtures and the Points Table.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (!widget.readOnly) ...[
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: widget.onAddTeam,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add teams'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottomInset),
      itemCount: teams.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          final statusText = widget.readOnly
              ? '${teams.length} participating ${teams.length == 1 ? 'team' : 'teams'}'
              : teams.length < 2
                  ? '1 team · Add at least 1 more to generate fixtures'
                  : widget.canEditTeams
                      ? '${teams.length} teams'
                      : '${teams.length} teams · Locked once matches begin';
          return Row(
            children: [
              Expanded(
                child: Text(
                  statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (!widget.readOnly && widget.canEditTeams)
                TextButton.icon(
                  onPressed: widget.onAddTeam,
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('Add teams'),
                ),
            ],
          );
        }

        final team = teams[index - 1];
        final roster = widget.tournament.teamRosters[team] ?? const [];
        final isExpanded = _expandedTeams.contains(team);
        final canRemoveThisTeam = !widget.readOnly &&
            widget.canEditTeams &&
            teams.length > 2 &&
            !widget.playedTeams.contains(team.toLowerCase());

        return GlassSurface(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(CreaseRadius.card),
                onTap: () => setState(() {
                  if (isExpanded) {
                    _expandedTeams.remove(team);
                  } else {
                    _expandedTeams.add(team);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                  child: Row(
                    children: [
                      CreaseTeamBadge(name: team, size: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              team,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              roster.isEmpty
                                  ? 'No squad yet'
                                  : '${roster.length} ${roster.length == 1 ? 'player' : 'players'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (!widget.readOnly)
                        TextButton.icon(
                          onPressed: () => widget.onAddPlayer(team),
                          icon: const Icon(
                            Icons.person_add_alt_1_rounded,
                            size: 16,
                          ),
                          label: const Text('Add'),
                        ),
                      Icon(
                        isExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: c.inkSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              if (isExpanded) ...[
                Divider(height: 1, color: c.hairlineSubtle),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (roster.isEmpty)
                        Text(
                          'Auto-filled as players bat or bowl during matches.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: c.inkSecondary),
                        )
                      else ...[
                        Text(
                          widget.readOnly
                              ? 'Tournament squad'
                              : 'Tournament squad · Tap to rename, × to remove',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final p in roster)
                              widget.readOnly
                                  ? Chip(
                                      label: Text(p),
                                      visualDensity: VisualDensity.compact,
                                    )
                                  : InputChip(
                                      label: Text(p),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () =>
                                          widget.onRenamePlayer(team, p),
                                      onDeleted: () =>
                                          widget.onRemovePlayer(team, p),
                                    ),
                          ],
                        ),
                      ],
                      if (canRemoveThisTeam) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: c.wicketRed,
                            ),
                            onPressed: () => widget.onRemoveTeam(team),
                            icon: const Icon(
                              Icons.remove_circle_outline_rounded,
                              size: 16,
                            ),
                            label: const Text('Remove from tournament'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
