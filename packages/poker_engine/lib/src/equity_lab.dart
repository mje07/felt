import 'dart:math';
import 'dart:typed_data';

import 'card.dart';
import 'evaluator.dart';
import 'ranges/weighted_range.dart';

/// Result of [rangeVsRange].
class RangeEquity {
  RangeEquity({
    required this.equity,
    required this.handEquity,
    required this.exact,
    required this.runouts,
  });

  /// Each range's share of the pot (sums to 1).
  final List<double> equity;

  /// Per range, per combo index: that hand's equity against the other
  /// range(s) (NaN for combos not in the range or blocked by the board).
  final List<Float64List> handEquity;

  /// Whether every runout was enumerated (otherwise sampled).
  final bool exact;
  final int runouts;
}

/// Equity of 2–4 [ranges] on [board] (0, 3, 4 or 5 cards).
///
/// Heads-up it enumerates every runout when there are at most
/// [maxExactRunouts] (river, turn and flop), comparing whole ranges per
/// runout with card-removal correction, so per-hand equities are exact.
/// Preflop, or with 3–4 ranges, it samples.
RangeEquity rangeVsRange(
  List<WeightedRange> ranges,
  List<int> board, {
  List<int> dead = const [],
  int maxExactRunouts = 1200,
  int samples = 60000,
  Random? rng,
}) {
  assert(ranges.length >= 2 && ranges.length <= 4);
  final r = rng ?? Random(1);
  final blocked = [...board, ...dead];
  final rs = [for (final x in ranges) x.removeDead(blocked)];
  final need = 5 - board.length;
  final deck = [for (var c = 0; c < 52; c++) if (!blocked.contains(c)) c];
  final runoutCount = _choose(deck.length, need);
  if (ranges.length == 2 && runoutCount <= maxExactRunouts) {
    return _headsUpExact(rs[0], rs[1], board, deck, need);
  }
  return _sampled(rs, board, deck, need, samples, r);
}

int _choose(int n, int k) {
  var out = 1;
  for (var i = 0; i < k; i++) {
    out = out * (n - i) ~/ (i + 1);
  }
  return out;
}

RangeEquity _headsUpExact(WeightedRange h, WeightedRange v, List<int> board, List<int> deck, int need) {
  final heroWin = Float64List(1326), heroTot = Float64List(1326);
  final vilWin = Float64List(1326), vilTot = Float64List(1326);
  var runouts = 0;
  final full = List<int>.filled(7, 0);
  final strength = Int32List(1326);
  final order = <int>[];

  void runout(List<int> five) {
    runouts++;
    var mask = 0;
    for (final c in five) {
      mask |= 1 << c;
    }
    order.clear();
    for (var i = 0; i < 1326; i++) {
      if (h.w[i] <= 0 && v.w[i] <= 0) continue;
      final (a, b) = comboCards[i];
      if ((mask >> a) & 1 == 1 || (mask >> b) & 1 == 1) continue;
      full[0] = a;
      full[1] = b;
      for (var k = 0; k < 5; k++) {
        full[2 + k] = five[k];
      }
      strength[i] = evaluate(full);
      order.add(i);
    }
    order.sort((x, y) => strength[x].compareTo(strength[y]));
    _accumulate(order, strength, h.w, v.w, heroWin, heroTot);
    _accumulate(order, strength, v.w, h.w, vilWin, vilTot);
  }

  if (need == 0) {
    runout(board);
  } else {
    final five = [...board, ...List.filled(need, 0)];
    void rec(int start, int depth) {
      if (depth == need) {
        runout(five);
        return;
      }
      for (var i = start; i < deck.length; i++) {
        five[board.length + depth] = deck[i];
        rec(i + 1, depth + 1);
      }
    }

    rec(0, 0);
  }

  return _finish([h, v], [heroWin, vilWin], [heroTot, vilTot], true, runouts);
}

/// For every combo of [me] in [order] (sorted by strength), adds its
/// winnings (win + half ties, weighted by [them]) and its total opposing
/// weight, correcting for shared cards.
void _accumulate(List<int> order, Int32List strength, Float32List me, Float32List them,
    Float64List win, Float64List tot) {
  var total = 0.0;
  final cardTotal = Float64List(52);
  for (final i in order) {
    final w = them[i];
    if (w <= 0) continue;
    final (a, b) = comboCards[i];
    total += w;
    cardTotal[a] += w;
    cardTotal[b] += w;
  }
  var below = 0.0;
  final cardBelow = Float64List(52);
  var g = 0;
  while (g < order.length) {
    // Group of equal strength.
    var end = g;
    while (end < order.length && strength[order[end]] == strength[order[g]]) {
      end++;
    }
    var eq = 0.0;
    final cardEq = <int, double>{};
    for (var k = g; k < end; k++) {
      final i = order[k];
      final w = them[i];
      if (w <= 0) continue;
      final (a, b) = comboCards[i];
      eq += w;
      cardEq[a] = (cardEq[a] ?? 0) + w;
      cardEq[b] = (cardEq[b] ?? 0) + w;
    }
    for (var k = g; k < end; k++) {
      final i = order[k];
      if (me[i] <= 0) continue;
      final (a, b) = comboCards[i];
      final self = them[i]; // same two cards: impossible, counted twice below
      final winW = below - cardBelow[a] - cardBelow[b];
      final tieW = eq - (cardEq[a] ?? 0) - (cardEq[b] ?? 0) + self;
      final totW = total - cardTotal[a] - cardTotal[b] + self;
      win[i] += winW + tieW / 2;
      tot[i] += totW;
    }
    for (var k = g; k < end; k++) {
      final i = order[k];
      final w = them[i];
      if (w <= 0) continue;
      final (a, b) = comboCards[i];
      below += w;
      cardBelow[a] += w;
      cardBelow[b] += w;
    }
    g = end;
  }
}

