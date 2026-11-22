import 'dart:convert';

import 'package:flutter/material.dart';

/// App-wide theme mode controller backed by local SQLite persistence.
class CreaseThemeController extends ValueNotifier<ThemeMode> {
  CreaseThemeController._() : super(ThemeMode.system);
  static final CreaseThemeController instance = CreaseThemeController._();
}

@immutable
class UserProfile {
  const UserProfile({
    this.displayName = '',
    this.role = 'All-rounder',
    this.linkedPlayerName,
    this.themeMode = ThemeMode.system,
  });

  final String displayName;
  final String role;
  final String? linkedPlayerName;
  final ThemeMode themeMode;

  static const List<String> roles = [
    'Batter',
    'Bowler',
    'All-rounder',
    'Wicket-keeper',
  ];

  String get effectiveName =>
      displayName.trim().isEmpty ? 'Crease Player' : displayName.trim();

  String get initials {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return '';
    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  UserProfile copyWith({
    String? displayName,
    String? role,
    String? linkedPlayerName,
    bool clearLinkedPlayer = false,
    ThemeMode? themeMode,
  }) {
    return UserProfile(
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      linkedPlayerName: clearLinkedPlayer
          ? null
          : (linkedPlayerName ?? this.linkedPlayerName),
      themeMode: themeMode ?? this.themeMode,
    );
  }

  String toJson() => jsonEncode({
        'display_name': displayName,
        'role': role,
        'linked_player_name': linkedPlayerName,
        'theme_mode': themeMode.name,
      });

  static UserProfile fromJson(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final modeName = map['theme_mode'] as String?;
      final mode = ThemeMode.values.firstWhere(
        (m) => m.name == modeName,
        orElse: () => ThemeMode.system,
      );
      return UserProfile(
        displayName: (map['display_name'] as String?) ?? '',
        role: (map['role'] as String?) ?? 'All-rounder',
        linkedPlayerName: map['linked_player_name'] as String?,
        themeMode: mode,
      );
    } catch (_) {
      return const UserProfile();
    }
  }
}
