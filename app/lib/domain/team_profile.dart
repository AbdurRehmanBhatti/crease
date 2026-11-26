import 'package:flutter/foundation.dart';

/// Per-player cricket role & team designation helper.
@immutable
class SquadPlayerMeta {
  const SquadPlayerMeta({
    this.role = '',
    this.designation,
  });

  /// e.g. 'Batter', 'Bowler', 'All-rounder', 'Wicket-keeper'
  final String role;

  /// 'C' (Captain), 'VC' (Vice-Captain), 'WK' (Wicket-Keeper), or null
  final String? designation;

  static const List<String> roles = [
    'Batter',
    'Bowler',
    'All-rounder',
    'Wicket-keeper',
  ];

  static const List<String> designations = ['C', 'VC', 'WK'];

  String get designationLabel => switch (designation) {
        'C' => 'Captain',
        'VC' => 'Vice-Captain',
        'WK' => 'Wicket-Keeper',
        _ => '',
      };

  bool get isEmpty =>
      role.trim().isEmpty && (designation == null || designation!.isEmpty);

  SquadPlayerMeta copyWith({
    String? role,
    String? designation,
    bool clearDesignation = false,
  }) =>
      SquadPlayerMeta(
        role: role ?? this.role,
        designation: clearDesignation ? null : (designation ?? this.designation),
      );
}

/// First-class normalized player record (`public.players` / SQLite `players`).
/// Single source of truth for display name, role, designation, and linked user.
@immutable
class PlayerProfile {
  const PlayerProfile({
    required this.id,
    required this.teamId,
    this.ownerId,
    this.userId,
    required this.displayName,
    this.role = '',
    this.designation,
    this.memberRole = 'player',
    this.avatarUrl,
    this.claimedAt,
    this.archived = false,
    this.synced = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String teamId;
  final String? ownerId;
  final String? userId;
  final String displayName;
  final String role;
  final String? designation;
  final String memberRole; // 'captain' | 'player'
  final String? avatarUrl;
  final DateTime? claimedAt;
  final bool archived;
  final bool synced;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isLinked => userId != null && userId!.trim().isNotEmpty;
  bool get isCaptain => designation == 'C' || memberRole == 'captain';

  SquadPlayerMeta get meta => SquadPlayerMeta(
        role: role,
        designation: designation,
      );

  String get designationLabel => meta.designationLabel;

  PlayerProfile copyWith({
    String? teamId,
    String? ownerId,
    String? userId,
    bool clearUserId = false,
    String? displayName,
    String? role,
    String? designation,
    bool clearDesignation = false,
    String? memberRole,
    String? avatarUrl,
    bool clearAvatarUrl = false,
    DateTime? claimedAt,
    bool clearClaimedAt = false,
    bool? archived,
    bool? synced,
    DateTime? updatedAt,
  }) =>
      PlayerProfile(
        id: id,
        teamId: teamId ?? this.teamId,
        ownerId: ownerId ?? this.ownerId,
        userId: clearUserId ? null : (userId ?? this.userId),
        displayName: displayName ?? this.displayName,
        role: role ?? this.role,
        designation: clearDesignation ? null : (designation ?? this.designation),
        memberRole: memberRole ?? this.memberRole,
        avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
        claimedAt: clearClaimedAt ? null : (claimedAt ?? this.claimedAt),
        archived: archived ?? this.archived,
        synced: synced ?? this.synced,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'team_id': teamId,
        'owner_id': ownerId,
        'user_id': userId,
        'display_name': displayName,
        'role': role,
        'designation': designation,
        'member_role': memberRole,
        'avatar_url': avatarUrl,
        'claimed_at': claimedAt?.millisecondsSinceEpoch,
        'archived': archived ? 1 : 0,
        'synced': synced ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  static bool _decodeBool(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    return false;
  }

  static PlayerProfile fromMap(Map<String, Object?> map) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final createdMs = (map['created_at'] as num?)?.toInt() ?? nowMs;
    final updatedMs = (map['updated_at'] as num?)?.toInt() ?? createdMs;
    final claimedMs = (map['claimed_at'] as num?)?.toInt();
    final rawAvatar = (map['avatar_url'] as String?)?.trim();
    final rawDes = (map['designation'] as String?)?.trim();
    final rawUid = (map['user_id'] as String?)?.trim();
    return PlayerProfile(
      id: map['id']! as String,
      teamId: (map['team_id'] as String?) ?? '',
      ownerId: map['owner_id'] as String?,
      userId: (rawUid != null && rawUid.isNotEmpty) ? rawUid : null,
      displayName: (map['display_name'] as String?) ?? 'Player',
      role: (map['role'] as String?) ?? '',
      designation: (rawDes != null && rawDes.isNotEmpty) ? rawDes : null,
      memberRole: (map['member_role'] as String?) ?? 'player',
      avatarUrl: (rawAvatar != null && rawAvatar.isNotEmpty) ? rawAvatar : null,
      claimedAt: claimedMs != null
          ? DateTime.fromMillisecondsSinceEpoch(claimedMs)
          : null,
      archived: _decodeBool(map['archived']),
      synced: map.containsKey('synced') ? _decodeBool(map['synced']) : true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdMs),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedMs),
    );
  }
}