RangeEquity _sampled(List<WeightedRange> rs, List<int> board, List<int> deck, int need, int samples, Random r) {
  final n = rs.length;
  final cum = [for (final x in rs) x.cumulativeWeights()];
  final win = [for (var i = 0; i < n; i++) Float64List(1326)];
  final tot = [for (var i = 0; i < n; i++) Float64List(1326)];
  var boardMask = 0;
  for (final c in board) {
    boardMask |= 1 << c;
  }
  final held = List<int>.filled(n, 0);
  final vals = List<int>.filled(n, 0);
  final full = List<int>.filled(7, 0);
  var done = 0;
  for (var s = 0; s < samples; s++) {
    var used = boardMask;
    var ok = true;
    // Rotate who is drawn first so card removal doesn't favour anyone.
    final first = s % n;
    for (var k = 0; k < n; k++) {
      final p = (first + k) % n;
      final c = WeightedRange.sample(cum[p], r, used);
      if (c < 0) {
        ok = false;
        break;
      }
      held[p] = c;
      final (a, b) = comboCards[c];
      used |= (1 << a) | (1 << b);
    }
    if (!ok) continue;
    final five = [...board];
    while (five.length < 5) {
      final c = deck[r.nextInt(deck.length)];
      if ((used >> c) & 1 == 1) continue;
      used |= 1 << c;
      five.add(c);
    }
    for (var k = 0; k < 5; k++) {
      full[2 + k] = five[k];
    }
    var best = -1;
    for (var p = 0; p < n; p++) {
      final (a, b) = comboCards[held[p]];
      full[0] = a;
      full[1] = b;
      vals[p] = evaluate(full);
      if (vals[p] > best) best = vals[p];
    }
    final winners = vals.where((x) => x == best).length;
    for (var p = 0; p < n; p++) {
      tot[p][held[p]] += 1;
      if (vals[p] == best) win[p][held[p]] += 1 / winners;
    }
    done++;
  }
  return _finish(rs, win, tot, false, done);
}

RangeEquity _finish(List<WeightedRange> rs, List<Float64List> win, List<Float64List> tot, bool exact, int runouts) {
  final hand = <Float64List>[];
  final eq = <double>[];
  for (var p = 0; p < rs.length; p++) {
    final he = Float64List(1326)..fillRange(0, 1326, double.nan);
    var num = 0.0, den = 0.0;
    for (var i = 0; i < 1326; i++) {
      if (rs[p].w[i] <= 0 || tot[p][i] <= 0) continue;
      he[i] = win[p][i] / tot[p][i];
      // Exact mode: tot is the opposing weight; sampled mode: the draw count
      // (draws already follow the weights).
      final w = exact ? rs[p].w[i] : 1.0;
      num += w * win[p][i];
      den += w * tot[p][i];
    }
    hand.add(he);
    eq.add(den > 0 ? num / den : 0);
  }
  final sum = eq.fold(0.0, (a, b) => a + b);
  return RangeEquity(
    equity: [for (final e in eq) sum > 0 ? e / sum : 0],
    handEquity: hand,
    exact: exact,
    runouts: runouts,
  );
}

// ---------------------------------------------------------------------------
// Hand classes on a board (Flopzilla-style).

enum HandClass {
  straightFlush('Straight flush'),
  quads('Quads'),
  fullHouse('Full house'),
  flush('Flush'),
  straight('Straight'),
  set('Set'),
  trips('Trips'),
  twoPair('Two pair'),
  overpair('Overpair'),
  topPairGood('Top pair, good kicker'),
  topPairWeak('Top pair, weak kicker'),
  pocketBelowTop('Pocket pair below top card'),
  middlePair('Middle pair'),
  bottomPair('Bottom pair'),
  aceHigh('Ace high'),
  nothing('No made hand'),
  // Draws (flop and turn only); a hand can have one of these as well as a
  // made-hand class.
  comboDraw('Flush + straight draw'),
  flushDraw('Flush draw'),
  oesd('Open-ended straight draw'),
  gutshot('Gutshot'),
  backdoorFlush('Backdoor flush draw');

