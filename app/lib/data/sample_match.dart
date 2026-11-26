import '../domain/models.dart';

/// Synthetic sample match used to demonstrate Crease immediately on first launch.
/// Clearly flagged with [MatchConfig.isDemo] = true.
/// Uses deterministic UUIDv4s and `adHocPlayers` so every ID in the app is uniform.
class SampleMatchSeed {
  SampleMatchSeed._();

  static const String demoMatchId = '00000000-0000-4000-8000-000000000001';

  static String _playerUuid(int index) =>
      '00000000-0000-4000-8000-00000001${index.toString().padLeft(4, '0')}';

  static String _ballUuid(int seq) =>
      '00000000-0000-4000-8000-00000002${seq.toString().padLeft(4, '0')}';

  static const List<String> _teamANames = [
    'Babar R.',
    'Saim A.',
    'Fakhar Z.',
    'Shan M.',
    'Iftikhar A.',
    'Shadab K.',
    'A. Salman',
    'S. Afridi',
    'H. Ali',
    'A. Jamal',
    'Z. Khan',
  ];

  static const List<String> _teamBNames = [
    'M. Rizwan',
    'S. Masood',
    'J. Vince',
    'K. Pollard',
    'I. Wasim',
    'S. Khan',
    'M. Nawaz',
    'M. Amir',
    'N. Shah',
    'H. Rauf',
    'M. Hasnain',
  ];

  static final Map<String, String> _nameToId = {
    for (var i = 0; i < _teamANames.length; i++) _teamANames[i]: _playerUuid(i + 1),
    for (var i = 0; i < _teamBNames.length; i++) _teamBNames[i]: _playerUuid(101 + i),
  };

  static final Map<String, String> _adHocPlayers = {
    for (final e in _nameToId.entries) e.value: e.key,
  };

  static String _id(String name) => _nameToId[name] ?? _nameToId['M. Rizwan']!;

  static MatchConfig config() => MatchConfig(
        id: demoMatchId,
        teamA: 'LHR Lions',
        teamB: 'KHI Kites',
        oversLimit: 20,
        playersPerSide: 11,
        formatLabel: 'T20',
        battingFirstSide: MatchSide.b,
        openingStriker1Id: _id('M. Rizwan'),
        openingNonStriker1Id: _id('S. Masood'),
        openingBowler1Id: _id('S. Afridi'),
        openingStriker2Id: _id('Babar R.'),
        openingNonStriker2Id: _id('Saim A.'),
        openingBowler2Id: _id('M. Amir'),
        teamAPlayerIds: [for (final n in _teamANames) _id(n)],
        teamBPlayerIds: [for (final n in _teamBNames) _id(n)],
        adHocPlayers: _adHocPlayers,
        firstInningsTargetOverride: 180,
        isDemo: true,
        createdAt: DateTime(2026, 11, 21, 19, 0),
      );

