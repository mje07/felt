// Duplicate-format bot match with confidence intervals.
// Run: dart run tool/arena.dart [--deals 5000] [--difficulty expert]
//        [--lineup rock,tag,lag,station,maniac] [--seed 1]
// Heads-up: --lineup tag,station
import 'dart:io';

import 'package:poker_engine/poker_engine.dart';

void main(List<String> args) {
  String opt(String name, String def) {
    final i = args.indexOf('--$name');
    return i >= 0 ? args[i + 1] : def;
  }

  final deals = int.parse(opt('deals', '3000'));
  final seed = int.parse(opt('seed', '1'));
  final stackBb = int.parse(opt('stack', '100'));
  final difficulty = Difficulty.values.byName(opt('difficulty', 'standard'));
  final lineup = [
    for (final id in opt('lineup', 'rock,tag,lag,station,maniac').split(','))
      Personality.byId(id.trim())
  ];
  final sw = Stopwatch()..start();
  final lines = runArena(
    lineup: lineup,
    difficulty: difficulty,
    deals: deals,
    seed: seed,
    stackBb: stackBb,
    onProgress: (d) {
      if (d % 1000 == 0) stderr.writeln('$d deals, ${sw.elapsed.inSeconds}s');
    },
  );
  stdout.writeln('${lineup.length}-handed, ${difficulty.name}, ${stackBb}bb, $deals deals '
      '× ${lineup.length} rotations, ${sw.elapsed.inSeconds}s  (bb/100 ± 95% CI)');
  for (final l in lines) {
    stdout.writeln('  $l');
  }
}
