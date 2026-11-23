import 'dart:math';

import 'package:poker_engine/poker_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('heads-up: button posts SB, acts first preflop and last postflop', () {
    var s = deal([1000, 1000], button: 0);
    expect(s.smallBlindSeat, 0);
    expect(s.bigBlindSeat, 1);
    expect(s.toAct, 0);
    s = act(s, call);
    expect(s.toAct, 1, reason: 'BB has the option');
    s = act(s, check);
    expect(s.street, Street.flop);
    expect(s.toAct, 1, reason: 'BB acts first postflop');
  });

  test('blinds and preflop order with 4 players', () {
    final s = deal([1000, 1000, 1000, 1000], button: 0);
    expect(s.smallBlindSeat, 1);
    expect(s.bigBlindSeat, 2);
    expect(s.toAct, 3);
    expect(s.pot, 15);
  });

  test('big blind option after limps', () {
    var s = deal([1000, 1000, 1000], button: 0);
    s = act(s, call); // button
    s = act(s, call); // SB completes
    expect(s.toAct, 2);
    final l = legalActions(s);
    expect(l.canCheck, isTrue);
    expect(l.canRaise, isTrue);
    expect(l.minRaiseTo, 20);
    s = act(s, check);
    expect(s.street, Street.flop);
    expect(s.toAct, 1, reason: 'first live seat left of button');
  });

  test('minimum raise follows the last full raise', () {
    var s = deal([1000, 1000, 1000], button: 0);
    expect(legalActions(s).minRaiseTo, 20);
    s = act(s, raise(30)); // +20
    expect(legalActions(s).minRaiseTo, 50);
    s = act(s, raise(80)); // +50
    expect(legalActions(s).minRaiseTo, 130);
    expect(() => act(s, raise(120)), throwsA(isA<IllegalActionException>()));
  });

  test('min bet postflop is the big blind', () {
    var s = deal([1000, 1000], button: 0);
    s = act(s, call);
    s = act(s, check);
    final l = legalActions(s);
    expect(l.isBet, isTrue);
    expect(l.minRaiseTo, 10);
  });

  test('short all-in raise does not reopen betting', () {
    // Seat 1 (SB) has 45 total.
    var s = deal([1000, 45, 1000], button: 0);
    s = act(s, raise(30)); // seat 0: full raise (+20)
    s = act(s, raise(45)); // seat 1: all-in, only +15
    expect(s.seats[1].allIn, isTrue);
    expect(s.toAct, 2);
    expect(legalActions(s).canRaise, isTrue, reason: 'BB has not acted yet');
    s = act(s, call);
    expect(s.toAct, 0);
    final l = legalActions(s);
    expect(l.canCall, isTrue);
    expect(l.callAmount, 15);
    expect(l.canRaise, isFalse, reason: 'incomplete raise does not reopen');
  });

  test('two short all-ins that add up to a full raise reopen action', () {
    // Preflop order: 3 (UTG), 4, 0 (btn), 1 (sb), 2 (bb).
    var s = deal([55, 1000, 1000, 1000, 45], button: 0);
    s = act(s, raise(30)); // seat 3: +20, full
    s = act(s, raise(45)); // seat 4: all-in, +15 short
    s = act(s, raise(55)); // seat 0: all-in, +10 short; +25 since seat 3 acted
    s = act(s, fold); // sb
    s = act(s, fold); // bb
    expect(s.toAct, 3);
    expect(legalActions(s).canRaise, isFalse,
        reason: 'everyone else is all-in: raising is pointless');
  });

  test('cumulative short raises reopen for a player with live opponents', () {
    var s = deal([55, 1000, 1000, 1000, 45], button: 0);
    s = act(s, raise(30)); // seat 3
    s = act(s, raise(45)); // seat 4 short all-in
    s = act(s, raise(55)); // seat 0 short all-in
    s = act(s, fold); // sb
    s = act(s, call); // bb calls 55, still has chips
    expect(s.toAct, 3);
    expect(legalActions(s).canRaise, isTrue);
  });

  test('uncalled bet is returned', () {
    var s = deal([1000, 1000], button: 0);
    s = act(s, raise(100));
    s = act(s, fold);
    expect(s.isComplete, isTrue);
    final ret = s.log.whereType<UncalledReturned>().single;
    expect(ret.seat, 0);
    expect(ret.amount, 90);
    expect(s.seats[0].stack, 1010);
    expect(s.seats[1].stack, 990);
    expect(s.log.whereType<ShowdownRevealed>(), isEmpty);
  });

  test('all-in preflop runs out the board', () {
    final deck = stackedDeck(['As Ad', 'Kc Kd'], '2h 7s 9c Jd 3h');
    var s = deal([500, 300], button: 0, deck: deck);
    s = act(s, raise(500));
    s = act(s, call);
    expect(s.isComplete, isTrue);
    expect(s.board.length, 5);
    expect(s.street, Street.showdown);
    expect(s.log.whereType<UncalledReturned>().single.amount, 200);
    expect(s.seats[0].stack, 800);
    expect(s.seats[1].stack, 0);
  });

  test('three-way side pots pay the right players', () {
    // button 0, sb 1, bb 2. Deal order: 1, 2, 0.
    // seat 0 (100): KK, seat 1 (300): QQ, seat 2 (50): AA
    final deck = stackedDeck(['Qc Qd', 'Ac Ad', 'Kc Kd'], '2h 7s 9c 4d 3h');
    var s = deal([100, 300, 50], button: 0, deck: deck);
    s = act(s, raise(100)); // seat 0 all-in
    s = act(s, raise(300)); // seat 1 all-in
    s = act(s, call); // seat 2 all-in for 50
    expect(s.isComplete, isTrue);
    // Main 150 -> AA (seat 2). Side 100 -> KK (seat 0). Uncalled 200 -> seat 1.
    expect(s.seats[2].stack, 150);
    expect(s.seats[0].stack, 100);
    expect(s.seats[1].stack, 200);
  });

  test('split pot with odd chip goes left of the button', () {
    // Board is a royal flush: every live player splits.
    final deck = stackedDeck(['2c 3d', '4c 5d', '6c 7d'], 'Ah Kh Qh Jh Th');
    var s = deal([1000, 1000, 1000], button: 0, deck: deck);
    s = act(s, call); // btn
    s = act(s, fold); // sb folds its 5
    s = act(s, check); // bb
    while (!s.isComplete) {
      s = act(s, check);
    }
    // pot 25 split by seats 0 and 2; odd chip to seat 2 (first left of button).
    expect(s.seats[2].stack, 1000 - 10 + 13);
    expect(s.seats[0].stack, 1000 - 10 + 12);
  });

  test('random legal play conserves chips and never throws', () {
    final rng = Random(7);
    for (var h = 0; h < 20000; h++) {
      final n = 2 + rng.nextInt(8);
      final stacks = [for (var i = 0; i < n; i++) 1 + rng.nextInt(400)];
      var s = startHand(
        players: [for (var i = 0; i < n; i++) SeatSetup('P$i', stacks[i])],
        button: rng.nextInt(n),
        smallBlind: 1,
        bigBlind: 2,
        handNumber: h,
        rng: rng,
      );
      final total = stacks.fold(0, (a, b) => a + b);
      while (!s.isComplete) {
        final l = legalActions(s);
        final r = rng.nextDouble();
        PlayerAction a;
        if (l.canRaise && r < 0.3) {
          a = PlayerAction(ActionType.raise,
              l.minRaiseTo + rng.nextInt(l.maxRaiseTo - l.minRaiseTo + 1));
        } else if (l.canFold && r < 0.5) {
          a = fold;
        } else {
          a = l.canCheck ? check : call;
        }
        s = applyAction(s, a);
        expect(s.totalChips, total);
      }
      expect(s.seats.fold(0, (a, p) => a + p.stack), total);
    }
  });
}
