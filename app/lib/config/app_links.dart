/// Public live web scorecard base URL (GitHub Pages from /docs).
/// Update this if you connect a custom domain later.
class CreaseLinks {
  CreaseLinks._();

  static const String liveScorecardBaseUrl =
      'https://abdurrehmanbhatti.github.io/crease/';

  static String liveMatchUrl(String matchId) =>
      '$liveScorecardBaseUrl?match=${Uri.encodeQueryComponent(matchId)}';
}
