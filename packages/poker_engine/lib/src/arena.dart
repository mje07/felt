import 'dart:math';

import 'bots/bot.dart';
import 'bots/heuristic_bot.dart';
import 'bots/personality.dart';
import 'bots/reads.dart';
import 'rng.dart';
import 'rules.dart';

/// One bot's result in an [runArena] match.
class ArenaLine {
  ArenaLine(this.personality);
  final Personality personality;
  int samples = 0;
  double sum = 0, sumSq = 0;

  /// Big blinds won per 100 hands.
  double get bbPer100 => samples == 0 ? 0 : sum / samples * 100;

  /// Half-width of the 95% confidence interval, in bb/100.
  double get ci95 {
    if (samples < 2) return double.infinity;
    final mean = sum / samples;
    final variance = (sumSq / samples - mean * mean) * samples / (samples - 1);
    return 1.96 * sqrt(max(0, variance) / samples) * 100;
  }

  @override
  String toString() =>
      '${personality.label.padRight(9)} ${bbPer100.toStringAsFixed(1).padLeft(7)} ± ${ci95.toStringAsFixed(1)}';
}

/// Duplicate-format bot match. Each deal is played once per seat rotation of
/// [lineup] with the same deck and button, and every hand starts at
/// [stackBb] big blinds, so card luck and stack swings cancel out.
///
/// Results are averaged per personality (a personality listed twice pools
/// both seats).
List<ArenaLine> runArena({
  required List<Personality> lineup,
  Difficulty difficulty = Difficulty.standard,
  int deals = 2000,
  int seed = 1,
  int stackBb = 100,
  void Function(int dealsDone)? onProgress,
}) {
  const bb = 10;
  final rng = Random(seed);
  final n = lineup.length;
  final lines = <String, ArenaLine>{};
  for (final p in lineup) {
    lines.putIfAbsent(p.id, () => ArenaLine(p));
  }
  final bots = {for (final p in lineup) p.id: HeuristicBot(p, difficulty)};
  final reads = TableReads();

  for (var d = 0; d < deals; d++) {
    final deck = List<int>.generate(52, (i) => i);
    shuffle(deck, rng);
    // Per-deal net for each personality, summed across rotations.
    final net = <String, double>{for (final id in lines.keys) id: 0};
    for (var rot = 0; rot < n; rot++) {
      final seatsP = [for (var i = 0; i < n; i++) lineup[(i + rot) % n]];
      var s = startHand(
        players: [for (final p in seatsP) SeatSetup(p.label, stackBb * bb)],
        button: 0,
        smallBlind: bb ~/ 2,
        bigBlind: bb,
        handNumber: d * n + rot + 1,
        deck: List.of(deck),
      );
      while (!s.isComplete) {
        final p = seatsP[s.toAct];
        s = applyAction(s, bots[p.id]!.decide(buildBotContext(s, reads: reads), rng));
      }
      reads.observe(s);
      for (var i = 0; i < n; i++) {
        net[seatsP[i].id] = net[seatsP[i].id]! + (s.seats[i].stack - stackBb * bb) / bb;
      }
    }
    for (final e in net.entries) {
      final line = lines[e.key]!;
      final count = lineup.where((p) => p.id == e.key).length;
      // Average per hand played by this personality in this deal.
      final perHand = e.value / (n * count);
      line.samples++;
      line.sum += perHand;
      line.sumSq += perHand * perHand;
    }
    onProgress?.call(d + 1);
  }
  return lines.values.toList()..sort((a, b) => b.bbPer100.compareTo(a.bbPer100));
}
