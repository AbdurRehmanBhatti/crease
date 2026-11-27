import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../config/security_guards.dart';
import '../../data/local_event_store.dart';
import '../../domain/models.dart';
import '../../domain/roster_sync_planner.dart';
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


part 'sheets/create_team_sheet.dart';
part 'team_detail_screen.dart';
part 'sheets/team_player_sheets.dart';

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
                teamId: saved?.id ?? publicTeamId,
                avatarUrl: saved?.logoUrl,
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

