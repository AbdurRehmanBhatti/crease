import 'package:crease/config/app_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CreaseLinks parses HTTPS and custom scheme match URIs', () {
    final httpsUri = Uri.parse(CreaseLinks.liveMatchUrl('match-123'));
    expect(CreaseLinks.parseMatchId(httpsUri), 'match-123');

    final schemeUri = Uri.parse(CreaseLinks.appMatchUri('match-456'));
    expect(CreaseLinks.parseMatchId(schemeUri), 'match-456');

    final schemeQuery = Uri.parse('crease://match?match=match-789');
    expect(CreaseLinks.parseMatchId(schemeQuery), 'match-789');

    final unrelated = Uri.parse('https://abdurrehmanbhatti.github.io/crease/');
    expect(CreaseLinks.parseMatchId(unrelated), isNull);
    expect(CreaseLinks.parseTeamInviteCode(unrelated), isNull);

    final teamHttps = Uri.parse(CreaseLinks.teamInviteUrl('731492'));
    expect(CreaseLinks.parseTeamInviteCode(teamHttps), '731492');

    final teamScheme = Uri.parse('crease://join-team/731492');
    expect(CreaseLinks.parseTeamInviteCode(teamScheme), '731492');

    final tourneyHttps = Uri.parse(CreaseLinks.tournamentUrl('tourney-101'));
    expect(CreaseLinks.parseTournamentId(tourneyHttps), 'tourney-101');

    final tourneyScheme =
        Uri.parse(CreaseLinks.appTournamentUri('tourney-202'));
    expect(CreaseLinks.parseTournamentId(tourneyScheme), 'tourney-202');

    expect(CreaseLinks.parseTournamentId(unrelated), isNull);
  });
}