  const HandClass(this.label);
  final String label;

  bool get isDraw => index >= HandClass.comboDraw.index;
}

/// The made-hand class of hole cards [a], [b] on [board], plus any draw.
(HandClass made, HandClass? draw) classifyHand(int a, int b, List<int> board) {
  final cat = categoryOf(evaluate([a, b, ...board]));
  final ra = cardRank(a), rb = cardRank(b);
  final boardRanks = [for (final c in board) cardRank(c)]..sort((x, y) => y.compareTo(x));
  final top = boardRanks.first, bottom = boardRanks.last;
  final pocket = ra == rb;
  final pairsA = boardRanks.contains(ra), pairsB = boardRanks.contains(rb);

  HandClass pairClass() {
    if (pocket) {
      if (ra > top) return HandClass.overpair;
      if (ra < bottom) return HandClass.bottomPair;
      return HandClass.pocketBelowTop;
    }
    final paired = pairsA && pairsB ? max(ra, rb) : (pairsA ? ra : (pairsB ? rb : -1));
    if (paired < 0) {
      return ra == 12 || rb == 12 ? HandClass.aceHigh : HandClass.nothing;
    }
    if (paired == top) {
      final kicker = paired == ra ? rb : ra;
      return kicker >= 9 ? HandClass.topPairGood : HandClass.topPairWeak; // J+ kicker
    }
    if (paired == bottom) return HandClass.bottomPair;
    return HandClass.middlePair;
  }

  final made = switch (cat) {
    HandCategory.straightFlush => HandClass.straightFlush,
    HandCategory.quads => HandClass.quads,
    HandCategory.fullHouse => HandClass.fullHouse,
    HandCategory.flush => HandClass.flush,
    HandCategory.straight => HandClass.straight,
    HandCategory.trips =>
      pocket && pairsA ? HandClass.set : (pairsA || pairsB ? HandClass.trips : pairClass()),
    HandCategory.twoPair => pairsA && pairsB && !pocket ? HandClass.twoPair : pairClass(),
    _ => pairClass(),
  };
  return (made, board.length < 5 && made.index > HandClass.straight.index ? _draw(a, b, board) : null);
}

HandClass? _draw(int a, int b, List<int> board) {
  final suits = List<int>.filled(4, 0);
  for (final c in board) {
    suits[cardSuit(c)]++;
  }
  var flushDraw = false, backdoor = false;
  for (final s in {cardSuit(a), cardSuit(b)}) {
    final n = suits[s] + (cardSuit(a) == s ? 1 : 0) + (cardSuit(b) == s ? 1 : 0);
    if (n == 4) flushDraw = true;
    if (n == 3 && board.length == 3) backdoor = true;
  }
  var boardMask = 0;
  for (final c in board) {
    boardMask |= 1 << cardRank(c);
  }
  final all = boardMask | 1 << cardRank(a) | 1 << cardRank(b);
  var completing = 0;
  for (var r = 0; r < 13; r++) {
    if ((all >> r) & 1 == 1) continue;
    if (_straight(all | 1 << r) && !_straight(boardMask | 1 << r)) completing++;
  }
  if (flushDraw && completing > 0) return HandClass.comboDraw;
  if (flushDraw) return HandClass.flushDraw;
  if (completing >= 2) return HandClass.oesd;
  if (completing == 1) return HandClass.gutshot;
  if (backdoor) return HandClass.backdoorFlush;
  return null;
}

bool _straight(int rankMask) {
  final m = rankMask << 1 | ((rankMask >> 12) & 1);
  for (var lo = 0; lo <= 9; lo++) {
    if ((m >> lo) & 0x1F == 0x1F) return true;
  }
  return false;
}

/// How a range breaks down on a board: weighted combos per class (draws
/// counted separately from made hands, so a hand can appear twice).
class ClassBreakdown {
  ClassBreakdown(this.combos, this.total, this.members);

  /// Weighted combo count per class.
  final Map<HandClass, double> combos;

  /// Weighted combos in the range after board removal.
  final double total;

  /// Combo indices per class, for highlighting on a grid.
  final Map<HandClass, List<int>> members;

  double share(HandClass c) => total > 0 ? (combos[c] ?? 0) / total : 0;
}

ClassBreakdown handClassBreakdown(WeightedRange range, List<int> board) {
  assert(board.length >= 3);
  final r = range.removeDead(board);
  final combos = <HandClass, double>{};
  final members = <HandClass, List<int>>{};
  var total = 0.0;
  for (final i in r.live) {
    final (a, b) = comboCards[i];
    final w = r.w[i];
    total += w;
    final (made, draw) = classifyHand(a, b, board);
    for (final c in [made, if (draw != null) draw]) {
      combos[c] = (combos[c] ?? 0) + w;
      (members[c] ??= []).add(i);
    }
  }
  return ClassBreakdown(combos, total, members);
}
