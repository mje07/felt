import '../card.dart';

/// Grid index for a starting hand by ranks (0..12) and suitedness.
/// Matches `startingHandIndex`: suited at hi*13+lo, offsuit at lo*13+hi.
int gridIndex(int r1, int r2, {required bool suited}) {
  final hi = r1 > r2 ? r1 : r2, lo = r1 > r2 ? r2 : r1;
  if (hi == lo) return hi * 13 + hi;
  return suited ? hi * 13 + lo : lo * 13 + hi;
}

/// Number of card combinations for a grid cell (6 pairs, 4 suited, 12 offsuit).
int combosAt(int index) {
  final row = index ~/ 13, col = index % 13;
  if (row == col) return 6;
  return row > col ? 4 : 12;
}

int _rank(String c) {
  final r = rankChars.indexOf(c.toUpperCase());
  if (r < 0) throw FormatException('Bad rank "$c"');
  return r;
}

/// Parses standard range notation into grid indices, e.g.
/// `"77+, A2s+, KTo+, T9s, QJs-Q9s, 99-55, AK"`.
Set<int> parseRange(String text) {
  final out = <int>{};
  for (var raw in text.split(',')) {
    final t = raw.trim();
    if (t.isEmpty) continue;
    if (t.contains('-')) {
      final parts = t.split('-').map((s) => s.trim()).toList();
      if (parts.length != 2) throw FormatException('Bad range "$t"');
      final a = _hand(parts[0]), b = _hand(parts[1]);
      if (a.isPair && b.isPair) {
        final lo = a.hi < b.hi ? a.hi : b.hi, hi = a.hi > b.hi ? a.hi : b.hi;
        for (var r = lo; r <= hi; r++) {
          out.add(gridIndex(r, r, suited: false));
        }
      } else {
        if (a.hi != b.hi || a.suited != b.suited) throw FormatException('Bad range "$t"');
        final lo = a.lo < b.lo ? a.lo : b.lo, hi = a.lo > b.lo ? a.lo : b.lo;
        for (var k = lo; k <= hi; k++) {
          out.addAll(_both(a.hi, k, a.suited));
        }
      }
      continue;
    }
    final plus = t.endsWith('+');
    final h = _hand(plus ? t.substring(0, t.length - 1) : t);
    if (h.isPair) {
      for (var r = h.hi; r <= (plus ? 12 : h.hi); r++) {
        out.add(gridIndex(r, r, suited: false));
      }
    } else {
      for (var k = h.lo; k <= (plus ? h.hi - 1 : h.lo); k++) {
        out.addAll(_both(h.hi, k, h.suited));
      }
    }
  }
  return out;
}

/// suited: true / false / null (both).
Iterable<int> _both(int hi, int lo, bool? suited) sync* {
  if (suited != false) yield gridIndex(hi, lo, suited: true);
  if (suited != true) yield gridIndex(hi, lo, suited: false);
}

class _H {
  _H(this.hi, this.lo, this.suited);
  final int hi, lo;
  final bool? suited;
  bool get isPair => hi == lo;
}

_H _hand(String s) {
  if (s.length < 2 || s.length > 3) throw FormatException('Bad hand "$s"');
  final a = _rank(s[0]), b = _rank(s[1]);
  final hi = a > b ? a : b, lo = a > b ? b : a;
  bool? suited;
  if (s.length == 3) {
    final c = s[2].toLowerCase();
    if (c != 's' && c != 'o') throw FormatException('Bad hand "$s"');
    suited = c == 's';
  }
  return _H(hi, lo, suited);
}

/// Total combos in a range, and as a fraction of all 1326.
int rangeCombos(Set<int> range) => range.fold(0, (a, i) => a + combosAt(i));
double rangeFraction(Set<int> range) => rangeCombos(range) / 1326;
