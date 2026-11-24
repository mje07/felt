import 'dart:math';

import 'bots/preflop_chart.dart';
import 'card.dart';
import 'evaluator.dart';

/// Opponent ranges as explicit lists of two-card combos.
///
/// A combo is packed as `a << 6 | b`. Lists are sampled uniformly, so a
/// range is exactly what the list holds: no rejection sampling, no random
/// hands sneaking into narrow ranges.

int packCombo(int a, int b) => a << 6 | b;
int comboA(int combo) => combo >> 6;
int comboB(int combo) => combo & 63;

/// All 1326 combos, strongest preflop first (by [preflopPercentile]).
final List<int> combosByStrength = () {
  final out = <int>[];
  for (var a = 0; a < 52; a++) {
    for (var b = a + 1; b < 52; b++) {
      out.add(packCombo(a, b));
    }
  }
  out.sort((x, y) => preflopPercentile(comboA(x), comboB(x))
      .compareTo(preflopPercentile(comboA(y), comboB(y))));
  return out;
}();

final List<double> _percentiles = [
  for (final c in combosByStrength) preflopPercentile(comboA(c), comboB(c))
];

/// The strongest [width] of starting hands (1.0 = any two cards), with
/// combos that clash with [dead] cards removed.
List<int> preflopRange(double width, {Iterable<int> dead = const []}) {
  var mask = 0;
  for (final c in dead) {
    mask |= 1 << c;
  }
  // Every combo whose class percentile is within the width.
  var n = combosByStrength.length;
  if (width < 1.0) {
    var lo = 0, hi = combosByStrength.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_percentiles[mid] <= width + 1e-9) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    n = max(lo, 6); // at least one hand class
  }
  return [
    for (var i = 0; i < n; i++)
      if (!_clashes(combosByStrength[i], mask)) combosByStrength[i]
  ];
}

bool _clashes(int combo, int mask) =>
    (mask >> comboA(combo)) & 1 == 1 || (mask >> comboB(combo)) & 1 == 1;

