import 'package:poker_engine/poker_engine.dart';
import 'package:test/test.dart';

HandHistory hand(List<DecisionReview> reviews) => HandHistory(
    handNumber: 1, playedAt: DateTime(2024), heroSeat: 0, heroNet: 0, events: const [], summary: '', reviews: reviews);

DecisionReview r(Street street, MistakeKind? kind, Grade grade, double loss) => DecisionReview(
    street: street, taken: 'x', recommended: 'y', grade: grade, explanation: '', kind: kind, lossBb: loss);

void main() {
  test('leaks are grouped by street and mistake, ranked by cost per 100 hands', () {
    final hands = [
      for (var i = 0; i < 4; i++) hand([r(Street.river, MistakeKind.callingWithoutOdds, Grade.mistake, 5)]),
      for (var i = 0; i < 3; i++) hand([r(Street.flop, MistakeKind.missedValue, Grade.inaccuracy, 1)]),
      hand([r(Street.turn, MistakeKind.overplayedWeak, Grade.blunder, 30)]), // only once: not a pattern
      for (var i = 0; i < 12; i++) hand([r(Street.river, null, Grade.best, 0)]),
    ];
    final leaks = findLeaks(hands);
    expect(leaks.map((l) => l.title), ['River: calling without the odds', 'Flop: missed value bets']);
    expect(leaks.first.spots, 4);
    expect(leaks.first.lostBb, 20);
    expect(leaks.first.bbPer100, closeTo(20 / 20 * 100, 1e-9));
  });
}
