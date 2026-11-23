import 'dart:typed_data';

import 'card.dart';

/// Hand categories, ordered weakest to strongest.
enum HandCategory {
  highCard('High Card'),
  pair('Pair'),
  twoPair('Two Pair'),
  trips('Three of a Kind'),
  straight('Straight'),
  flush('Flush'),
  fullHouse('Full House'),
  quads('Four of a Kind'),
  straightFlush('Straight Flush');

  const HandCategory(this.label);
  final String label;
}

/// Hand values are ints: `category << 20 | r1 << 16 | r2 << 12 | ... | r5`,
/// where r1..r5 are (rank + 1), or 0 when unused. Larger is better.
int _make(int cat, [int a = -1, int b = -1, int c = -1, int d = -1, int e = -1]) =>
    cat << 20 |
    (a + 1) << 16 |
    (b + 1) << 12 |
    (c + 1) << 8 |
    (d + 1) << 4 |
    (e + 1);

HandCategory categoryOf(int value) => HandCategory.values[value >> 20];

/// Rank (0..12) stored at kicker slot [i] (0..4), or -1.
int kickerRank(int value, int i) => ((value >> (16 - 4 * i)) & 0xF) - 1;

int _bitCount(int x) {
  var n = 0;
  while (x != 0) {
    x &= x - 1;
    n++;
  }
  return n;
}

int _highBit(int x) => x.bitLength - 1;

/// Highest rank of a 5-long run in a 13-bit rank mask, or -1. Handles A-2-3-4-5.
int _straightHigh(int mask) {
  // bit 0 = ace-low, bit r+1 = rank r.
  final ext = (mask << 1) | ((mask >> 12) & 1);
  for (var hi = 13; hi >= 4; hi--) {
    if ((ext >> (hi - 4)) & 0x1F == 0x1F) return hi - 1;
  }
  return -1;
}

final Uint8List _counts = Uint8List(13);

/// Evaluates the best 5-card hand among 5..7 cards.
int evaluate(List<int> cards) {
  final counts = _counts;
  counts.fillRange(0, 13, 0);
  var s0 = 0, s1 = 0, s2 = 0, s3 = 0, rankMask = 0;
  for (var i = 0; i < cards.length; i++) {
    final c = cards[i];
    final r = c >> 2;
    final bit = 1 << r;
    switch (c & 3) {
      case 0:
        s0 |= bit;
      case 1:
        s1 |= bit;
      case 2:
        s2 |= bit;
      default:
        s3 |= bit;
    }
    counts[r]++;
    rankMask |= bit;
  }

  // Flush / straight flush. With <= 7 cards at most one suit can have 5+.
  var flushMask = 0;
  if (_bitCount(s0) >= 5) {
    flushMask = s0;
  } else if (_bitCount(s1) >= 5) {
    flushMask = s1;
  } else if (_bitCount(s2) >= 5) {
    flushMask = s2;
  } else if (_bitCount(s3) >= 5) {
    flushMask = s3;
  }
  if (flushMask != 0) {
    final sf = _straightHigh(flushMask);
    if (sf >= 0) return _make(8, sf);
    var m = flushMask;
    final a = _highBit(m);
    m &= ~(1 << a);
    final b = _highBit(m);
    m &= ~(1 << b);
    final c = _highBit(m);
    m &= ~(1 << c);
    final d = _highBit(m);
    m &= ~(1 << d);
    return _make(5, a, b, c, d, _highBit(m));
  }

  var quad = -1, trip1 = -1, trip2 = -1, pair1 = -1, pair2 = -1, pair3 = -1;
  for (var r = 12; r >= 0; r--) {
    switch (counts[r]) {
      case 4:
        quad = r;
      case 3:
        if (trip1 < 0) {
          trip1 = r;
        } else if (trip2 < 0) {
          trip2 = r;
        }
      case 2:
        if (pair1 < 0) {
          pair1 = r;
        } else if (pair2 < 0) {
          pair2 = r;
        } else if (pair3 < 0) {
          pair3 = r;
        }
    }
  }

  if (quad >= 0) {
    return _make(7, quad, _highBit(rankMask & ~(1 << quad)));
  }
  if (trip1 >= 0 && (trip2 >= 0 || pair1 >= 0)) {
    return _make(6, trip1, trip2 > pair1 ? trip2 : pair1);
  }
  final st = _straightHigh(rankMask);
  if (st >= 0) return _make(4, st);

  if (trip1 >= 0) {
    var m = rankMask & ~(1 << trip1);
    final a = _highBit(m);
    m &= ~(1 << a);
    return _make(3, trip1, a, _highBit(m));
  }
  if (pair2 >= 0) {
    // Best kicker may be the third pair's rank.
    final k = _highBit(rankMask & ~(1 << pair1) & ~(1 << pair2));
    return _make(2, pair1, pair2, k);
  }
  if (pair1 >= 0) {
    var m = rankMask & ~(1 << pair1);
    final a = _highBit(m);
    m &= ~(1 << a);
    final b = _highBit(m);
    m &= ~(1 << b);
    return _make(1, pair1, a, b, _highBit(m));
  }
  var m = rankMask;
  final a = _highBit(m);
  m &= ~(1 << a);
  final b = _highBit(m);
  m &= ~(1 << b);
  final c = _highBit(m);
  m &= ~(1 << c);
  final d = _highBit(m);
  m &= ~(1 << d);
  return _make(0, a, b, c, d, _highBit(m));
}

/// Human-readable description, e.g. "Full House, Kings over Fives".
String describeHand(int value) {
  final cat = categoryOf(value);
  String r(int i) => rankNames[kickerRank(value, i)];
  String p(int i) => rankPlurals[kickerRank(value, i)];
  return switch (cat) {
    HandCategory.straightFlush =>
      kickerRank(value, 0) == 12 ? 'Royal Flush' : 'Straight Flush, ${r(0)} high',
    HandCategory.quads => 'Four ${p(0)}',
    HandCategory.fullHouse => 'Full House, ${p(0)} over ${p(1)}',
    HandCategory.flush => 'Flush, ${r(0)} high',
    HandCategory.straight => 'Straight, ${r(0)} high',
    HandCategory.trips => 'Three ${p(0)}',
    HandCategory.twoPair => 'Two Pair, ${p(0)} and ${p(1)}',
    HandCategory.pair => 'Pair of ${p(0)}',
    HandCategory.highCard => '${r(0)} High',
  };
}

/// The five cards making the best hand (for highlighting in the UI).
List<int> bestFive(List<int> cards) {
  if (cards.length <= 5) return List.of(cards);
  var best = -1;
  var bestCombo = <int>[];
  final n = cards.length;
  final combo = List<int>.filled(5, 0);
  for (var a = 0; a < n; a++) {
    for (var b = a + 1; b < n; b++) {
      for (var c = b + 1; c < n; c++) {
        for (var d = c + 1; d < n; d++) {
          for (var e = d + 1; e < n; e++) {
            combo[0] = cards[a];
            combo[1] = cards[b];
            combo[2] = cards[c];
            combo[3] = cards[d];
            combo[4] = cards[e];
            final v = evaluate(combo);
            if (v > best) {
              best = v;
              bestCombo = List.of(combo);
            }
          }
        }
      }
    }
  }
  return bestCombo;
}