/// Immutable in-memory snapshot of all known players and teams, backing
/// O(1) name resolution across scorecards, stats, and live scoring.
@immutable
class PlayerDirectorySnapshot {
  const PlayerDirectorySnapshot({
    this.playersById = const {},
    this.playerNamesById = const {},
    this.playerUserIdsById = const {},
    this.teamNamesById = const {},
    this.teamLogosById = const {},
  });

  static const empty = PlayerDirectorySnapshot();

  final Map<String, PlayerProfile> playersById;
  final Map<String, String> playerNamesById;
  final Map<String, String> playerUserIdsById;
  final Map<String, String> teamNamesById;
  final Map<String, String> teamLogosById;

  String resolvePlayerName(
    String? id, {
    Map<String, String> adHocPlayers = const {},
    String fallback = '',
  }) {
    if (id == null || id.isEmpty) return fallback;
    return playerNamesById[id] ?? adHocPlayers[id] ?? fallback;
  }

  String resolveTeamName(String? teamId, String fallbackName) {
    if (teamId == null || teamId.isEmpty) return fallbackName;
    final resolved = teamNamesById[teamId];
    return (resolved != null && resolved.trim().isNotEmpty)
        ? resolved
        : fallbackName;
  }

  List<PlayerProfile> activePlayersForTeam(String teamId) {
    final list = playersById.values
        .where((p) => p.teamId == teamId && !p.archived)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  factory PlayerDirectorySnapshot.fromLists({
    required List<PlayerProfile> players,
    required List<TeamProfile> teams,
  }) {
    final pById = <String, PlayerProfile>{};
    final pNames = <String, String>{};
    final pUids = <String, String>{};
    for (final p in players) {
      pById[p.id] = p;
      pNames[p.id] = p.displayName;
      if (p.userId != null && p.userId!.isNotEmpty) {
        pUids[p.id] = p.userId!;
      }
    }
    final tNames = <String, String>{
      for (final t in teams) t.id: t.name,
    };
    final tLogos = <String, String>{
      for (final t in teams)
        if (t.logoUrl != null && t.logoUrl!.trim().isNotEmpty)
          t.id: t.logoUrl!.trim(),
    };
    return PlayerDirectorySnapshot(
      playersById: Map.unmodifiable(pById),
      playerNamesById: Map.unmodifiable(pNames),
      playerUserIdsById: Map.unmodifiable(pUids),
      teamNamesById: Map.unmodifiable(tNames),
      teamLogosById: Map.unmodifiable(tLogos),
    );
  }
}

@immutable
class TeamProfile {
  const TeamProfile({
    required this.id,
    required this.name,
    this.location,
    this.profileCode,
    this.logoUrl,
    this.isMyTeam = false,
    this.isOwner = true,
    this.squad = const [],
    this.synced = false,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? location;
  final String? profileCode;
  final String? logoUrl;
  final bool isMyTeam;
  final bool isOwner;

  /// Active (non-archived) squad players from `players` table.
  final List<PlayerProfile> squad;
  final bool synced;
  final DateTime createdAt;

  /// Convenience display-name list derived from [squad].
  List<String> get players => squad.map((p) => p.displayName).toList();

  /// Convenience UUID list derived from [squad].
  List<String> get playerIds => squad.map((p) => p.id).toList();

  PlayerProfile? playerById(String id) {
    for (final p in squad) {
      if (p.id == id) return p;
    }
    return null;
  }

  PlayerProfile? playerByName(String name) {
    final lower = name.trim().toLowerCase();
    for (final p in squad) {
      if (p.displayName.trim().toLowerCase() == lower) return p;
    }
    return null;
  }

  SquadPlayerMeta metaFor(String playerName) {
    final found = playerByName(playerName);
    return found?.meta ?? const SquadPlayerMeta();
  }

  TeamProfile copyWith({
    String? name,
    String? location,
    bool clearLocation = false,
    String? profileCode,
    String? logoUrl,
    bool clearLogo = false,
    bool? isMyTeam,
    bool? isOwner,
    List<PlayerProfile>? squad,
    bool? synced,
  }) =>
      TeamProfile(
        id: id,
        name: name ?? this.name,
        location: clearLocation ? null : (location ?? this.location),
        profileCode: profileCode ?? this.profileCode,
        logoUrl: clearLogo ? null : (logoUrl ?? this.logoUrl),
        isMyTeam: isMyTeam ?? this.isMyTeam,
        isOwner: isOwner ?? this.isOwner,
        squad: squad ?? this.squad,
        synced: synced ?? this.synced,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'location': (location != null && location!.trim().isNotEmpty)
            ? location!.trim()
            : null,
        'profile_code': (profileCode != null && profileCode!.trim().isNotEmpty)
            ? profileCode!.trim().toUpperCase()
            : null,
        'logo_url': (logoUrl != null && logoUrl!.trim().isNotEmpty)
            ? logoUrl!.trim()
            : null,
        'is_my_team': isMyTeam ? 1 : 0,
        'is_owner': isOwner ? 1 : 0,
        'synced': synced ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static bool _decodeBool(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    return false;
  }

  static TeamProfile fromMap(
    Map<String, Object?> map, {
    List<PlayerProfile> squad = const [],
  }) {
    final rawLoc = (map['location'] as String?)?.trim();
    final rawCode = (map['profile_code'] as String?)?.trim();
    final rawLogo = (map['logo_url'] as String?)?.trim();
    return TeamProfile(
      id: map['id']! as String,
      name: map['name']! as String,
      location: (rawLoc != null && rawLoc.isNotEmpty) ? rawLoc : null,
      profileCode:
          (rawCode != null && rawCode.isNotEmpty) ? rawCode.toUpperCase() : null,
      logoUrl: (rawLogo != null && rawLogo.isNotEmpty) ? rawLogo : null,
      isMyTeam: _decodeBool(map['is_my_team']),
      isOwner: map.containsKey('is_owner') ? _decodeBool(map['is_owner']) : true,
      squad: squad,
      synced: _decodeBool(map['synced']),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at']! as num).toInt(),
      ),
    );
  }
}

@immutable
class TeamInvitePreview {
  const TeamInvitePreview({
    required this.teamId,
    required this.teamName,
    required this.players,
    this.myClaimedPlayerId,
  });

  final String teamId;
  final String teamName;
  final List<PlayerProfile> players;
  final String? myClaimedPlayerId;
}
