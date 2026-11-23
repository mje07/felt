import '../card.dart';
import 'preflop_table.g.dart';

/// Index into the 13x13 starting-hand grid.
/// Row = higher rank, col = lower rank. Suited hands live at [hi*13+lo],
/// offsuit at [lo*13+hi], pairs on the diagonal.
int startingHandIndex(int c1, int c2) {
  final r1 = cardRank(c1), r2 = cardRank(c2);
  final hi = r1 > r2 ? r1 : r2, lo = r1 > r2 ? r2 : r1;
  final suited = cardSuit(c1) == cardSuit(c2);
  return suited ? hi * 13 + lo : lo * 13 + hi;
}

/// e.g. "AKs", "T9o", "77".
String startingHandName(int index) {
  final row = index ~/ 13, col = index % 13;
  if (row == col) return '${rankChars[row]}${rankChars[row]}';
  if (row > col) return '${rankChars[row]}${rankChars[col]}s';
  return '${rankChars[col]}${rankChars[row]}o';
}

/// Heads-up all-in equity vs a random hand (0..1).
double preflopEquity(int c1, int c2) =>
    preflopEquityTable[startingHandIndex(c1, c2)];

/// Fraction of all 1326 starting combos at least as strong as this hand.
/// 0.005 = AA (top half-percent), 1.0 = 72o.
double preflopPercentile(int c1, int c2) =>
    preflopPercentileTable[startingHandIndex(c1, c2)];
