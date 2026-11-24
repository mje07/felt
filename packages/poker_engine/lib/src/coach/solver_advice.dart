import 'dart:math';

import '../bots/bot.dart';
import '../game_state.dart';
import '../range_model.dart' as rm;
import '../ranges/weighted_range.dart';
import '../solver/solver.dart';

/// The solver's view of one heads-up river decision, for the player's hand.
class SolverAdvice {
  const SolverAdvice({
    required this.actions,
    required this.ev,
    required this.freq,
    required this.streetBet,
    required this.pot,
    required this.exploitability,
  });

  /// The tree's options at this decision.
  final List<SolverAction> actions;

  /// Expected chips of each action for this hand, and how often the solver
  /// takes each one with it.
  final List<double> ev, freq;

  /// Our chips already in on this street, and the pot now (for labels).
  final int streetBet, pot;

  /// How exploitable the solved strategy is (% of the pot at the start of
  /// the street).
  final double exploitability;

  int get best {
    var b = 0;
    for (var i = 1; i < ev.length; i++) {
      if (ev[i] > ev[b]) b = i;
    }
    return b;
  }

  /// Index of the tree action closest to what was actually done.
  int indexOf(ActionType type, int amountTo) {
    String? kind = switch (type) {
      ActionType.fold => 'fold',
      ActionType.check => 'check',
      ActionType.call => 'call',
      _ => null,
    };
    if (kind != null) {
      final i = actions.indexWhere((a) => a.kind == kind);
      if (i >= 0) return i;
    }
    var bestI = -1;
    var bestD = 1 << 30;
    for (var i = 0; i < actions.length; i++) {
      if (!actions[i].aggressive) continue;
      final d = (actions[i].amount - amountTo).abs();
      if (d < bestD) {
        bestD = d;
        bestI = i;
      }
    }
    return bestI >= 0 ? bestI : 0;
  }

  String label(int i) {
    final a = actions[i];
    return switch (a.kind) {
      'check' => 'Check',
      'fold' => 'Fold',
      'call' => 'Call',
      'bet' => 'Bet ${((a.amount - streetBet) / pot * 100).round()}% pot',
      'raise' => 'Raise',
      _ => 'All-in',
    };
  }

  /// "Bet 75% pot 62% · Check 38%".
  String get mix {
    final order = [for (var i = 0; i < actions.length; i++) i]..sort((a, b) => freq[b].compareTo(freq[a]));
    return [
      for (final i in order)
        if (freq[i] >= 0.05) '${label(i)} ${(freq[i] * 100).round()}%',
    ].join(' · ');
  }
}

/// Solves a heads-up river decision exactly, or returns null when the spot
/// isn't one the solver covers (multiway, not the river, missing ranges).
SolverAdvice? solveRiverDecision(BotContext ctx, {Duration budget = const Duration(milliseconds: 1500)}) {
  if (ctx.street != Street.river || ctx.opponents != 1 || ctx.board.length != 5) return null;
  if (ctx.opponentCombos.isEmpty || ctx.selfCombos.isEmpty || ctx.streetStartStack <= 0) return null;
  WeightedRange toRange(List<int> combos) {
    final r = WeightedRange();
    for (final c in combos) {
      r.w[comboIndex(rm.comboA(c), rm.comboB(c))] = 1;
    }
    return r;
  }

  final mine = toRange(ctx.selfCombos);
  final myCombo = comboIndex(ctx.hole[0], ctx.hole[1]);
  mine.w[myCombo] = 1; // our actual hand is always possible
  final theirs = toRange(ctx.opponentCombos.first);
  final heroIp = ctx.inPosition;

  // Include the sizes actually used on this street so the line maps exactly.
  final pot = ctx.streetStartPot;
  final seen = <double>{0.5, 1.0};
  var potSoFar = pot, prevTop = 0;
  for (final (_, type, to) in ctx.streetActions) {
    if (type == ActionType.bet) seen.add(double.parse(((to) / potSoFar).toStringAsFixed(2)));
    potSoFar += max(0, to - prevTop);
    prevTop = max(prevTop, to);
  }
  final spot = SolverSpot(
    board: ctx.board,
    pot: pot,
    stack: ctx.streetStartStack,
    oop: heroIp ? theirs : mine,
    ip: heroIp ? mine : theirs,
    river: StreetSizes(bet: seen.toList()..sort(), raise: const [0.75]),
  );
  final s = Solver(spot);
  final sw = Stopwatch()..start();
  var expl = double.infinity;
  while (sw.elapsed < budget) {
    s.iterate(s.iterations < 40 ? 20 : 40);
    expl = s.exploitability();
    if (expl <= 0.3) break;
  }

  // Follow the street's actions down the tree.
  final path = <int>[];
  var node = s.root;
  for (final (_, type, to) in ctx.streetActions) {
    if (node.kind != NodeKind.action) return null;
    final advice = SolverAdvice(
        actions: node.actions, ev: const [], freq: const [], streetBet: 0, pot: pot, exploitability: expl);
    final i = advice.indexOf(type, to);
    path.add(i);
    node = node.children[i];
  }
  final heroPlayer = heroIp ? 1 : 0;
  if (node.kind != NodeKind.action || node.player != heroPlayer) return null;
  final evs = s.actionEvs(path, myCombo);
  if (evs == null) return null;
  final myBet = heroPlayer == 0 ? node.c0 : node.c1;
  return SolverAdvice(
    actions: node.actions,
    ev: evs.$1,
    freq: evs.$2,
    streetBet: myBet,
    pot: pot + node.c0 + node.c1,
    exploitability: expl,
  );
}
