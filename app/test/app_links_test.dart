import 'package:crease/config/app_links.dart';
import 'package:crease/config/security_guards.dart';
import 'package:crease/domain/team_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const matchUuid1 = '11111111-1111-4111-8111-111111111111';
  const matchUuid2 = '22222222-2222-4222-8222-222222222222';
  const matchUuid3 = '33333333-3333-4333-8333-333333333333';
  const tourneyUuid1 = '44444444-4444-4444-8444-444444444444';
  const tourneyUuid2 = '55555555-5555-4555-8555-555555555555';

  test('CreaseLinks parses valid UUID HTTPS and custom scheme URIs', () {
    final httpsUri = Uri.parse(CreaseLinks.liveMatchUrl(matchUuid1));
    expect(CreaseLinks.parseMatchId(httpsUri), matchUuid1);

    final schemeUri = Uri.parse(CreaseLinks.appMatchUri(matchUuid2));
    expect(CreaseLinks.parseMatchId(schemeUri), matchUuid2);

    final schemeQuery = Uri.parse('crease://match?match=$matchUuid3');
    expect(CreaseLinks.parseMatchId(schemeQuery), matchUuid3);

    final unrelated = Uri.parse('https://abdurrehmanbhatti.github.io/crease/');
    expect(CreaseLinks.parseMatchId(unrelated), isNull);
    expect(CreaseLinks.parseTeamInviteCode(unrelated), isNull);

    final teamHttps = Uri.parse(CreaseLinks.teamInviteUrl('731492'));
    expect(CreaseLinks.parseTeamInviteCode(teamHttps), '731492');

    final teamScheme = Uri.parse('crease://join-team/731492');
    expect(CreaseLinks.parseTeamInviteCode(teamScheme), '731492');

    final tourneyHttps = Uri.parse(CreaseLinks.tournamentUrl(tourneyUuid1));
    expect(CreaseLinks.parseTournamentId(tourneyHttps), tourneyUuid1);

    final tourneyScheme =
        Uri.parse(CreaseLinks.appTournamentUri(tourneyUuid2));
    expect(CreaseLinks.parseTournamentId(tourneyScheme), tourneyUuid2);

    expect(CreaseLinks.parseTournamentId(unrelated), isNull);
  });

  test('CreaseLinks rejects non-UUID and injection-shaped deep link IDs', () {
    expect(
      CreaseLinks.parseMatchId(
        Uri.parse('https://abdurrehmanbhatti.github.io/crease/?match=not-a-uuid'),
      ),
      isNull,
    );
    expect(
      CreaseLinks.parseMatchId(
        Uri.parse('crease://match/1,owner_id.neq.null'),
      ),
      isNull,
    );
    expect(
      CreaseLinks.parseTournamentId(
        Uri.parse('crease://tournament/..%2F..%2Fetc'),
      ),
      isNull,
    );
  });

  test('CreaseSecurity.sanitizeImageUrl enforces trusted HTTPS hosts', () {
    const sbUrl =
        'https://ajwqkcblakfojsbyqjqt.supabase.co/storage/v1/object/public/avatars/11111111-1111-4111-8111-111111111111/avatar.jpg?v=12345';
    const googleUrl = 'https://lh3.googleusercontent.com/a/ACg8ocTest=s96-c';

    expect(CreaseSecurity.sanitizeImageUrl(sbUrl), sbUrl);
    expect(
      CreaseSecurity.sanitizeImageUrl(googleUrl, allowGoogleProfilePhotos: true),
      googleUrl,
    );
    expect(
      CreaseSecurity.sanitizeImageUrl(googleUrl, allowGoogleProfilePhotos: false),
      isNull,
    );
    expect(
      CreaseSecurity.sanitizeImageUrl('https://evil.example.com/pixel.png'),
      isNull,
    );
    expect(
      CreaseSecurity.sanitizeImageUrl(
        'http://ajwqkcblakfojsbyqjqt.supabase.co/storage/v1/object/public/avatars/a/b.jpg',
      ),
      isNull,
    );
    expect(
      CreaseSecurity.sanitizeImageUrl('javascript:alert(1)'),
      isNull,
    );
  });

  test('PlayerProfile.fromMap recognizes public is_claimed without raw user_id', () {
    final claimed = PlayerProfile.fromMap({
      'id': matchUuid1,
      'team_id': matchUuid2,
      'display_name': 'Babar',
      'is_claimed': true,
    });
    expect(claimed.userId, isNull);
    expect(claimed.isClaimed, isTrue);
    expect(claimed.isLinked, isTrue);

    final unclaimed = PlayerProfile.fromMap({
      'id': matchUuid3,
      'team_id': matchUuid2,
      'display_name': 'Shaheen',
      'is_claimed': false,
    });
    expect(unclaimed.isLinked, isFalse);
  });
}
