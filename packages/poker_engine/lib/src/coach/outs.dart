import '../evaluator.dart';

/// Unseen cards that would give a straight or better, for a hand that
/// currently has less than a straight. Empty on the river, or if the hand
/// is already a straight or better.
List<int> outsToStraightOrBetter(List<int> hole, List<int> board) {
  if (board.length < 3 || board.length > 4) return const [];
  final cards = [...hole, ...board];
  if (categoryOf(evaluate(cards)).index >= HandCategory.straight.index) return const [];
  final seen = cards.toSet();
  return [
    for (var c = 0; c < 52; c++)
      if (!seen.contains(c) && categoryOf(evaluate([...cards, c])).index >= HandCategory.straight.index) c
  ];
}

/// Exact chance to hit one of [outs] by the river: from the flop (two cards
/// to come, 47 unseen) or the turn (one card, 46 unseen).
double hitChanceByRiver(int outs, int boardLength) {
  if (boardLength == 4) return outs / 46;
  return 1 - (47 - outs) * (46 - outs) / (47 * 46);
}
