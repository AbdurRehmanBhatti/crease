import '../domain/models.dart';

/// Synthetic sample match used to demonstrate Crease immediately on first launch.
/// Clearly flagged with [MatchConfig.isDemo] = true.
/// Produces exact real-cricket totals:
///   LHR Lions 142/3 (16.4 overs) chasing 180 -> Need 38 from 20 balls (RRR 11.4)
///   Over 17 so far: 1, •, 4, W (Fakhar Z. c Rizwan)
///   Bowler: H. Rauf 3.4-0-31-1
class SampleMatchSeed {
  SampleMatchSeed._();

  static const String demoMatchId = 'demo-lhr-v-khi-t20';

  static MatchConfig config() => MatchConfig(
        id: demoMatchId,
        teamA: 'LHR Lions',
        teamB: 'KHI Kites',
        oversLimit: 20,
        playersPerSide: 11,
        formatLabel: 'T20',
        battingFirstTeam: 'KHI Kites',
        openingStrikerInnings1: 'M. Rizwan',
        openingNonStrikerInnings1: 'S. Masood',
        openingBowlerInnings1: 'S. Afridi',
        openingStrikerInnings2: 'Babar R.',
        openingNonStrikerInnings2: 'Saim A.',
        openingBowlerInnings2: 'M. Amir',
        teamAPlayers: const [
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
        ],
        teamBPlayers: const [
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
        ],
        firstInningsTargetOverride: 180,
        isDemo: true,
        createdAt: DateTime(2026, 11, 21, 19, 0),
      );

