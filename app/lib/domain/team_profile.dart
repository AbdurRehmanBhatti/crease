import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Per-player cricket role & team designation stored on [TeamProfile].
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

  bool get isEmpty => role.trim().isEmpty && (designation == null || designation!.isEmpty);

  SquadPlayerMeta copyWith({
    String? role,
    String? designation,
    bool clearDesignation = false,
  }) =>
      SquadPlayerMeta(
        role: role ?? this.role,
        designation: clearDesignation ? null : (designation ?? this.designation),
      );

  Map<String, Object?> toJsonMap() => {
        'role': role,
        if (designation != null && designation!.isNotEmpty)
          'designation': designation,
      };

  static SquadPlayerMeta fromJsonMap(Map<String, Object?> map) =>
      SquadPlayerMeta(
        role: (map['role'] as String?) ?? '',
        designation: map['designation'] as String?,
      );
}

@immutable
class TeamProfile {
  const TeamProfile({
    required this.id,
    required this.name,
    this.location,
    this.isMyTeam = false,
    this.isOwner = true,
    this.players = const [],
    this.playerMeta = const {},
    this.synced = false,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? location;
  final bool isMyTeam;
  final bool isOwner;
  final List<String> players;
  final Map<String, SquadPlayerMeta> playerMeta;
  final bool synced;
  final DateTime createdAt;

  SquadPlayerMeta metaFor(String playerName) {
    final direct = playerMeta[playerName];
    if (direct != null) return direct;
    final lower = playerName.toLowerCase();
    for (final entry in playerMeta.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return const SquadPlayerMeta();
  }

  /// Updates [playerName]'s role/designation while keeping C / VC / WK unique
  /// across the squad.
  TeamProfile withUpdatedPlayerMeta(String playerName, SquadPlayerMeta meta) {
    final next = Map<String, SquadPlayerMeta>.from(playerMeta);
    final des = meta.designation;
    if (des != null && des.isNotEmpty) {
      for (final entry in next.entries.toList()) {
        if (entry.key.toLowerCase() != playerName.toLowerCase() &&
            entry.value.designation == des) {
          next[entry.key] = entry.value.copyWith(clearDesignation: true);
        }
      }
    }
    if (meta.isEmpty) {
      next.removeWhere((k, _) => k.toLowerCase() == playerName.toLowerCase());
    } else {
      next.removeWhere((k, _) => k.toLowerCase() == playerName.toLowerCase());
      next[playerName] = meta;
    }
    return copyWith(playerMeta: next);
  }

  TeamProfile copyWith({
    String? name,
    String? location,
    bool clearLocation = false,
    bool? isMyTeam,
    bool? isOwner,
    List<String>? players,
    Map<String, SquadPlayerMeta>? playerMeta,
    bool? synced,
  }) =>
      TeamProfile(
        id: id,
        name: name ?? this.name,
        location: clearLocation ? null : (location ?? this.location),
        isMyTeam: isMyTeam ?? this.isMyTeam,
        isOwner: isOwner ?? this.isOwner,
        players: players ?? this.players,
        playerMeta: playerMeta ?? this.playerMeta,
        synced: synced ?? this.synced,
        createdAt: createdAt,
      );

  Map<String, Object?> toJsonMetaMap() => {
        for (final entry in playerMeta.entries)
          if (!entry.value.isEmpty) entry.key: entry.value.toJsonMap(),
      };

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'location': (location != null && location!.trim().isNotEmpty)
            ? location!.trim()
            : null,
        'is_my_team': isMyTeam ? 1 : 0,
        'is_owner': isOwner ? 1 : 0,
        'players': jsonEncode(players),
        'player_meta': jsonEncode(toJsonMetaMap()),
        'synced': synced ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static bool _decodeBool(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    return false;
  }

  static List<String> _decodePlayers(Object? raw) {
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is List) return list.map((e) => e.toString()).toList();
    } catch (_) {}
    return const [];
  }

  static Map<String, SquadPlayerMeta> _decodeMeta(Object? raw) {
    Map<String, dynamic>? decoded;
    if (raw is Map) {
      decoded = Map<String, dynamic>.from(raw);
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is Map) decoded = Map<String, dynamic>.from(parsed);
      } catch (_) {}
    }
    if (decoded == null) return const {};
    final out = <String, SquadPlayerMeta>{};
    for (final entry in decoded.entries) {
      if (entry.value is Map) {
        out[entry.key] = SquadPlayerMeta.fromJsonMap(
          Map<String, Object?>.from(entry.value as Map),
        );
      }
    }
    return out;
  }

  static TeamProfile fromMap(Map<String, Object?> map) {
    final rawLoc = (map['location'] as String?)?.trim();
    return TeamProfile(
      id: map['id']! as String,
      name: map['name']! as String,
      location: (rawLoc != null && rawLoc.isNotEmpty) ? rawLoc : null,
      isMyTeam: _decodeBool(map['is_my_team']),
      isOwner: map.containsKey('is_owner') ? _decodeBool(map['is_owner']) : true,
      players: _decodePlayers(map['players']),
      playerMeta: _decodeMeta(map['player_meta']),
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
    required this.claimedPlayers,
    this.myClaimedPlayer,
  });

  final String teamId;
  final String teamName;
  final List<String> players;
  final List<String> claimedPlayers;
  final String? myClaimedPlayer;
}