/// Draws a combo from [combos] that avoids the cards in [usedMask], or -1
/// if every combo clashes.
int sampleCombo(List<int> combos, int usedMask, Random rng) {
  if (combos.isEmpty) return -1;
  for (var t = 0; t < 48; t++) {
    final c = combos[rng.nextInt(combos.length)];
    if (!_clashes(c, usedMask)) return c;
  }
  final start = rng.nextInt(combos.length);
  for (var i = 0; i < combos.length; i++) {
    final c = combos[(start + i) % combos.length];
    if (!_clashes(c, usedMask)) return c;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Board-aware narrowing.

/// Approximate outs for a flush or straight draw (0 on the river, or when
/// the hand is already a straight or better). Only draws that use a hole
/// card count.
int drawOuts(int a, int b, List<int> board) {
  if (board.length < 3 || board.length >= 5) return 0;
  var outs = 0;
  // Flush draw: four of a suit, at least one from the hole.
  final suits = List<int>.filled(4, 0);
  for (final c in board) {
    suits[cardSuit(c)]++;
  }
  for (final s in {cardSuit(a), cardSuit(b)}) {
    final count = suits[s] + (cardSuit(a) == s ? 1 : 0) + (cardSuit(b) == s ? 1 : 0);
    if (count == 4) outs += 9;
    if (count >= 5) return 0; // already a flush
  }
  // Straight draw: ranks that would complete a straight using a hole card.
  final boardMask = _rankMask(board);
  final allMask = boardMask | 1 << cardRank(a) | 1 << cardRank(b);
  if (_isStraight(allMask)) return 0;
  var completing = 0;
  for (var r = 0; r < 13; r++) {
    if ((allMask >> r) & 1 == 1) continue;
    if (_isStraight(allMask | 1 << r) && !_isStraight(boardMask | 1 << r)) completing++;
  }
  outs += completing >= 2 ? 8 : completing * 4;
  return min(outs, 15);
}

int _rankMask(List<int> cards) {
  var m = 0;
  for (final c in cards) {
    m |= 1 << cardRank(c);
  }
  return m;
}

bool _isStraight(int rankMask) {
  // Bit 0 = deuce … bit 12 = ace; the ace also plays low.
  final m = rankMask << 1 | ((rankMask >> 12) & 1);
  for (var lo = 0; lo <= 9; lo++) {
    if ((m >> lo) & 0x1F == 0x1F) return true;
  }
  return false;
}

/// What a player did, for narrowing their range.
enum RangeAction { bet, raise, call, check }

/// Scores each combo on [board]: its made-hand rank within [combos] (0..1)
/// plus a bonus for draws, so strong draws rank with medium made hands.
List<(int, double, int)> _scored(List<int> combos, List<int> board) {
  final values = <(int, int, int)>[];
  for (final c in combos) {
    final a = comboA(c), b = comboB(c);
    values.add((c, evaluate([a, b, ...board]), drawOuts(a, b, board)));
  }
  values.sort((x, y) => x.$2.compareTo(y.$2));
  final n = values.length;
  final drawWeight = board.length == 3 ? 0.022 : 0.012;
  final out = <(int, double, int)>[];
  for (var i = 0; i < n; i++) {
    final (c, _, outs) = values[i];
    out.add((c, (n == 1 ? 1.0 : i / (n - 1)) + outs * drawWeight, outs));
  }
  out.sort((x, y) => y.$2.compareTo(x.$2)); // strongest first
  return out;
}

/// Narrows [combos] after a player took [action] on [board].
///
/// Bets keep the strongest 55% (raises 40%) plus a bluff slice of draws
/// and a little air. Calls drop the very top (it would have raised) and
/// the bottom. Checks drop the very top (it would usually have bet).
/// [aggression] scales for how often this player bets compared with a
/// typical player (see `TableReads`): 2.0 means twice as often, so their
/// betting range is wider and holds more bluffs.
List<int> narrowRange(List<int> combos, List<int> board, RangeAction action, {double aggression = 1.0}) {
  final agg = aggression.clamp(0.3, 3.0);
  if (combos.length <= 6 || board.length < 3) return combos;
  final scored = _scored(combos, board);
  final n = scored.length;
  List<int> take(Iterable<(int, double, int)> xs) => [for (final x in xs) x.$1];

  switch (action) {
    case RangeAction.bet:
    case RangeAction.raise:
      final valueShare = (action == RangeAction.raise ? 0.4 : 0.55) * agg.clamp(0.75, 1.5);
      final keep = max(6, (n * min(0.9, valueShare)).ceil());
      final value = scored.take(keep);
      final rest = scored.skip(keep).toList();
      final draws = rest.where((x) => x.$3 > 0).toList()
        ..sort((x, y) => y.$3.compareTo(x.$3));
      // Roughly balanced: about one bluff for every two value hands. Draws
      // first; on the river (no draws) the bluffs are air.
      final river = board.length == 5;
      final bluffs = draws.take((keep * 0.3 * agg).round());
      final air = rest.reversed.where((x) => x.$3 == 0).take((keep * (river ? 0.4 : 0.12) * agg).round());
      return take([...value, ...bluffs, ...air]);
    case RangeAction.call:
      final top = (n * 0.08).floor();
      final keep = max(6, (n * 0.65).ceil());
      final core = scored.sublist(top, keep.clamp(top, n));
      final draws = scored.skip(keep).where((x) => x.$3 >= 8);
      return take([...core, ...draws]);
    case RangeAction.check:
      final top = (n * 0.06).floor();
      return take(scored.skip(top));
  }
}

/// The part of [combos] that continues against a bet: the strongest
/// [fraction] on [board] by made hand and draws.
List<int> continuingRange(List<int> combos, List<int> board, double fraction) {
  if (combos.length <= 6) return combos;
  final scored = _scored(combos, board);
  return [for (final x in scored.take(max(6, (scored.length * fraction).ceil()))) x.$1];
}