  /// Generates realistic 1st innings (KHI Kites 179/6 in 20.0 ov) +
  /// 2nd innings (LHR Lions 142/3 in 16.4 ov) ball events so both teams
  /// appear cleanly across Overview, Scorecard, Charts (dual Worm), and Overs.
  static List<BallEvent> innings1Events() {
    final baseTime = DateTime(2026, 11, 21, 17, 30);
    final list = <BallEvent>[];
    var seq = 1;
    String striker = 'M. Rizwan';
    String nonStriker = 'S. Masood';
    var legalInOver = 0;

    void addBall({
      required String bowler,
      int runs = 0,
      bool wicket = false,
      WicketType? wicketType,
      String? fielder,
      String? nextBatter,
    }) {
      final event = BallEvent(
        id: 'demo-inn1-ball-$seq',
        matchId: demoMatchId,
        inningsNumber: 1,
        sequenceNumber: seq,
        striker: striker,
        nonStriker: nonStriker,
        bowler: bowler,
        runsOffBat: runs,
        isWicket: wicket,
        wicketType: wicketType,
        dismissedBatter: wicket ? striker : null,
        fielder: fielder,
        nextBatter: nextBatter,
        synced: true,
        createdAt: baseTime.add(Duration(seconds: seq * 20)),
      );
      list.add(event);
      seq++;
      if (wicket && nextBatter != null) striker = nextBatter;
      if (runs.isOdd) {
        final t = striker;
        striker = nonStriker;
        nonStriker = t;
      }
      legalInOver++;
      if (legalInOver == 6) {
        legalInOver = 0;
        final t = striker;
        striker = nonStriker;
        nonStriker = t;
      }
    }

    // 20 overs totaling 179/6 (target 180)
    final scripts = <_OverScript>[
      const _OverScript('S. Afridi', [0, 4, 1, 0, 2, 1]), // 8
      const _OverScript('H. Ali', [1, 4, 0, 1, 2, 1]), // 9 -> 17
      const _OverScript('S. Afridi', [4, 0, 1, 0, 1, 2], wktIdx: 3, wktType: WicketType.bowled, next: 'J. Vince'), // 8 -> 25/1
      const _OverScript('H. Ali', [2, 1, 4, 0, 1, 1]), // 9 -> 34/1
      const _OverScript('Z. Khan', [1, 0, 4, 2, 1, 1]), // 9 -> 43/1
      const _OverScript('Shadab K.', [0, 2, 1, 4, 1, 1]), // 9 -> 52/1
      const _OverScript('Z. Khan', [1, 1, 2, 0, 4, 0], wktIdx: 5, wktType: WicketType.lbw, next: 'K. Pollard'), // 8 -> 60/2
      const _OverScript('Shadab K.', [1, 6, 0, 1, 1, 1]), // 10 -> 70/2
      const _OverScript('A. Jamal', [0, 2, 4, 1, 1, 1]), // 9 -> 79/2
      const _OverScript('Shadab K.', [1, 0, 2, 1, 4, 1]), // 9 -> 88/2
      const _OverScript('A. Jamal', [0, 1, 0, 6, 1, 1], wktIdx: 2, wktType: WicketType.caught, next: 'I. Wasim'), // 9 -> 97/3
      const _OverScript('Z. Khan', [1, 2, 1, 4, 0, 1]), // 9 -> 106/3
      const _OverScript('Shadab K.', [2, 1, 4, 0, 1, 1]), // 9 -> 115/3
      const _OverScript('H. Ali', [1, 0, 6, 1, 1, 0], wktIdx: 5, wktType: WicketType.bowled, next: 'S. Khan'), // 9 -> 124/4
      const _OverScript('A. Jamal', [1, 4, 1, 2, 0, 1]), // 9 -> 133/4
      const _OverScript('Z. Khan', [2, 1, 0, 4, 1, 1]), // 9 -> 142/4
      const _OverScript('S. Afridi', [1, 0, 4, 1, 2, 1], wktIdx: 1, wktType: WicketType.caught, next: 'M. Nawaz'), // 9 -> 151/5
      const _OverScript('H. Ali', [2, 4, 1, 0, 2, 1]), // 10 -> 161/5
      const _OverScript('A. Jamal', [1, 0, 6, 1, 1, 0], wktIdx: 5, wktType: WicketType.bowled, next: 'M. Amir'), // 9 -> 170/6
      const _OverScript('S. Afridi', [1, 2, 4, 1, 1, 0]), // 9 -> 179/6
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

  /// Generates 100 legal ball events for Innings 2 that naturally derive:
  /// - Total: 142/3 in 16.4 overs
  /// - Babar R. (striker) 58 (41)
  /// - Over 17 (H. Rauf): 1, •, 4, W (Fakhar Z. c Rizwan -> Shan M. in)
  /// - H. Rauf figures: 3.4-0-31-1
  static List<BallEvent> events() {
    final baseTime = DateTime(2026, 11, 21, 19, 10);
    final list = <BallEvent>[...innings1Events()];
    var seq = list.length + 1;

    String striker = 'Babar R.';
    String nonStriker = 'Saim A.';
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
      final event = BallEvent(
        id: 'demo-ball-$seq',
        matchId: demoMatchId,
        inningsNumber: 2,
        sequenceNumber: seq,
        striker: striker,
        nonStriker: nonStriker,
        bowler: bowler,
        runsOffBat: runs,
        extraType: extra,
        extraRuns: extraRuns,
        isWicket: wicket,
        wicketType: wicketType,
        dismissedBatter: wicket ? striker : null,
        fielder: fielder,
        nextBatter: nextBatter,
        synced: true,
        createdAt: baseTime.add(Duration(seconds: seq * 25)),
      );
      list.add(event);
      seq++;

      if (wicket && nextBatter != null) {
        striker = nextBatter;
      }
      final running = event.runningRuns;
      if (running.isOdd) {
        final t = striker;
        striker = nonStriker;
        nonStriker = t;
      }
      if (extra.isLegalDelivery) {
        legalInOver++;
        if (legalInOver == 6) {
          legalInOver = 0;
          final t = striker;
          striker = nonStriker;
          nonStriker = t;
        }
      }
    }

    // Build 16 completed overs (96 legal balls) totaling 137/2, then over 17 (4 balls) = 5 runs + 1 wicket -> 142/3.
    // Bowlers: M. Amir (4 ov, 32-1), N. Shah (4 ov, 34-1), S. Khan (4 ov, 32-0), I. Wasim (1 ov, 13-0), H. Rauf (3.4 ov, 31-1)
    // H. Rauf bowls overs 4, 10, 15 (26 runs in 3 overs) + over 17 (5 runs, 1 wkt) = 3.4-0-31-1.
    final overScripts = <_OverScript>[
      const _OverScript('M. Amir', [1, 0, 4, 0, 1, 2]), // Ov 1: 8
      const _OverScript('N. Shah', [0, 4, 1, 2, 0, 1]), // Ov 2: 8 -> 16
      const _OverScript('M. Amir', [2, 0, 4, 1, 0, 2]), // Ov 3: 9 -> 25
      const _OverScript('H. Rauf', [1, 4, 0, 1, 2, 1]), // Ov 4: 9 (Rauf 1-0-9-0) -> 34
      const _OverScript('S. Khan', [1, 2, 0, 4, 1, 1]), // Ov 5: 9 -> 43
      const _OverScript('N. Shah', [0, 1, 0, 4, 1, 2], wktIdx: 2, wktType: WicketType.bowled, next: 'Fakhar Z.'), // Ov 6: 8, 1w -> 51/1
      const _OverScript('S. Khan', [1, 1, 2, 0, 4, 1]), // Ov 7: 9 -> 60/1
      const _OverScript('M. Amir', [0, 4, 1, 0, 1, 1]), // Ov 8: 7 -> 67/1
      const _OverScript('S. Khan', [2, 1, 4, 0, 1, 0]), // Ov 9: 8 -> 75/1
      const _OverScript('H. Rauf', [0, 2, 1, 4, 1, 0]), // Ov 10: 8 (Rauf 2-0-17-0) -> 83/1
      const _OverScript('N. Shah', [1, 4, 2, 1, 0, 1]), // Ov 11: 9 -> 92/1
      const _OverScript('S. Khan', [1, 0, 2, 1, 1, 1]), // Ov 12: 6 -> 98/1
      const _OverScript('M. Amir', [4, 0, 1, 0, 2, 1], wktIdx: 3, wktType: WicketType.lbw, next: 'Shan M.'), // Ov 13: 8, 1w -> 106/2
      const _OverScript('I. Wasim', [2, 4, 1, 2, 4, 0]), // Ov 14: 13 -> 119/2
      const _OverScript('H. Rauf', [1, 0, 2, 1, 4, 1]), // Ov 15: 9 (Rauf 3-0-26-0) -> 128/2
      const _OverScript('N. Shah', [1, 2, 1, 4, 1, 0]), // Ov 16: 9 -> 137/2
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

    // Over 17 (in progress, H. Rauf): 1, •, 4, W -> 5 runs, 1 wkt -> 142/3 (16.4 ov), Rauf 3.4-0-31-1
    addBall(bowler: 'H. Rauf', runs: 1);
    addBall(bowler: 'H. Rauf', runs: 0);
    addBall(bowler: 'H. Rauf', runs: 4);
    addBall(
      bowler: 'H. Rauf',
      runs: 0,
      wicket: true,
      wicketType: WicketType.caught,
      fielder: 'Rizwan',
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

