import 'dart:convert';

import 'package:flutter/foundation.dart';

@immutable
class TeamProfile {
  const TeamProfile({
    required this.id,
    required this.name,
    this.isMyTeam = false,
    this.players = const [],
    this.synced = false,
    required this.createdAt,
  });

  final String id;
  final String name;
  final bool isMyTeam;
  final List<String> players;
  final bool synced;
  final DateTime createdAt;

  TeamProfile copyWith({
    String? name,
    bool? isMyTeam,
    List<String>? players,
    bool? synced,
  }) =>
      TeamProfile(
        id: id,
        name: name ?? this.name,
        isMyTeam: isMyTeam ?? this.isMyTeam,
        players: players ?? this.players,
        synced: synced ?? this.synced,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'is_my_team': isMyTeam ? 1 : 0,
        'players': jsonEncode(players),
        'synced': synced ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static List<String> _decodePlayers(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is List) return list.map((e) => e.toString()).toList();
    } catch (_) {}
    return const [];
  }

  static TeamProfile fromMap(Map<String, Object?> map) => TeamProfile(
        id: map['id']! as String,
        name: map['name']! as String,
        isMyTeam: ((map['is_my_team'] as int?) ?? 0) == 1,
        players: _decodePlayers(map['players']),
        synced: ((map['synced'] as int?) ?? 0) == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
      );
}
