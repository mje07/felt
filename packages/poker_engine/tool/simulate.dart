// Headless bot-vs-bot simulation. Checks invariants and reports bot results.
// Run: dart run tool/simulate.dart [--hands 100000] [--seats 6] [--seed 1]
import 'dart:io';
import 'dart:math';

import 'package:poker_engine/poker_engine.dart';

void main(List<String> args) {
  int opt(String name, int def) {
    final i = args.indexOf('--$name');
    return i >= 0 ? int.parse(args[i + 1]) : def;
  }

  final hands = opt('hands', 100000), seatsN = opt('seats', 6), seed = opt('seed', 1);
  final rng = Random(seed);
  const buyIn = 1000;
  final players = [
    for (var i = 0; i < seatsN; i++)
      TablePlayer(
        name: Personality.all[i % Personality.all.length].label,
        stack: buyIn,
        personality: Personality.all[i % Personality.all.length],
        difficulty: Difficulty.casual,
      ),
  ];
  final game = CashGame(seats: players, smallBlind: 5, bigBlind: 10, rng: rng);
  final sw = Stopwatch()..start();
  var showdowns = 0, actions = 0;
  for (var h = 0; h < hands; h++) {
    for (var i = 0; i < seatsN; i++) {
      if (players[i].stack < buyIn ~/ 2) game.rebuy(i, buyIn - players[i].stack);
    }
    final total = players.fold(0, (a, p) => a + p.stack);
    var s = game.startNextHand();
    while (!s.isComplete) {
      s = applyAction(s, players[s.toAct].bot!.decide(buildBotContext(s), rng));
      actions++;
    }
    game.settle(s);
    if (players.fold(0, (a, p) => a + p.stack) != total) {
      stderr.writeln('Chip conservation violated in hand ${s.handNumber}\n$s');
      exit(1);
    }
    if (s.street == Street.showdown) showdowns++;
    if ((h + 1) % 10000 == 0) stdout.writeln('${h + 1} hands, ${sw.elapsed.inSeconds}s');
  }
  stdout.writeln('\n$hands hands, $actions actions, ${(100 * showdowns / hands).toStringAsFixed(1)}% showdowns, ${sw.elapsed.inSeconds}s');
  stdout.writeln('Results (bb/100):');
  for (final p in players) {
    final net = p.stack - p.buyIns;
    stdout.writeln('  ${p.name.padRight(10)} ${(net / 10 / hands * 100).toStringAsFixed(1).padLeft(7)}');
  }
}
