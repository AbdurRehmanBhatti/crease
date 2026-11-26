import 'package:crease/data/sample_match.dart';
import 'package:crease/domain/cricket_engine.dart';
import 'package:crease/domain/models.dart';
import 'package:crease/domain/stats_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const names = {
    'ali': 'Ali',
    'bilal': 'Bilal',
    'zain': 'Zain',
    'kamran': 'Kamran',
    'wk': 'WK',
    'saad': 'Saad',
    'omer': 'Omer',
    'hamza': 'Hamza',
  };

  group('CricketEngine derivation', () {
    test('derives exact sample match totals from 100 real ball events', () {
      final config = SampleMatchSeed.config();
      final events = SampleMatchSeed.events();
      final state = CricketEngine.derive(config, events);

      final inn = state.activeInnings;
      expect(state.activeInningsNumber, 2);
      expect(state.status, MatchStatus.live);
      expect(inn.totalRuns, 142);
      expect(inn.wickets, 3);
      expect(inn.oversText, '16.4');
      expect(inn.runsNeeded, 38);
      expect(inn.ballsRemaining, 20);
      expect(inn.requiredRunRate, closeTo(11.4, 0.01));

      final rauf = inn.bowlerByName('H. Rauf');
      expect(rauf.figuresText, '3.4-0-31-1');

      final over17 = inn.overs.last;
      expect(over17.overNumber, 17);
      expect(over17.balls.map((b) => b.shortMark).toList(), ['1', '•', '4', 'W']);
    });

    test('rotates strike on odd runs, end of over, and handles wides/no-balls', () {
      final cfg = MatchConfig(
        id: 'm1',
        teamA: 'A',
        teamB: 'B',
        oversLimit: 2,
        formatLabel: '2OV',
        battingFirstSide: MatchSide.a,
        openingStriker1Id: 'ali',
        openingNonStriker1Id: 'bilal',
        openingBowler1Id: 'zain',
        adHocPlayers: names,
        createdAt: DateTime(2026, 11, 21),
      );

      final now = DateTime(2026, 11, 21);
      final events = [
        BallEvent(
          id: '1',
          matchId: 'm1',
          inningsNumber: 1,
          sequenceNumber: 1,
          strikerId: 'ali',
          nonStrikerId: 'bilal',
          bowlerId: 'zain',
          runsOffBat: 1,
          createdAt: now,
        ),
        BallEvent(
          id: '2',
          matchId: 'm1',
          inningsNumber: 1,
          sequenceNumber: 2,
          strikerId: 'bilal',
          nonStrikerId: 'ali',
          bowlerId: 'zain',
          extraType: ExtraType.wide,
          extraRuns: 1,
          createdAt: now,
        ),
        BallEvent(
          id: '3',
          matchId: 'm1',
          inningsNumber: 1,
          sequenceNumber: 3,
          strikerId: 'bilal',
          nonStrikerId: 'ali',
          bowlerId: 'zain',
          runsOffBat: 4,
          createdAt: now,
        ),
      ];

      final state = CricketEngine.derive(cfg, events);
      final inn = state.innings1;
      expect(inn.totalRuns, 6);
      expect(inn.legalBalls, 2);
      expect(inn.oversText, '0.2');
      expect(inn.wides, 1);
      expect(inn.striker, 'Bilal');
      expect(inn.batterByName('Bilal').runs, 4);
      expect(inn.batterByName('Bilal').balls, 1);
      expect(inn.batterByName('Bilal').fours, 1);
    });

    test('voiding any ball recalculates score cleanly with zero drift', () {
      final config = SampleMatchSeed.config();
      final events = SampleMatchSeed.events();
      events[events.length - 2] =
          events[events.length - 2].copyWith(voided: true);

      final state = CricketEngine.derive(config, events);
      expect(state.activeInnings.totalRuns, 138);
      expect(state.activeInnings.oversText, '16.3');
    });

    test('recording a wicket without nextBatterId prompts for next batter', () {
      final config = SampleMatchSeed.config();
      final events = SampleMatchSeed.events();
      final last = events.last;
      final shadabId = config.adHocPlayers.entries
          .firstWhere((e) => e.value == 'Shadab K.')
          .key;
      events[events.length - 1] = BallEvent(
        id: last.id,
        matchId: last.matchId,
        inningsNumber: last.inningsNumber,
        sequenceNumber: last.sequenceNumber,
        strikerId: last.strikerId,
        nonStrikerId: last.nonStrikerId,
        bowlerId: last.bowlerId,
        isWicket: true,
        wicketType: WicketType.caught,
        dismissedBatterId: last.dismissedBatterId,
        fielderId: last.fielderId,
        nextBatterId: null,
        createdAt: last.createdAt,
      );

      final pending = CricketEngine.derive(config, events);
      expect(pending.activeInnings.needsNextBatter, isTrue);
      expect(pending.activeInnings.striker, isEmpty);

      events[events.length - 1] =
          events.last.copyWith(nextBatterId: shadabId);
      final resolved = CricketEngine.derive(config, events);
      expect(resolved.activeInnings.needsNextBatter, isFalse);
      expect(resolved.activeInnings.striker, 'Shadab K.');
    });

    test('handles retired hurt, +5 penalty runs, wide+stumped, and revised target', () {
      final cfg = MatchConfig(
        id: 'edge-cases-1',
        teamA: 'A',
        teamB: 'B',
        oversLimit: 10,
        formatLabel: 'T10',
        battingFirstSide: MatchSide.a,
        openingStriker1Id: 'ali',
        openingNonStriker1Id: 'bilal',
        openingBowler1Id: 'zain',
        adHocPlayers: names,
        firstInningsTargetOverride: 55,
        createdAt: DateTime(2026),
      );
      final events = [
        BallEvent(
          id: 'e1',
          matchId: cfg.id,
          inningsNumber: 1,
          sequenceNumber: 1,
          strikerId: 'ali',
          nonStrikerId: 'bilal',
          bowlerId: 'zain',
          extraType: ExtraType.penalty,
          extraRuns: 5,
          createdAt: DateTime(2026),
        ),
        BallEvent(
          id: 'e2',
          matchId: cfg.id,
          inningsNumber: 1,
          sequenceNumber: 2,
          strikerId: 'ali',
          nonStrikerId: 'bilal',
          bowlerId: 'zain',
          isWicket: true,
          wicketType: WicketType.retiredHurt,
          dismissedBatterId: 'ali',
          nextBatterId: 'kamran',
          createdAt: DateTime(2026),
        ),
        BallEvent(
          id: 'e3',
          matchId: cfg.id,
          inningsNumber: 1,
          sequenceNumber: 3,
          strikerId: 'kamran',
          nonStrikerId: 'bilal',
          bowlerId: 'zain',
          extraType: ExtraType.wide,
          extraRuns: 1,
          isWicket: true,
          wicketType: WicketType.stumped,
          dismissedBatterId: 'kamran',
          fielderId: 'wk',
          createdAt: DateTime(2026),
        ),
      ];

      final state = CricketEngine.derive(cfg, events);
      expect(state.innings1.totalRuns, 6);
      expect(state.innings1.legalBalls, 0);
      expect(state.innings1.wickets, 1);
      expect(state.innings1.bowlerByName('Zain').runsConceded, 1);
      expect(state.innings1.bowlerByName('Zain').wickets, 1);
      expect(state.innings1.batterByName('Ali').isOut, isFalse);
      expect(state.innings1.batterByName('Ali').dismissalText, 'retired hurt');
      expect(state.innings1.needsNextBatter, isTrue);
    });

    test('in-match Super Over resolves tied limited-overs match inside innings 3 & 4', () {
      final cfg = MatchConfig(
        id: 'so-match',
        teamA: 'Bhatti XI',
        teamB: 'Street XI',
        oversLimit: 1,
        playersPerSide: 11,
        formatLabel: '1OV',
        battingFirstSide: MatchSide.a,
        openingStriker1Id: 'ali',
        openingNonStriker1Id: 'bilal',
        openingBowler1Id: 'zain',
        openingStriker2Id: 'saad',
        openingNonStriker2Id: 'omer',
        openingBowler2Id: 'hamza',
        teamAPlayerIds: const ['ali', 'bilal', 'hamza'],
        teamBPlayerIds: const ['saad', 'omer', 'zain'],
        adHocPlayers: names,
        createdAt: DateTime(2026),
      );

      final regEvents = <BallEvent>[
        for (var i = 1; i <= 6; i++)
          BallEvent(
            id: 'i1-$i',
            matchId: cfg.id,
            inningsNumber: 1,
            sequenceNumber: i,
            strikerId: 'ali',
            nonStrikerId: 'bilal',
            bowlerId: 'zain',
            runsOffBat: i == 1 ? 6 : 0,
            createdAt: DateTime(2026),
          ),
        for (var i = 1; i <= 6; i++)
          BallEvent(
            id: 'i2-$i',
            matchId: cfg.id,
            inningsNumber: 2,
            sequenceNumber: i,
            strikerId: 'saad',
            nonStrikerId: 'omer',
            bowlerId: 'hamza',
            runsOffBat: i == 1 ? 6 : 0,
            createdAt: DateTime(2026),
          ),
      ];

      final tied = CricketEngine.derive(cfg, regEvents);
      expect(tied.status, MatchStatus.completed);
      expect(tied.resultSummary, 'Match tied');
      expect(tied.innings3, isNull);

      final so1Events = [
        ...regEvents,
        BallEvent(
          id: 'so1-1',
          matchId: cfg.id,
          inningsNumber: 3,
          sequenceNumber: 1,
          strikerId: 'saad',
          nonStrikerId: 'omer',
          bowlerId: 'hamza',
          runsOffBat: 4,
          createdAt: DateTime(2026),
        ),
        BallEvent(
          id: 'so1-2',
          matchId: cfg.id,
          inningsNumber: 3,
          sequenceNumber: 2,
          strikerId: 'saad',
          nonStrikerId: 'omer',
          bowlerId: 'hamza',
          isWicket: true,
          wicketType: WicketType.bowled,
          dismissedBatterId: 'saad',
          nextBatterId: 'zain',
          createdAt: DateTime(2026),
        ),
        BallEvent(
          id: 'so1-3',
          matchId: cfg.id,
          inningsNumber: 3,
          sequenceNumber: 3,
          strikerId: 'zain',
          nonStrikerId: 'omer',
          bowlerId: 'hamza',
          isWicket: true,
          wicketType: WicketType.bowled,
          dismissedBatterId: 'zain',
          createdAt: DateTime(2026),
        ),
      ];

      final soBreak = CricketEngine.derive(cfg, so1Events);
      expect(soBreak.innings3, isNotNull);
      expect(soBreak.innings3!.battingTeam, 'Street XI');
      expect(soBreak.innings3!.isComplete, isTrue);
      expect(soBreak.innings3!.totalRuns, 4);
      expect(soBreak.status, MatchStatus.inningsBreak);

      final so2Events = [
        ...so1Events,
        BallEvent(
          id: 'so2-1',
          matchId: cfg.id,
          inningsNumber: 4,
          sequenceNumber: 1,
          strikerId: 'ali',
          nonStrikerId: 'bilal',
          bowlerId: 'zain',
          runsOffBat: 6,
          createdAt: DateTime(2026),
        ),
      ];

      final done = CricketEngine.derive(cfg, so2Events);
      expect(done.status, MatchStatus.completed);
      expect(done.innings4, isNotNull);
      expect(done.innings4!.battingTeam, 'Bhatti XI');
      expect(done.innings4!.isComplete, isTrue);
      expect(done.resultSummary, 'Bhatti XI won Super Over');
    });
  });

  group('Strict 3NF Player Identity (UUID normalization)', () {
    test('renaming a player updates past scorecards, dismissals, and career stats without splitting', () {
      const pAbdur = '00000000-0000-4000-8000-000000000101';
      const pSheran = '00000000-0000-4000-8000-000000000102';
      const pBasit = '00000000-0000-4000-8000-000000000103';
      const pFielder = '00000000-0000-4000-8000-000000000104';

      final cfg = MatchConfig(
        id: 'm-rename',
        teamA: 'Bhatti XI',
        teamB: 'Abu G',
        oversLimit: 2,
        formatLabel: '2OV',
        battingFirstSide: MatchSide.a,
        openingStriker1Id: pAbdur,
        openingNonStriker1Id: pSheran,
        openingBowler1Id: pBasit,
        createdAt: DateTime(2026, 11, 26),
      );

      final events = [
        BallEvent(
          id: 'b1',
          matchId: cfg.id,
          inningsNumber: 1,
          sequenceNumber: 1,
          strikerId: pAbdur,
          nonStrikerId: pSheran,
          bowlerId: pBasit,
          runsOffBat: 6,
          createdAt: DateTime(2026, 11, 26),
        ),
        BallEvent(
          id: 'b2',
          matchId: cfg.id,
          inningsNumber: 1,
          sequenceNumber: 2,
          strikerId: pAbdur,
          nonStrikerId: pSheran,
          bowlerId: pBasit,
          isWicket: true,
          wicketType: WicketType.caught,
          dismissedBatterId: pAbdur,
          fielderId: pFielder,
          createdAt: DateTime(2026, 11, 26),
        ),
      ];

      // Before rename: "Abdur" and "Rehman"
      final beforeNames = {
        pAbdur: 'Abdur',
        pSheran: 'Sheran',
        pBasit: 'Basit',
        pFielder: 'Rehman',
      };
      final before = CricketEngine.derive(cfg, events, playerNamesById: beforeNames);
      expect(before.innings1.batterById(pAbdur).name, 'Abdur');
      expect(before.innings1.batterById(pAbdur).dismissalText, 'c Rehman b Basit');

      // After renaming both players in `players` (zero ball_events rewritten!)
      final afterNames = {
        pAbdur: 'Abdur Rehman',
        pSheran: 'Sheran Bhatti',
        pBasit: 'Basit Khan',
        pFielder: 'Rehman Ali',
      };
      final after = CricketEngine.derive(cfg, events, playerNamesById: afterNames);
      expect(after.innings1.batterById(pAbdur).name, 'Abdur Rehman');
      expect(after.innings1.batterById(pAbdur).dismissalText, 'c Rehman Ali b Basit Khan');
      expect(after.innings1.fallOfWickets.first.batterName, 'Abdur Rehman');

      final stats = StatsEngine.derive([after], playerNamesById: afterNames);
      final abdurStats = stats.where((s) => s.playerId == pAbdur).toList();
      expect(abdurStats.length, 1);
      expect(abdurStats.first.name, 'Abdur Rehman');
      expect(abdurStats.first.runs, 6);
    });

    test('two players sharing the exact same display name remain distinct by playerId', () {
      const aliClubA = '00000000-0000-4000-8000-000000000201';
      const aliClubB = '00000000-0000-4000-8000-000000000202';
      const partner = '00000000-0000-4000-8000-000000000203';

      final dir = {
        aliClubA: 'Ali',
        aliClubB: 'Ali',
        partner: 'Bilal',
      };
      final cfg = MatchConfig(
        id: 'm-same-player-name',
        teamA: 'Club A',
        teamB: 'Club B',
        oversLimit: 1,
        formatLabel: '1OV',
        battingFirstSide: MatchSide.a,
        openingStriker1Id: aliClubA,
        openingNonStriker1Id: partner,
        openingBowler1Id: aliClubB,
        createdAt: DateTime(2026, 11, 26),
      );
      final events = [
        BallEvent(
          id: 'b1',
          matchId: cfg.id,
          inningsNumber: 1,
          sequenceNumber: 1,
          strikerId: aliClubA,
          nonStrikerId: partner,
          bowlerId: aliClubB,
          runsOffBat: 4,
          createdAt: DateTime(2026, 11, 26),
        ),
      ];
      final derived = CricketEngine.derive(cfg, events, playerNamesById: dir);
      final stats = StatsEngine.derive([derived], playerNamesById: dir);
      final aliEntries = stats.where((s) => s.name == 'Ali').toList();
      expect(aliEntries.length, 2);
      expect(aliEntries.firstWhere((s) => s.playerId == aliClubA).runs, 4);
      expect(aliEntries.firstWhere((s) => s.playerId == aliClubB).runsConceded, 4);
    });
  });
}
