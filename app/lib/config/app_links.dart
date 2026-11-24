/// Public live web scorecard base URL (GitHub Pages from /docs) and
/// deep-link parsing helpers for both HTTPS App Links and `crease://` links.
class CreaseLinks {
  CreaseLinks._();

  static const String liveScorecardBaseUrl =
      'https://abdurrehmanbhatti.github.io/crease/';

  static String liveMatchUrl(String matchId) =>
      '$liveScorecardBaseUrl?match=${Uri.encodeQueryComponent(matchId)}';

  static String appMatchUri(String matchId) =>
      'crease://match/${Uri.encodeComponent(matchId)}';

  static String tournamentUrl(String tournamentId) =>
      '$liveScorecardBaseUrl?tournament=${Uri.encodeQueryComponent(tournamentId)}';

  static String appTournamentUri(String tournamentId) =>
      'crease://tournament/${Uri.encodeComponent(tournamentId)}';

  static String teamInviteUrl(String code) =>
      '$liveScorecardBaseUrl?team-code=${Uri.encodeQueryComponent(code)}';

  /// Extracts a match ID from either:
  /// - `https://abdurrehmanbhatti.github.io/crease/?match=<id>`
  /// - `crease://match/<id>` or `crease://match?match=<id>`
  static String? parseMatchId(Uri uri) {
    final queryId = uri.queryParameters['match']?.trim();
    if (queryId != null && queryId.isNotEmpty) {
      return queryId;
    }
    if (uri.scheme == 'crease' && uri.host == 'match') {
      final segs = uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
      if (segs.isNotEmpty) {
        return Uri.decodeComponent(segs.first).trim();
      }
    }
    return null;
  }

  /// Extracts a tournament ID from either:
  /// - `https://abdurrehmanbhatti.github.io/crease/?tournament=<id>`
  /// - `crease://tournament/<id>` or `crease://tournament?tournament=<id>`
  static String? parseTournamentId(Uri uri) {
    final queryId = uri.queryParameters['tournament']?.trim();
    if (queryId != null && queryId.isNotEmpty) {
      return queryId;
    }
    if (uri.scheme == 'crease' && uri.host == 'tournament') {
      final segs = uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
      if (segs.isNotEmpty) {
        return Uri.decodeComponent(segs.first).trim();
      }
    }
    return null;
  }

  /// Extracts a 6-digit team invite code from either:
  /// - `https://abdurrehmanbhatti.github.io/crease/?team-code=<6-digits>`
  /// - `crease://join-team/<6-digits>`
  static String? parseTeamInviteCode(Uri uri) {
    final q = uri.queryParameters['team-code']?.trim();
    if (q != null && q.isNotEmpty) {
      return q.replaceAll(RegExp(r'[^0-9]'), '');
    }
    if (uri.scheme == 'crease' && uri.host == 'join-team') {
      final segs = uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
      if (segs.isNotEmpty) {
        return Uri.decodeComponent(segs.first).replaceAll(RegExp(r'[^0-9]'), '');
      }
    }
    return null;
  }
}
