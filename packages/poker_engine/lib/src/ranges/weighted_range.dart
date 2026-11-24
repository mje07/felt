import 'dart:math';
import 'dart:typed_data';

import '../bots/preflop_chart.dart';
import '../card.dart';
import '../coach/notation.dart';
import '../coach/ranges.dart';
import '../range_model.dart';

/// The 1326 two-card combos in a fixed order: index `i` holds cards
/// `comboCards[i]` (lower card first). Shared by ranges, the equity lab and
/// the solver.
final List<(int, int)> comboCards = [
  for (var a = 0; a < 52; a++)
    for (var b = a + 1; b < 52; b++) (a, b)
];

final Int16List _comboIndex = () {
  final t = Int16List(52 * 52)..fillRange(0, 52 * 52, -1);
  for (var i = 0; i < comboCards.length; i++) {
    final (a, b) = comboCards[i];
    t[a * 52 + b] = i;
    t[b * 52 + a] = i;
  }
  return t;
}();

/// Index (0..1325) of the combo holding cards [a] and [b].
int comboIndex(int a, int b) => _comboIndex[a * 52 + b];

/// Grid cell (see [startingHandIndex]) for each combo index.
final Uint8List comboCell = Uint8List.fromList([
  for (final (a, b) in comboCards) startingHandIndex(a, b),
]);

/// Combo indices in each of the 169 grid cells.
final List<List<int>> cellCombos = () {
  final out = List.generate(169, (_) => <int>[]);
  for (var i = 0; i < comboCards.length; i++) {
    out[comboCell[i]].add(i);
  }
  return out;
}();

/// A range with a weight (0..1) on each of the 1326 combos, as used by the
/// equity lab and the solver. A weight of 0.5 means "this hand half the time".
class WeightedRange {
  WeightedRange([Float32List? weights]) : w = weights ?? Float32List(1326);

  final Float32List w;

  /// Every combo at full weight.
  factory WeightedRange.full() => WeightedRange(Float32List(1326)..fillRange(0, 1326, 1));

  /// Cells (grid indices) at [weight].
  factory WeightedRange.cells(Iterable<int> cells, [double weight = 1]) {
    final r = WeightedRange();
    for (final c in cells) {
      for (final i in cellCombos[c]) {
        r.w[i] = weight;
      }
    }
    return r;
  }

  /// From range notation such as "22+, A2s+, KTo+".
  factory WeightedRange.fromNotation(String text) => WeightedRange.cells(parseRange(text));

  /// The hands a chart plays (raises and calls by default).
  factory WeightedRange.fromChart(RangeChart chart, {bool raise = true, bool call = true}) =>
      WeightedRange.cells({if (raise) ...chart.raise, if (call) ...chart.call});

  /// The strongest [width] of hands by preflop strength.
  factory WeightedRange.fromWidth(double width) {
    final r = WeightedRange();
    for (final c in preflopRange(width)) {
      r.w[comboIndex(comboA(c), comboB(c))] = 1;
    }
    return r;
  }

  WeightedRange copy() => WeightedRange(Float32List.fromList(w));

  double operator [](int combo) => w[combo];
  void operator []=(int combo, double v) => w[combo] = v;

  /// Sets every combo in grid [cell] to [weight].
  void setCell(int cell, double weight) {
    for (final i in cellCombos[cell]) {
      w[i] = weight;
    }
  }

  /// Average weight per grid cell (169 values).
  List<double> gridWeights() => [
        for (final combos in cellCombos) combos.fold(0.0, (s, i) => s + w[i]) / combos.length,
      ];

  /// A copy with every combo that uses one of [cards] removed.
  WeightedRange removeDead(Iterable<int> cards) {
    final out = copy();
    var mask = 0;
    for (final c in cards) {
      mask |= 1 << c;
    }
    for (var i = 0; i < 1326; i++) {
      final (a, b) = comboCards[i];
      if ((mask >> a) & 1 == 1 || (mask >> b) & 1 == 1) out.w[i] = 0;
    }
    return out;
  }

  /// Sum of weights: the number of combos in the range.
  double get combos => w.fold(0.0, (s, x) => s + x);

  /// Share of all 1326 combos.
  double get fraction => combos / 1326;

  bool get isEmpty => combos <= 0;

  /// Combo indices with a positive weight.
  Iterable<int> get live sync* {
    for (var i = 0; i < 1326; i++) {
      if (w[i] > 0) yield i;
    }
  }

  /// Notation for the cells at least half in the range, strongest first.
  String toNotation() {
    final g = gridWeights();
    final cells = [for (var i = 0; i < 169; i++) if (g[i] >= 0.5) i]
      ..sort((a, b) => preflopPercentileOf(a).compareTo(preflopPercentileOf(b)));
    return cells.map(startingHandName).join(', ');
  }

  /// Draws a combo index proportionally to weight, avoiding [usedMask]
  /// cards; -1 if nothing is available. [cumulative] comes from [cumulativeWeights].
  static int sample(Float64List cumulative, Random rng, int usedMask) {
    final total = cumulative.last;
    if (total <= 0) return -1;
    for (var t = 0; t < 64; t++) {
      final x = rng.nextDouble() * total;
      var lo = 0, hi = cumulative.length - 1;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (cumulative[mid] > x) {
          hi = mid;
        } else {
          lo = mid + 1;
        }
      }
      final (a, b) = comboCards[lo];
      if ((usedMask >> a) & 1 == 0 && (usedMask >> b) & 1 == 0) return lo;
    }
    return -1;
  }

  /// Running totals of the weights, for [sample].
  Float64List cumulativeWeights() {
    final out = Float64List(1326);
    var s = 0.0;
    for (var i = 0; i < 1326; i++) {
      s += w[i];
      out[i] = s;
    }
    return out;
  }
}

/// "AhKd" style label for a combo index.
String comboLabel(int combo) {
  final (a, b) = comboCards[combo];
  return cardRank(a) >= cardRank(b) ? '${cardToString(a)}${cardToString(b)}' : '${cardToString(b)}${cardToString(a)}';
}
