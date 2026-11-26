import 'models.dart';
import 'team_profile.dart';

/// Snapshot of an existing cloud team owned by the newly signed-in user.
class CloudOwnedTeam {
  const CloudOwnedTeam({
    required this.id,
    required this.name,
    this.squad = const [],
    this.location,
  });

  final String id;
  final String name;
  final List<PlayerProfile> squad;
  final String? location;
}

/// Action to apply when an offline guest team collides by name (case-insensitive)
/// with an existing cloud team owned by the signed-in user.
class GuestTeamMergeAction {
  const GuestTeamMergeAction({
    required this.guestTeamId,
    required this.survivingTeamId,
    required this.playersToReparent,
    required this.mergedLocation,
    required this.needsCloudTeamUpdate,
  });

  final String guestTeamId;
  final String survivingTeamId;
  final List<PlayerProfile> playersToReparent;
  final String? mergedLocation;
  final bool needsCloudTeamUpdate;
}

/// Pure, deterministic planner for merging offline guest teams into existing
/// registered-account teams and repointing match team IDs.
class GuestTeamMergePlanner {
  GuestTeamMergePlanner._();

  static List<GuestTeamMergeAction> planOfflineMerges({
    required List<TeamProfile> unsyncedGuestTeams,
    required List<CloudOwnedTeam> ownedCloudTeams,
  }) {
    final ownedByLower = <String, CloudOwnedTeam>{};
    for (final t in ownedCloudTeams) {
      final key = t.name.trim().toLowerCase();
      if (key.isEmpty || t.id.isEmpty) continue;
      ownedByLower.putIfAbsent(key, () => t);
    }

    final actions = <GuestTeamMergeAction>[];
    for (final guestTeam in unsyncedGuestTeams) {
      final key = guestTeam.name.trim().toLowerCase();
      if (key.isEmpty) continue;
      final existing = ownedByLower[key];
      if (existing == null || existing.id == guestTeam.id) continue;

      final existingDesignations = existing.squad
          .where((p) => !p.archived && p.designation != null)
          .map((p) => p.designation!)
          .toSet();

      final reparented = <PlayerProfile>[];
      for (final p in guestTeam.squad) {
        final clearDes =
            p.designation != null && existingDesignations.contains(p.designation);
        if (!clearDes && p.designation != null) {
          existingDesignations.add(p.designation!);
        }
        reparented.add(
          p.copyWith(
            teamId: existing.id,
            clearDesignation: clearDes,
            synced: false,
          ),
        );
      }

      final existingLoc = existing.location?.trim();
      final guestLoc = guestTeam.location?.trim();
      final resolvedExistingLoc =
          (existingLoc != null && existingLoc.isNotEmpty) ? existingLoc : null;
      final resolvedGuestLoc =
          (guestLoc != null && guestLoc.isNotEmpty) ? guestLoc : null;
      final mergedLocation = resolvedExistingLoc ?? resolvedGuestLoc;
      final locChanged = mergedLocation != resolvedExistingLoc;

      actions.add(
        GuestTeamMergeAction(
          guestTeamId: guestTeam.id,
          survivingTeamId: existing.id,
          playersToReparent: reparented,
          mergedLocation: mergedLocation,
          needsCloudTeamUpdate: locChanged,
        ),
      );

      ownedByLower[key] = CloudOwnedTeam(
        id: existing.id,
        name: existing.name,
        squad: [...existing.squad, ...reparented],
        location: mergedLocation,
      );
    }
    return actions;
  }

  /// Rewrites [teamAId] / [teamBId] on [matches] according to [idMap]
  /// (`oldGuestTeamId -> survivingTeamId`), leaving unrelated IDs untouched.
  static List<MatchConfig> rewriteMatchTeamIds(
    List<MatchConfig> matches,
    Map<String, String> idMap,
  ) {
    if (idMap.isEmpty) return matches;
    return [
      for (final m in matches)
        m.copyWith(
          teamAId: idMap[m.teamAId] ?? m.teamAId,
          teamBId: idMap[m.teamBId] ?? m.teamBId,
        ),
    ];
  }
}
