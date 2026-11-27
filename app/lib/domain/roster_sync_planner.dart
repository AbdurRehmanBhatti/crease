import 'package:flutter/foundation.dart';

import 'models.dart';
import 'team_profile.dart';

enum RosterMergeActionKind {
  /// Insert a new remote player or replace an already-synced local player.
  insertOrReplace,

  /// Local player has unsynced edits (`synced == false`), so only merge remote
  /// claim metadata (`user_id`, `claimed_at`, `avatar_url`) without clobbering
  /// local role, designation, or display-name changes.
  patchClaimOnly,
}

@immutable
class RosterMergeAction {
  const RosterMergeAction({
    required this.kind,
    required this.remotePlayer,
  });

  final RosterMergeActionKind kind;
  final PlayerProfile remotePlayer;
}

/// Pure, deterministic planning helpers for syncing `public.players` rows
/// between Supabase (REST pulls & Realtime payloads) and local SQLite.
class RosterSyncPlanner {
  RosterSyncPlanner._();

  /// Builds the column map for routine owner `UPDATE` syncs on `public.players`.
  ///
  /// Intentionally omits `user_id`, `claimed_at`, and `avatar_url` whenever the
  /// local row is unclaimed so a stale owner cache can never accidentally wipe
  /// a teammate's remote account link.
  static Map<String, Object?> buildOwnerUpdatePayload(PlayerProfile player) {
    final uid = player.userId?.trim();
    final avatar = player.avatarUrl?.trim();
    return <String, Object?>{
      'display_name': player.displayName,
      'role': player.role,
      'designation': player.archived ? null : player.designation,
      'member_role': player.memberRole,
      'archived': player.archived,
      'updated_at': player.updatedAt.millisecondsSinceEpoch,
      if (uid != null && uid.isNotEmpty) ...{
        'user_id': uid,
        if (player.claimedAt != null)
          'claimed_at': player.claimedAt!.millisecondsSinceEpoch,
        if (avatar != null && avatar.isNotEmpty) 'avatar_url': avatar,
      },
    };
  }

  /// Computes the minimal set of SQLite mutations needed to merge [remoteRows]
  /// into [localById] for teams present in [validTeamIds].
  static List<RosterMergeAction> planMerge({
    required Set<String> validTeamIds,
    required Map<String, PlayerProfile> localById,
    required List<Map> remoteRows,
  }) {
    if (validTeamIds.isEmpty || remoteRows.isEmpty) return const [];

    final actions = <RosterMergeAction>[];
    for (final raw in remoteRows) {
      final map = Map<String, Object?>.from(raw);
      final rawId = (map['id'] as String?)?.trim() ?? '';
      if (rawId.isEmpty) continue;
      final remote = PlayerProfile.fromMap(map).copyWith(synced: true);
      if (!validTeamIds.contains(remote.teamId)) continue;

      final local = localById[remote.id];
      if (local == null) {
        actions.add(
          RosterMergeAction(
            kind: RosterMergeActionKind.insertOrReplace,
            remotePlayer: remote,
          ),
        );
        continue;
      }

      if (!local.synced) {
        if (hasClaimDiff(local, remote)) {
          actions.add(
            RosterMergeAction(
              kind: RosterMergeActionKind.patchClaimOnly,
              remotePlayer: remote,
            ),
          );
        }
        continue;
      }

      if (hasProfileDiff(local, remote)) {
        actions.add(
          RosterMergeAction(
            kind: RosterMergeActionKind.insertOrReplace,
            remotePlayer: remote,
          ),
        );
      }
    }
    return actions;
  }

  static bool hasClaimDiff(PlayerProfile a, PlayerProfile b) =>
      a.userId != b.userId ||
      a.claimedAt?.millisecondsSinceEpoch !=
          b.claimedAt?.millisecondsSinceEpoch ||
      a.avatarUrl != b.avatarUrl;

  static bool hasProfileDiff(PlayerProfile a, PlayerProfile b) =>
      a.teamId != b.teamId ||
      a.ownerId != b.ownerId ||
      hasClaimDiff(a, b) ||
      a.displayName != b.displayName ||
      a.role != b.role ||
      a.designation != b.designation ||
      a.memberRole != b.memberRole ||
      a.archived != b.archived;
}