  static List<BallEvent> innings1Events() {
    final baseTime = DateTime(2026, 11, 21, 17, 30);
    final list = <BallEvent>[];
    var seq = 1;
    String strikerId = _id('M. Rizwan');
    String nonStrikerId = _id('S. Masood');
    var legalInOver = 0;

    void addBall({
      required String bowler,
      int runs = 0,
      bool wicket = false,
      WicketType? wicketType,
      String? fielder,
      String? nextBatter,
    }) {
      final nextId = nextBatter != null ? _id(nextBatter) : null;
      final event = BallEvent(
        id: _ballUuid(seq),
        matchId: demoMatchId,
        inningsNumber: 1,
        sequenceNumber: seq,
        strikerId: strikerId,
        nonStrikerId: nonStrikerId,
        bowlerId: _id(bowler),
        runsOffBat: runs,
        isWicket: wicket,
        wicketType: wicketType,
        dismissedBatterId: wicket ? strikerId : null,
        fielderId: fielder != null ? _id(fielder) : null,
        nextBatterId: nextId,
        synced: true,
        createdAt: baseTime.add(Duration(seconds: seq * 20)),
      );
      list.add(event);
      seq++;
      if (wicket && nextId != null) strikerId = nextId;
      if (runs.isOdd) {
        final t = strikerId;
        strikerId = nonStrikerId;
        nonStrikerId = t;
      }
      legalInOver++;
      if (legalInOver == 6) {
        legalInOver = 0;
        final t = strikerId;
        strikerId = nonStrikerId;
        nonStrikerId = t;
      }
    }

    final scripts = <_OverScript>[
      const _OverScript('S. Afridi', [0, 4, 1, 0, 2, 1]),
      const _OverScript('H. Ali', [1, 4, 0, 1, 2, 1]),
      const _OverScript('S. Afridi', [4, 0, 1, 0, 1, 2], wktIdx: 3, wktType: WicketType.bowled, next: 'J. Vince'),
      const _OverScript('H. Ali', [2, 1, 4, 0, 1, 1]),
      const _OverScript('Z. Khan', [1, 0, 4, 2, 1, 1]),
      const _OverScript('Shadab K.', [0, 2, 1, 4, 1, 1]),
      const _OverScript('Z. Khan', [1, 1, 2, 0, 4, 0], wktIdx: 5, wktType: WicketType.lbw, next: 'K. Pollard'),
      const _OverScript('Shadab K.', [1, 6, 0, 1, 1, 1]),
      const _OverScript('A. Jamal', [0, 2, 4, 1, 1, 1]),
      const _OverScript('Shadab K.', [1, 0, 2, 1, 4, 1]),
      const _OverScript('A. Jamal', [0, 1, 0, 6, 1, 1], wktIdx: 2, wktType: WicketType.caught, next: 'I. Wasim'),
      const _OverScript('Z. Khan', [1, 2, 1, 4, 0, 1]),
      const _OverScript('Shadab K.', [2, 1, 4, 0, 1, 1]),
      const _OverScript('H. Ali', [1, 0, 6, 1, 1, 0], wktIdx: 5, wktType: WicketType.bowled, next: 'S. Khan'),
      const _OverScript('A. Jamal', [1, 4, 1, 2, 0, 1]),
      const _OverScript('Z. Khan', [2, 1, 0, 4, 1, 1]),
      const _OverScript('S. Afridi', [1, 0, 4, 1, 2, 1], wktIdx: 1, wktType: WicketType.caught, next: 'M. Nawaz'),
      const _OverScript('H. Ali', [2, 4, 1, 0, 2, 1]),
      const _OverScript('A. Jamal', [1, 0, 6, 1, 1, 0], wktIdx: 5, wktType: WicketType.bowled, next: 'M. Amir'),
      const _OverScript('S. Afridi', [1, 2, 4, 1, 1, 0]),
    ];

    for (final ov in scripts) {
      for (var i = 0; i < ov.runs.length; i++) {
        final isWkt = ov.wktIdx == i;
        addBall(
          bowler: ov.bowler,
          runs: isWkt ? 0 : ov.runs[i],
          wicket: isWkt,
          wicketType: isWkt ? ov.wktType : null,
          nextBatter: isWkt ? ov.next : null,
        );
      }
    }
    return list;
  }

