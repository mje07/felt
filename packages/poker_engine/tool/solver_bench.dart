// Solver timing on realistic spots. Compile for real numbers:
//   dart compile exe tool/solver_bench.dart -o build/solver_bench.exe
import 'package:poker_engine/poker_engine.dart';

void main() {
  final btn = WeightedRange.fromChart(chartFor('BTN', PreflopScenario.unopened));
  final bb = WeightedRange.fromChart(bbDefenseChart);

  void run(String name, SolverSpot spot, {double target = 0.5, int maxSeconds = 300}) {
    final sw = Stopwatch()..start();
    final s = Solver(spot);
    final built = sw.elapsedMilliseconds;
    var expl = double.infinity;
    while (sw.elapsed.inSeconds < maxSeconds) {
      s.iterate(s.iterations < 50 ? 10 : 25);
      expl = s.exploitability();
      if (expl <= target) break;
    }
    print('$name: ${s.nodeCount} nodes, ${s.hands(0).length}+${s.hands(1).length} hands, '
        'built ${built}ms, ${s.iterations} iterations, ${sw.elapsedMilliseconds}ms, '
        'exploitability ${expl.toStringAsFixed(2)}% pot');
  }

  run('river BTN vs BB', SolverSpot(board: parseCards('Ks 9d 4c 2h 7s'), pot: 55, stack: 945, oop: bb, ip: btn));
  run('turn  BTN vs BB', SolverSpot(board: parseCards('Ks 9d 4c 2h'), pot: 55, stack: 945, oop: bb, ip: btn));
  // Slow (~1.5 min): compile with -Dflop=true.
  if (const bool.fromEnvironment('flop')) {
    run('flop  BTN vs BB', SolverSpot(board: parseCards('Ks 9d 4c'), pot: 55, stack: 945, oop: bb, ip: btn), target: 1.0);
  }
}
