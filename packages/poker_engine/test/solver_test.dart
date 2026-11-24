import 'package:poker_engine/poker_engine.dart';
import 'package:test/test.dart';

/// Weighted share of [player]'s hands (filtered by [test]) taking [action]
/// at [node].
double frequency(Solver s, SolverNode node, int action, {bool Function(int combo)? test}) {
  final sigma = s.averageStrategy(node);
  final hands = s.hands(node.player), w = s.weights(node.player);
  var num = 0.0, den = 0.0;
  for (var j = 0; j < hands.length; j++) {
    if (test != null && !test(hands[j])) continue;
    num += w[j] * sigma[action * hands.length + j];
    den += w[j];
  }
  return num / den;
}

bool isRank(int combo, int rank) => cardRank(comboCards[combo].$1) == rank && cardRank(comboCards[combo].$2) == rank;

void main() {
  group('river toy game: nuts or air against a bluff-catcher', () {
    // In position: KK (3 combos, the nuts) or 65 (16 combos, air).
    // Out of position: QJ (12 combos), beats air, loses to KK. Pot-size bet.
    // Theory: bet all value, bluff 1.5 combos (9.4% of the air), and the
    // bluff-catcher calls exactly 50%.
    late Solver s;
    setUpAll(() {
      s = Solver(SolverSpot(
        board: parseCards('Kh Qd 7c 4s 2h'),
        pot: 100,
        stack: 100,
        oop: WeightedRange.fromNotation('QJ'),
        ip: WeightedRange.fromNotation('KK, 65'),
        river: const StreetSizes(bet: [1.0], raise: [], oopBet: []),
      ));
      s.iterate(3000);
    });

    test('the tree has the expected shape', () {
      expect(s.root.actions.map((a) => a.kind), ['check']);
      final ip = s.root.children.single;
      expect(ip.actions.map((a) => a.kind), ['check', 'allin']);
      expect(ip.children[1].actions.map((a) => a.kind), ['fold', 'call']);
    });

    test('converges to an unexploitable strategy', () {
      expect(s.exploitability(), lessThan(0.3));
    });

    test('matches the analytic equilibrium', () {
      final ip = s.root.children.single;
      final facing = ip.children[1];
      expect(frequency(s, ip, 1, test: (c) => isRank(c, 11)), closeTo(1.0, 0.01)); // KK bets
      expect(frequency(s, ip, 1, test: (c) => !isRank(c, 11)), closeTo(1.5 / 16, 0.02)); // bluffs
      expect(frequency(s, facing, 1), closeTo(0.5, 0.03)); // calls
    });

    test('the game value is zero-sum', () {
      expect(s.expectedValue(0) + s.expectedValue(1), closeTo(0, 1e-6));
    });
  });

  test('exploitability falls as the solver runs (turn spot)', () {
    final s = Solver(SolverSpot(
      board: parseCards('Ks 9d 4c 2h'),
      pot: 60,
      stack: 200,
      oop: WeightedRange.fromNotation('99, 44, KQs, KJs, AK, QJs, JTs, T9s, A5s, 87s'),
      ip: WeightedRange.fromNotation('AA, KK, AK, KQ, QQ, JJ, AQs, A5s, 65s, QJs'),
    ));
    s.iterate(10);
    final early = s.exploitability();
    s.iterate(150);
    final late = s.exploitability();
    expect(late, lessThan(early));
    expect(late, lessThan(3));
    expect(s.expectedValue(0) + s.expectedValue(1), closeTo(0, 1e-6));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('every node has consistent strategies and pot accounting', () {
    final s = Solver(SolverSpot(
      board: parseCards('Ah 8d 3c 3s Tc'),
      pot: 40,
      stack: 100,
      oop: WeightedRange.fromWidth(0.3),
      ip: WeightedRange.fromWidth(0.3),
    ));
    s.iterate(50);
    void walk(SolverNode n) {
      expect(n.c0, lessThanOrEqualTo(100));
      expect(n.c1, lessThanOrEqualTo(100));
      if (n.kind == NodeKind.action) {
        final sigma = s.averageStrategy(n);
        final h = s.hands(n.player).length;
        for (var j = 0; j < h; j++) {
          var sum = 0.0;
          for (var i = 0; i < n.actions.length; i++) {
            sum += sigma[i * h + j];
          }
          expect(sum, closeTo(1, 1e-6));
        }
      }
      n.children.forEach(walk);
    }

    walk(s.root);
  });

  test('views, and a cached solve restores the same strategy', () {
    SolverSpot spot() => SolverSpot(
          board: parseCards('Jh 8d 3c 3s 2c'),
          pot: 50,
          stack: 200,
          oop: WeightedRange.fromWidth(0.4),
          ip: WeightedRange.fromWidth(0.3),
        );
    final a = Solver(spot())..iterate(60);
    final view = a.view(const []);
    expect(view.kind, NodeKind.action);
    expect(view.actionFrequencies.reduce((x, y) => x + y), closeTo(1, 1e-9));
    expect(view.ev.where((e) => !e.isNaN), isNotEmpty);
    final deeper = a.view(const [0]); // after a check
    expect(deeper.player, 1);

    final b = Solver(spot());
    expect(b.importStrategies(a.exportStrategies()), isTrue);
    expect(b.iterations, 60);
    expect(b.view(const [0]).actionFrequencies, a.view(const [0]).actionFrequencies);
    expect(spot().describe(), spot().describe());
    expect(Solver(SolverSpot(board: parseCards('Jh 8d 3c'), pot: 50, stack: 200, oop: WeightedRange.full(), ip: WeightedRange.full()))
        .importStrategies(a.exportStrategies()), isFalse);
  });
}
