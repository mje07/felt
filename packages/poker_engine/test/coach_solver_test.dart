import 'dart:math';

import 'package:poker_engine/poker_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Heads-up hand checked down to the river. Seat 0 is the button (small
/// blind) and seat 1 the big blind, who acts first after the flop.
HandState checkedToRiver(String bbHole, String btnHole, String board) {
  var s = startHand(
    players: const [SeatSetup('Btn', 1000), SeatSetup('Hero', 1000)],
    button: 0,
    smallBlind: 5,
    bigBlind: 10,
    handNumber: 1,
    deck: stackedDeck([btnHole, bbHole], board),
  );
  s = applyAction(s, const PlayerAction.call()); // button completes
  s = applyAction(s, const PlayerAction.check()); // big blind checks
  for (var street = 0; street < 2; street++) {
    s = applyAction(s, const PlayerAction.check());
    s = applyAction(s, const PlayerAction.check());
  }
  expect(s.street, Street.river);
  return s;
}

PlayerAction asAction(SolverAction a) => switch (a.kind) {
      'check' => const PlayerAction.check(),
      'call' => const PlayerAction.call(),
      'fold' => const PlayerAction(ActionType.fold),
      'bet' || 'allin' => PlayerAction(ActionType.bet, a.amount),
      _ => PlayerAction(ActionType.raise, a.amount),
    };

void main() {
  test('heads-up river decisions are graded by the solver', () {
    final s = checkedToRiver('Ah Kd', '7c 6c', 'As 9h 4d 2c Qs');
    expect(s.seats[s.toAct].name, 'Hero');
    final ctx = buildBotContext(s);
    final a = analyzeDecision(ctx, samples: 400, rng: Random(1));
    final solver = a.solver;
    expect(solver, isNotNull);
    expect(solver!.actions.first.kind, 'check');
    expect(solver.freq.reduce((x, y) => x + y), closeTo(1, 1e-6));
    expect(solver.exploitability, lessThan(1.0));

    final best = gradeDecision(a, asAction(solver.actions[solver.best]))!;
    expect(best.grade, Grade.best);
    expect(best.bySolver, isTrue);
    expect(best.solverMix, isNotEmpty);
    expect(best.explanation, startsWith('Solver:'));

    // Round-trips through hand-history JSON.
    expect(DecisionReview.fromJson(best.toJson()).solverMix, best.solverMix);
  });

  test('facing a river bet, the line is followed down the tree', () {
    var s = checkedToRiver('9c 8c', 'Ah Ad', 'As 9h 4d 2c Qs');
    s = applyAction(s, const PlayerAction.check()); // big blind checks
    s = applyAction(s, const PlayerAction(ActionType.bet, 15)); // button bets 75%
    final ctx = buildBotContext(s);
    final a = analyzeDecision(ctx, samples: 400, rng: Random(2));
    final solver = a.solver!;
    expect(solver.actions.map((x) => x.kind), containsAll(['fold', 'call']));
    // Hero has a pair of nines against a range that bets; whatever the solver
    // does most must score Best, and its own grade must not be worse than
    // any alternative's.
    final grades = [for (final x in solver.actions) gradeDecision(a, asAction(x))!.grade.index];
    expect(grades[solver.best], Grade.best.index);
    expect(grades.reduce(min), Grade.best.index);
  });

  test('multiway and earlier streets keep the equity model', () {
    final s = checkedToRiver('Ah Kd', '7c 6c', 'As 9h 4d 2c Qs');
    var flop = startHand(
      players: const [SeatSetup('A', 1000), SeatSetup('B', 1000), SeatSetup('C', 1000)],
      button: 0,
      smallBlind: 5,
      bigBlind: 10,
      handNumber: 1,
      rng: Random(3),
    );
    while (flop.street == Street.preflop) {
      flop = applyAction(flop, legalActions(flop).canCheck ? const PlayerAction.check() : const PlayerAction.call());
    }
    expect(analyzeDecision(buildBotContext(flop), samples: 200, rng: Random(4)).solver, isNull);
    expect(s.street, Street.river);
  });
}