/// Cooldown helper for app-resume syncs so brief system dialogs or rapid
/// app-switching don't trigger redundant Supabase queries.
class ResumeSyncThrottle {
  ResumeSyncThrottle({this.cooldown = const Duration(seconds: 5)});

  final Duration cooldown;
  DateTime? _lastSyncAt;

  DateTime? get lastSyncAt => _lastSyncAt;

  bool shouldSync({DateTime? now}) {
    final last = _lastSyncAt;
    if (last == null) return true;
    final current = now ?? DateTime.now();
    return current.difference(last) >= cooldown;
  }

  void markSynced({DateTime? now}) {
    _lastSyncAt = now ?? DateTime.now();
  }
}

/// Per-team selectable player options for linking a user's account to their
/// squad spot(s) across one or more teams.
@immutable
class TeamLinkOption {
  const TeamLinkOption({
    required this.team,
    required this.eligiblePlayers,
    this.linkedPlayerId,
  });

  final TeamProfile team;
  final List<PlayerProfile> eligiblePlayers;
  final String? linkedPlayerId;

  PlayerProfile? playerById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final p in eligiblePlayers) {
      if (p.id == id) return p;
    }
    return null;
  }

  PlayerProfile? get linkedPlayer => playerById(linkedPlayerId);
}

extension RosterSyncTeamLinking on RosterSyncPlanner {
  /// Builds ordered per-team linking options across all [teams] (not just
  /// `isMyTeam`), filtering out archived, placeholder, and other-user-claimed
  /// players while preserving exact player UUIDs so identical names across
  /// different teams never collide.
  static List<TeamLinkOption> buildTeamLinkOptions({
    required List<TeamProfile> teams,
    required String? currentUserId,
    String? fallbackLinkedPlayerName,
  }) {
    final cleanFallback = fallbackLinkedPlayerName?.trim().toLowerCase();
    final options = <TeamLinkOption>[];

    for (final team in teams) {
      final eligible = <PlayerProfile>[];
      String? linkedId;

      for (final p in team.squad) {
        if (p.archived) continue;
        final name = p.displayName.trim();
        if (name.isEmpty || isPlaceholderPlayerName(name)) continue;

        final claimedByOther = p.userId != null &&
            p.userId!.isNotEmpty &&
            p.userId != currentUserId;
        if (claimedByOther) continue;

        eligible.add(p);
        if (currentUserId != null &&
            currentUserId.isNotEmpty &&
            p.userId == currentUserId) {
          linkedId ??= p.id;
        }
      }

      if (eligible.isEmpty) continue;
      eligible.sort(
        (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
      );

      // Offline / guest fallback before a userId exists on the player row.
      if (linkedId == null &&
          (currentUserId == null || currentUserId.isEmpty) &&
          cleanFallback != null &&
          cleanFallback.isNotEmpty &&
          (team.isMyTeam || teams.length == 1)) {
        for (final p in eligible) {
          if (p.displayName.trim().toLowerCase() == cleanFallback) {
            linkedId = p.id;
            break;
          }
        }
      }

      options.add(
        TeamLinkOption(
          team: team,
          eligiblePlayers: eligible,
          linkedPlayerId: linkedId,
        ),
      );
    }

    options.sort((a, b) {
      if (a.team.isMyTeam != b.team.isMyTeam) {
        return a.team.isMyTeam ? -1 : 1;
      }
      final aLinked = a.linkedPlayerId != null;
      final bLinked = b.linkedPlayerId != null;
      if (aLinked != bLinked) return aLinked ? -1 : 1;
      return a.team.name.toLowerCase().compareTo(b.team.name.toLowerCase());
    });

    return options;
  }

  /// Resolves the primary display name to persist in `UserProfile.linkedPlayerName`
  /// given the current per-team selection map.
  static String? primaryLinkedPlayerName(
    List<TeamLinkOption> options,
    Map<String, String?> selectedPlayerByTeam,
  ) {
    for (final opt in options) {
      final selectedId = selectedPlayerByTeam[opt.team.id];
      final player = opt.playerById(selectedId);
      if (player != null) return player.displayName;
    }
    return null;
  }
}
