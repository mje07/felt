import 'dart:math';

import 'package:poker_engine/poker_engine.dart';
import 'package:test/test.dart';

WeightedRange hand(String cards) {
  final c = parseCards(cards);
  return WeightedRange()..[comboIndex(c[0], c[1])] = 1;
}

/// Brute force: every (hero combo, villain combo, runout) triple.
double bruteForce(WeightedRange h, WeightedRange v, List<int> board) {
  var num = 0.0, den = 0.0;
  final deck = [for (var c = 0; c < 52; c++) if (!board.contains(c)) c];
  for (final i in h.live) {
    for (final j in v.live) {
      final (a, b) = comboCards[i];
      final (c, d) = comboCards[j];
      if ({a, b, c, d}.length < 4 || board.contains(a) || board.contains(b) || board.contains(c) || board.contains(d)) {
        continue;
      }
      final rest = [for (final x in deck) if (x != a && x != b && x != c && x != d) x];
      final need = 5 - board.length;
      void rec(List<int> five, int start) {
        if (five.length == 5) {
          final hv = evaluate([a, b, ...five]), vv = evaluate([c, d, ...five]);
          final w = h.w[i] * v.w[j];
          den += w;
          num += w * (hv > vv ? 1 : hv == vv ? 0.5 : 0);
          return;
        }
        for (var k = start; k < rest.length; k++) {
          rec([...five, rest[k]], k + 1);
        }
      }

      if (need == 0) {
        rec(board, 0);
      } else {
        rec([...board], 0);
      }
    }
  }
  return num / den;
}

void main() {
  group('range vs range equity', () {
    test('AA vs KK preflop is about 82%', () {
      final e = rangeVsRange([hand('Ah As'), hand('Kh Ks')], const [], samples: 80000, rng: Random(1));
      expect(e.equity[0], closeTo(0.819, 0.01));
      expect(e.exact, isFalse);
    });

    test('AKs vs QQ preflop is about 46%', () {
      final e = rangeVsRange([WeightedRange.fromNotation('AKs'), WeightedRange.fromNotation('QQ')], const [],
          samples: 80000, rng: Random(2));
      expect(e.equity[0], closeTo(0.462, 0.01));
    });

    test('exact flop, turn and river results match brute force, with card removal', () {
      final h = WeightedRange.fromNotation('AKs, QQ, 98s');
      final v = WeightedRange.fromNotation('AA, KQs, T9s')..[comboIndex(parseCard('Ts'), parseCard('9s'))] = 0.5;
      for (final b in ['Ah 9s 2d', 'Ah 9s 2d Qc', 'Ah 9s 2d Qc 8h']) {
        final board = parseCards(b);
        final e = rangeVsRange([h, v], board);
        expect(e.exact, isTrue);
        expect(e.equity[0], closeTo(bruteForce(h, v, board), 1e-9), reason: b);
        expect(e.equity[0] + e.equity[1], closeTo(1, 1e-9));
      }
    });

    test('per-hand equity: the nuts wins every time', () {
      final board = parseCards('Ah Kh Qh 2c 3d');
      final e = rangeVsRange([WeightedRange.fromNotation('JTs'), WeightedRange.fromNotation('AA, KK, 22')], board);
      expect(e.handEquity[0][comboIndex(parseCard('Jh'), parseCard('Th'))], 1.0);
    });

    test('three-way sampling sums to one', () {
      final e = rangeVsRange(
          [WeightedRange.fromNotation('AA'), WeightedRange.fromNotation('KK'), WeightedRange.fromNotation('QQ')],
          const [], samples: 30000, rng: Random(3));
      expect(e.equity.reduce((a, b) => a + b), closeTo(1, 1e-9));
      expect(e.equity[0], greaterThan(e.equity[1]));
    });
  });

  group('hand classes', () {
    HandClass made(String hole, String board) {
      final c = parseCards(hole);
      return classifyHand(c[0], c[1], parseCards(board)).$1;
    }

    HandClass? draw(String hole, String board) {
      final c = parseCards(hole);
      return classifyHand(c[0], c[1], parseCards(board)).$2;
    }

    test('made hands on K-7-2', () {
      const b = 'Ks 7d 2c';
      expect(made('Kh Kd', b), HandClass.set);
      expect(made('Ah As', b), HandClass.overpair);
      expect(made('Ah Kd', b), HandClass.topPairGood);
      expect(made('Kh 5d', b), HandClass.topPairWeak);
      expect(made('Qh Qd', b), HandClass.pocketBelowTop);
      expect(made('7h 2h', b), HandClass.twoPair);
      expect(made('8h 7h', b), HandClass.middlePair);
      expect(made('Ah 2h', b), HandClass.bottomPair);
      expect(made('Ah Qd', b), HandClass.aceHigh);
      expect(made('9h 8d', b), HandClass.nothing);
    });

    test('draws on 9-8-2 with two hearts', () {
      const b = '9h 8h 2c';
      expect(draw('Jh Th', b), HandClass.comboDraw);
      expect(draw('Jc Tc', b), HandClass.oesd);
      expect(draw('Ah 3h', b), HandClass.flushDraw);
      expect(draw('Jc 7d', b), HandClass.gutshot);
      expect(draw('Ad 3d', b), isNull);
      expect(draw('Ah 3h', '9h 8h 2c 4s 5d'), isNull); // river: no draws
    });

    test('breakdown counts', () {
      final bd = handClassBreakdown(WeightedRange.fromNotation('AA, KK, AKs'), parseCards('Ks 7d 2c'));
      expect(bd.total, 6 + 3 + 3); // KK loses 3 combos, AKs loses one
      expect(bd.combos[HandClass.overpair], 6);
      expect(bd.combos[HandClass.set], 3);
      expect(bd.combos[HandClass.topPairGood], 3);
      expect(bd.share(HandClass.overpair), closeTo(0.5, 1e-9));
    });
  });

  group('weighted ranges', () {
    test('notation round trip and grid weights', () {
      final r = WeightedRange.fromNotation('AA, AKs, 72o');
      expect(r.combos, 6 + 4 + 12);
      expect(r.toNotation(), 'AA, AKs, 72o');
      final g = r.gridWeights();
      expect(g.where((x) => x > 0).length, 3);
    });

    test('weighted sampling follows the weights and avoids dead cards', () {
      final r = WeightedRange.fromNotation('AA, KK');
      for (final i in cellCombos[startingHandIndex(parseCard('Kh'), parseCard('Ks'))]) {
        r[i] = 0.25;
      }
      final cum = r.cumulativeWeights();
      final rng = Random(5);
      var aces = 0;
      for (var n = 0; n < 20000; n++) {
        final c = WeightedRange.sample(cum, rng, 0);
        if (cardRank(comboCards[c].$1) == 12) aces++;
      }
      expect(aces / 20000, closeTo(0.8, 0.02)); // 6 : 1.5
      final dead = 1 << parseCard('As') | 1 << parseCard('Ah') | 1 << parseCard('Ad');
      for (var n = 0; n < 200; n++) {
        final c = WeightedRange.sample(cum, rng, dead);
        final (a, b) = comboCards[c];
        expect((dead >> a) & 1 | (dead >> b) & 1, 0);
      }
    });
  });
}
