import 'package:crease/data/sample_match.dart';
import 'package:crease/domain/cricket_engine.dart';
import 'package:crease/domain/stats_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StatsEngine career stats & leaderboards', () {
    test('derives batting, bowling, fielding, and MVP leaderboards from ball log', () {
      final derived = CricketEngine.derive(
        SampleMatchSeed.config(),
        SampleMatchSeed.events(),
      );

      final all = StatsEngine.derive([derived]);
      expect(all, isNotEmpty);

      final topBat = StatsEngine.byRuns(all);
      expect(topBat.first.name, 'Babar R.');
      expect(topBat.first.runs, greaterThan(50));
      expect(topBat.first.fifties, 1);

      final topBowl = StatsEngine.byWickets(all);
      expect(topBowl.any((p) => p.name == 'H. Rauf' && p.wickets == 1), isTrue);

      // M. Rizwan batted in innings 1 AND took the catch on ball 17.4 — unified under one playerId!
      final rizwan = all.firstWhere((p) => p.name == 'M. Rizwan');
      expect(rizwan.fieldingDismissals, 1);
      expect(rizwan.catches, 1);
      expect(rizwan.mvpPoints, greaterThan(8));

      final mvp = StatsEngine.byMvp(all);
      expect(mvp.first.mvpPoints, greaterThanOrEqualTo(mvp.last.mvpPoints));
    });
  });
}
