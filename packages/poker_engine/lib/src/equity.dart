import 'dart:math';

import 'range_model.dart';
import 'evaluator.dart';

class EquityResult {
  const EquityResult(this.win, this.tie, this.equity, this.samples);
  final double win, tie;

  /// Expected share of the pot (wins + split shares).
  final double equity;
  final int samples;
  @override
  String toString() =>
      'Equity(${(equity * 100).toStringAsFixed(1)}%, n=$samples)';
}

/// Monte Carlo equity of [hole] against [opponents] unknown hands.
///
/// [opponentRanges], when given, holds one value per opponent: the fraction of
/// starting hands they are assumed to hold (1.0 = any two cards, 0.2 = the top
/// 20% by preflop strength).
///
/// [opponentCombos], when given, takes precedence: one explicit combo list
/// per opponent (see `range_model.dart`), e.g. narrowed by their postflop
/// actions. Hands are drawn exactly from these ranges.
EquityResult monteCarloEquity({
  required List<int> hole,
  required List<int> board,
  required int opponents,
  int iterations = 1000,
  Random? rng,
  List<double>? opponentRanges,
  List<List<int>>? opponentCombos,
}) {
  assert(opponents >= 1);
  final r = rng ?? Random();
  var deadMask = 0;
  for (final c in [...hole, ...board]) {
    deadMask |= 1 << c;
  }
  final ranges = opponentCombos ??
      (opponentRanges == null
          ? null
          : [
              for (final w in opponentRanges)
                w >= 1.0 ? null : preflopRange(w, dead: [...hole, ...board])
            ].map((l) => l ?? const <int>[]).toList());
  final need = 5 - board.length;
  final hero = List<int>.filled(2 + 5, 0);
  final opp = List<int>.filled(2 + 5, 0);
  final oppHoles = List<int>.filled(opponents * 2, 0);
  var wins = 0.0, ties = 0.0, share = 0.0;

  int draw(int used) {
    while (true) {
      final c = r.nextInt(52);
      if ((used >> c) & 1 == 0) return c;
    }
  }

  for (var it = 0; it < iterations; it++) {
    var used = deadMask;
    for (var o = 0; o < opponents; o++) {
      final list = ranges == null || o >= ranges.length ? const <int>[] : ranges[o];
      final combo = list.isEmpty ? -1 : sampleCombo(list, used, r);
      int a, b;
      if (combo >= 0) {
        a = comboA(combo);
        b = comboB(combo);
      } else {
        // Any two cards (or the range is fully blocked).
        a = draw(used);
        b = draw(used | (1 << a));
      }
      used |= (1 << a) | (1 << b);
      oppHoles[o * 2] = a;
      oppHoles[o * 2 + 1] = b;
    }
    // Board: known cards first, then runout.
    hero[0] = hole[0];
    hero[1] = hole[1];
    for (var i = 0; i < board.length; i++) {
      hero[2 + i] = board[i];
    }
    for (var i = 0; i < need; i++) {
      final c = draw(used);
      used |= 1 << c;
      hero[2 + board.length + i] = c;
    }
    final heroVal = evaluate(hero);
    var best = 0;
    var tiedWith = 0;
    for (var i = 2; i < 7; i++) {
      opp[i] = hero[i];
    }
    for (var o = 0; o < opponents; o++) {
      opp[0] = oppHoles[o * 2];
      opp[1] = oppHoles[o * 2 + 1];
      final v = evaluate(opp);
      if (v > best) {
        best = v;
        tiedWith = 0;
      }
      if (v == heroVal) tiedWith++;
    }
    if (heroVal > best) {
      wins++;
      share++;
    } else if (heroVal == best) {
      ties++;
      share += 1 / (tiedWith + 1);
    }
  }
  return EquityResult(
      wins / iterations, ties / iterations, share / iterations, iterations);
}