  static List<BallEvent> events() {
    final baseTime = DateTime(2026, 11, 21, 19, 10);
    final list = <BallEvent>[...innings1Events()];
    var seq = list.length + 1;

    String strikerId = _id('Babar R.');
    String nonStrikerId = _id('Saim A.');
    int legalInOver = 0;

    void addBall({
      required String bowler,
      int runs = 0,
      ExtraType extra = ExtraType.none,
      int extraRuns = 0,
      bool wicket = false,
      WicketType? wicketType,
      String? fielder,
      String? nextBatter,
    }) {
      final nextId = nextBatter != null ? _id(nextBatter) : null;
      final event = BallEvent(
        id: _ballUuid(seq),
        matchId: demoMatchId,
        inningsNumber: 2,
        sequenceNumber: seq,
        strikerId: strikerId,
        nonStrikerId: nonStrikerId,
        bowlerId: _id(bowler),
        runsOffBat: runs,
        extraType: extra,
        extraRuns: extraRuns,
        isWicket: wicket,
        wicketType: wicketType,
        dismissedBatterId: wicket ? strikerId : null,
        fielderId: fielder != null ? _id(fielder) : null,
        nextBatterId: nextId,
        synced: true,
        createdAt: baseTime.add(Duration(seconds: seq * 25)),
      );
      list.add(event);
      seq++;

      if (wicket && nextId != null) {
        strikerId = nextId;
      }
      final running = event.runningRuns;
      if (running.isOdd) {
        final t = strikerId;
        strikerId = nonStrikerId;
        nonStrikerId = t;
      }
      if (extra.isLegalDelivery) {
        legalInOver++;
        if (legalInOver == 6) {
          legalInOver = 0;
          final t = strikerId;
          strikerId = nonStrikerId;
          nonStrikerId = t;
        }
      }
    }

    final overScripts = <_OverScript>[
      const _OverScript('M. Amir', [1, 0, 4, 0, 1, 2]),
      const _OverScript('N. Shah', [0, 4, 1, 2, 0, 1]),
      const _OverScript('M. Amir', [2, 0, 4, 1, 0, 2]),
      const _OverScript('H. Rauf', [1, 4, 0, 1, 2, 1]),
      const _OverScript('S. Khan', [1, 2, 0, 4, 1, 1]),
      const _OverScript('N. Shah', [0, 1, 0, 4, 1, 2], wktIdx: 2, wktType: WicketType.bowled, next: 'Fakhar Z.'),
      const _OverScript('S. Khan', [1, 1, 2, 0, 4, 1]),
      const _OverScript('M. Amir', [0, 4, 1, 0, 1, 1]),
      const _OverScript('S. Khan', [2, 1, 4, 0, 1, 0]),
      const _OverScript('H. Rauf', [0, 2, 1, 4, 1, 0]),
      const _OverScript('N. Shah', [1, 4, 2, 1, 0, 1]),
      const _OverScript('S. Khan', [1, 0, 2, 1, 1, 1]),
      const _OverScript('M. Amir', [4, 0, 1, 0, 2, 1], wktIdx: 3, wktType: WicketType.lbw, next: 'Shan M.'),
      const _OverScript('I. Wasim', [2, 4, 1, 2, 4, 0]),
      const _OverScript('H. Rauf', [1, 0, 2, 1, 4, 1]),
      const _OverScript('N. Shah', [1, 2, 1, 4, 1, 0]),
    ];

    for (final ov in overScripts) {
      for (var i = 0; i < ov.runs.length; i++) {
        final isWkt = ov.wktIdx == i;
        addBall(
          bowler: ov.bowler,
          runs: isWkt ? 0 : ov.runs[i],
          wicket: isWkt,
          wicketType: isWkt ? ov.wktType : null,
          nextBatter: isWkt ? ov.next : null,
        );
      }
    }

    addBall(bowler: 'H. Rauf', runs: 1);
    addBall(bowler: 'H. Rauf', runs: 0);
    addBall(bowler: 'H. Rauf', runs: 4);
    addBall(
      bowler: 'H. Rauf',
      runs: 0,
      wicket: true,
      wicketType: WicketType.caught,
      fielder: 'M. Rizwan',
      nextBatter: 'Iftikhar A.',
    );

    return list;
  }
}

class _OverScript {
  const _OverScript(
    this.bowler,
    this.runs, {
    this.wktIdx,
    this.wktType,
    this.next,
  });

  final String bowler;
  final List<int> runs;
  final int? wktIdx;
  final WicketType? wktType;
  final String? next;
}
