import 'dart:math';

import 'package:poker_engine/poker_engine.dart';
import 'package:test/test.dart';

Seat seat(int i, int total, {bool folded = false}) =>
    Seat(index: i, name: 'P$i', stack: 0)
      ..totalBet = total
      ..folded = folded;

void main() {
  group('pots', () {
    test('layers by all-in level', () {
      final pots =
          buildPots([seat(0, 50), seat(1, 100), seat(2, 200), seat(3, 200)]);
      expect([for (final p in pots) p.amount], [200, 150, 200]);
      expect(pots[0].eligible, [0, 1, 2, 3]);
      expect(pots[1].eligible, [1, 2, 3]);
      expect(pots[2].eligible, [2, 3]);
    });

    test('folded chips stay in but are not eligible', () {
      final pots =
          buildPots([seat(0, 80, folded: true), seat(1, 100), seat(2, 100)]);
      expect(pots.length, 1);
      expect(pots.single.amount, 280);
      expect(pots.single.eligible, [1, 2]);
    });

    test('odd chips go clockwise from the button', () {
      final awards = awardPots(
        pots: [const Pot(101, [0, 1, 2])],
        handValues: {0: 5, 1: 5, 2: 5},
        button: 1,
        seatCount: 3,
      );
      expect(awards.single.shares, {2: 34, 0: 34, 1: 33});
    });
  });

  group('equity', () {
    test('AA vs random is about 85%', () {
      final r = monteCarloEquity(
          hole: parseCards('As Ah'),
          board: [],
          opponents: 1,
          iterations: 20000,
          rng: Random(1));
      expect(r.equity, closeTo(0.852, 0.015));
    });

    test('made nuts on the river is 100%', () {
      final r = monteCarloEquity(
          hole: parseCards('Ah Kh'),
          board: parseCards('Qh Jh Th 2c 3d'),
          opponents: 3,
          iterations: 500);
      expect(r.equity, 1.0);
    });

    test('preflop percentile ordering and names', () {
      expect(preflopPercentile(parseCard('As'), parseCard('Ad')), lessThan(0.01));
      expect(preflopPercentile(parseCard('7c'), parseCard('2d')), greaterThan(0.95));
      expect(preflopPercentile(parseCard('3c'), parseCard('2d')), 1.0);
      expect(startingHandName(startingHandIndex(parseCard('Ks'), parseCard('Qs'))), 'KQs');
      expect(startingHandName(startingHandIndex(parseCard('Ks'), parseCard('Qd'))), 'KQo');
    });
  });

  test('bots play many hands legally and conserve chips', () {
    final rng = Random(99);
    final players = [
      for (var i = 0; i < 6; i++)
        TablePlayer(
          name: 'Bot$i',
          stack: 1000,
          personality: Personality.all[i % Personality.all.length],
          difficulty: Difficulty.casual,
        ),
    ];
    final game = CashGame(seats: players, smallBlind: 5, bigBlind: 10, rng: rng);
    var shown = 0, folded = 0;
    for (var h = 0; h < 1500; h++) {
      for (var i = 0; i < players.length; i++) {
        if (players[i].stack < 200) game.rebuy(i, 1000 - players[i].stack);
      }
      final total = players.fold(0, (a, p) => a + p.stack);
      var s = game.startNextHand();
      while (!s.isComplete) {
        final bot = players[s.toAct].bot!;
        s = applyAction(s, bot.decide(buildBotContext(s), rng));
      }
      game.settle(s);
      expect(players.fold(0, (a, p) => a + p.stack), total);
      s.street == Street.showdown ? shown++ : folded++;
    }
    expect(shown, greaterThan(100));
    expect(folded, greaterThan(300));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('hand history round-trips through JSON', () {
    final game = CashGame(
        seats: [TablePlayer(name: 'A', stack: 500, isHuman: true), TablePlayer(name: 'B', stack: 500)],
        smallBlind: 5,
        bigBlind: 10,
        rng: Random(3));
    var s = game.startNextHand();
    while (!s.isComplete) {
      s = applyAction(s, legalActions(s).canCheck ? const PlayerAction.check() : const PlayerAction.call());
    }
    final h = HandHistory.fromState(s, heroSeat: 0);
    final back = HandHistory.decode(h.encode());
    expect(back.events.length, h.events.length);
    expect(back.heroNet, h.heroNet);
  });
}
