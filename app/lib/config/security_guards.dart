/// Shared client-side input validation and security helpers.
class CreaseSecurity {
  CreaseSecurity._();

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static final RegExp _supabaseAvatarUrlRegex = RegExp(
    r'^https://ajwqkcblakfojsbyqjqt\.supabase\.co/storage/v1/object/public/avatars/[0-9a-fA-F-]+/[A-Za-z0-9._-]+(\?v=[0-9]+)?$',
  );

  static final RegExp _googleAvatarUrlRegex = RegExp(
    r'^https://lh[3-6]\.googleusercontent\.com/[^\s"<>]+$',
  );

  /// Returns `true` only for canonical hyphenated UUID strings.
  static bool isValidUuid(String? value) {
    if (value == null) return false;
    return _uuidRegex.hasMatch(value.trim());
  }

  /// Validates an image URL against Crease's trusted HTTPS host allowlist.
  /// Returns `null` for untrusted hosts, cleartext HTTP, or malformed URLs.
  static String? sanitizeImageUrl(
    String? raw, {
    bool allowGoogleProfilePhotos = false,
  }) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed.length > 1024) {
      return null;
    }
    if (_supabaseAvatarUrlRegex.hasMatch(trimmed)) {
      return trimmed;
    }
    if (allowGoogleProfilePhotos && _googleAvatarUrlRegex.hasMatch(trimmed)) {
      return trimmed;
    }
    return null;
  }
}

/// Typed exception for structured JSONB RPC error responses (`ok: false`).
class CreaseRpcException implements Exception {
  const CreaseRpcException(
    this.code, {
    this.retryAfterSeconds,
  });

  /// Machine-readable code returned by Postgres RPCs:
  /// `rate_limited`, `invalid_code`, `auth_required`, `already_claimed`,
  /// `player_not_found`, `invalid_name`, or `unknown`.
  final String code;
  final int? retryAfterSeconds;

  String get userMessage {
    switch (code) {
      case 'rate_limited':
        final secs = retryAfterSeconds ?? 60;
        final mins = (secs / 60).ceil().clamp(1, 60);
        return 'Too many invalid attempts. Please try again in $mins ${mins == 1 ? 'minute' : 'minutes'}.';
      case 'invalid_code':
        return 'Code not found or expired. Double-check the 6 digits.';
      case 'auth_required':
        return 'Please sign in to continue.';
      case 'already_claimed':
        return 'That player spot is already claimed by another account.';
      case 'player_not_found':
        return 'Player not found in this team.';
      case 'invalid_name':
        return 'Enter a valid player name (up to 80 characters).';
      default:
        return 'Could not complete request right now. Please try again.';
    }
  }

  @override
  String toString() => 'CreaseRpcException($code)';
}
