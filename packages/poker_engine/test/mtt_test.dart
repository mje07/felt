import 'dart:math';

import 'package:poker_engine/poker_engine.dart';
import 'package:test/test.dart';

MultiTableTournament field(int n, {int seed = 1, int stack = 1500, int? guarantee}) {
  final rng = Random(seed);
  return MultiTableTournament(
    players: [
      for (var i = 0; i < n; i++)
        TablePlayer(
          name: 'P$i',
          stack: stack,
          personality: Personality.all[rng.nextInt(Personality.all.length)],
          difficulty: Difficulty.casual,
        ),
    ],
    buyIn: 100,
    speed: BlindSpeed.hyper,
    guarantee: guarantee,
    rng: rng,
  );
}

void main() {
  group('payouts', () {
    test('about 15% of the field is paid, on a falling curve that sums to the pool', () {
      for (final (n, paid) in [(18, 3), (45, 7), (90, 14), (180, 27)]) {
        final prizes = mttPrizes(n, n * 100);
        expect(prizes, hasLength(paid), reason: '$n players');
        expect(prizes.reduce((a, b) => a + b), n * 100);
        for (var i = 1; i < prizes.length; i++) {
          expect(prizes[i], lessThanOrEqualTo(prizes[i - 1]));
        }
        // The last paid place still gets more than the buy-in back.
        expect(prizes.last, greaterThan(100));
      }
      final big = mttPrizes(180, 18000);
      expect(big.first / 18000, closeTo(0.26, 0.03));
    });

    test('a guarantee raises the prize pool', () {
      final t = field(18, guarantee: 1000000);
      expect(t.prizePool, 1000000);
      expect(t.prizes.reduce((a, b) => a + b), 1000000);
    });
  });

  group('playing a tournament out', () {
    for (final n in [18, 90, 180]) {
      test('$n players: conserved chips, balanced tables, one winner, every place once', () {
        final t = field(n, seed: n);
        final total = n * 1500;
        expect(t.tables.length, (n / 9).ceil());
        final reads = TableReads();
        var rounds = 0;
        while (!t.isFinished && rounds++ < 5000) {
          t.playOtherTables(reads: reads);
          final chips = t.players.fold(0, (s, p) => s + p.stack);
          expect(chips, total, reason: 'round $rounds');
          t.balance();
          t.clock++;
          final sizes = [for (final table in t.tables) table.playerIds.length];
          expect(sizes.reduce(max) - sizes.reduce(min), lessThanOrEqualTo(1), reason: 'round $rounds: $sizes');
          expect(sizes.every((s) => s <= 9), isTrue);
          // Every live player sits at exactly one table.
          final seated = [for (final table in t.tables) ...table.playerIds];
          expect(seated.toSet().length, seated.length);
          expect(seated.length, t.playersLeft);
        }
        expect(t.isFinished, isTrue);
        expect(t.tables.length, 1);
        expect(t.places.values.toSet(), {for (var p = 1; p <= n; p++) p});
        final paidOut = [for (var i = 0; i < n; i++) t.prizeFor(i)].reduce((a, b) => a + b);
        expect(paidOut, t.prizePool);
        expect(t.players[t.winner!].stack, total);
      }, timeout: const Timeout(Duration(minutes: 5)));
    }
  });

  group('dead button', () {
    test('the big blind always moves to the next live player, even through busts', () {
      final rng = Random(5);
      final t = Tournament(
        seats: [
          for (var i = 0; i < 9; i++)
            TablePlayer(name: 'P$i', stack: 600, personality: Personality.maniac, difficulty: Difficulty.casual),
        ],
        buyIn: 10,
        speed: BlindSpeed.hyper,
        rng: rng,
      );
      final reads = TableReads();
      int? lastBb;
      var checked = 0;
      while (!t.isFinished) {
        final aliveBefore = [for (var i = 0; i < 9; i++) t.seats[i].stack > 0 && !t.places.containsKey(i)];
        var s = t.startNextHand();
        final bb = s.bigBlindSeat;
        if (lastBb != null && aliveBefore.where((a) => a).length > 2) {
          var expected = lastBb;
          do {
            expected = (expected + 1) % 9;
          } while (!aliveBefore[expected]);
          expect(bb, expected, reason: 'hand ${t.handNumber}');
          checked++;
        }
        // The small blind, when there is one, was last hand's big blind.
        if (s.smallBlindSeat >= 0 && lastBb != null && aliveBefore.where((a) => a).length > 2) {
          expect(s.smallBlindSeat, lastBb);
        }
        lastBb = bb;
        while (!s.isComplete) {
          s = applyAction(s, t.seats[s.toAct].bot!.decide(buildBotContext(s, reads: reads), rng));
        }
        t.settle(s);
      }
      expect(checked, greaterThan(20));
    });

    test('a dead small blind posts nothing and the hand still plays', () {
      var s = startHand(
        players: const [SeatSetup('A', 100), null, SeatSetup('C', 100), SeatSetup('D', 100)],
        button: 0,
        smallBlindSeat: -1,
        bigBlindSeat: 2,
        smallBlind: 5,
        bigBlind: 10,
        handNumber: 1,
        rng: Random(1),
      );
      expect(s.pot, 10);
      expect(s.toAct, 3); // first after the big blind
      while (!s.isComplete) {
        s = applyAction(s, legalActions(s).canCheck ? const PlayerAction.check() : const PlayerAction.call());
      }
      expect(s.seats.fold(0, (a, p) => a + p.stack), 300);
    });
  });
}
