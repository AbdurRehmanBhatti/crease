import 'package:crease/data/sample_match.dart';
import 'package:crease/domain/cricket_engine.dart';
import 'package:crease/domain/match_insights.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MatchInsights derivation', () {
    test('derives partnerships, worm points, and scoring breakdown cleanly', () {
      final derived = CricketEngine.derive(
        SampleMatchSeed.config(),
        SampleMatchSeed.events(),
      );
      final inn = derived.activeInnings;

      final partnerships = MatchInsights.partnerships(inn);
      expect(partnerships.length, 3); // 3 wickets fell -> 3 completed stands
      expect(
        partnerships.fold<int>(0, (sum, p) => sum + p.runs),
        inn.totalRuns,
      );

      final worm = MatchInsights.wormPoints(inn);
      expect(worm.length, 17);
      expect(worm.last.cumulativeRuns, 142);

      final breakdown = MatchInsights.breakdown(inn);
      expect(breakdown.legalBalls, 100);
      expect(breakdown.dotPercent, greaterThan(0));
      expect(breakdown.boundaryRunPercent, greaterThan(0));
    });
  });
}
