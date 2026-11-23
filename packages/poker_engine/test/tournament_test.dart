import 'dart:math';

import 'package:poker_engine/poker_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

List<int> holeFor(String hand) {
  final r = parseRange(hand).first;
  final row = r ~/ 13, col = r % 13;
  if (row == col) return [makeCard(row, 0), makeCard(row, 1)];
  return row > col ? [makeCard(row, 0), makeCard(col, 0)] : [makeCard(col, 0), makeCard(row, 1)];
}

void main() {
  group('antes', () {
    test('big blind posts a dead ante', () {
      final s = startHand(
        players: const [SeatSetup('A', 1000), SeatSetup('B', 1000), SeatSetup('C', 1000)],
        button: 0,
        smallBlind: 100,
        bigBlind: 200,
        ante: 200,
        handNumber: 1,
        deck: List<int>.generate(52, (i) => i),
      );
      final bb = s.seats[s.bigBlindSeat];
      expect(bb.stack, 600);
      expect(bb.streetBet, 200, reason: 'ante is not part of the street bet');
      expect(s.pot, 500);
      expect(s.currentBet, 200);
      expect(s.log.whereType<AntePosted>().single.amount, 200);
    });

    test('short big blind posts the blind first, then what is left', () {
      final s = startHand(
        players: const [SeatSetup('A', 1000), SeatSetup('B', 250)],
        button: 0,
        smallBlind: 100,
        bigBlind: 200,
        ante: 200,
        handNumber: 1,
        deck: List<int>.generate(52, (i) => i),
      );
      final bb = s.seats[1];
      expect(bb.stack, 0);
      expect(bb.allIn, isTrue);
      expect(s.log.whereType<AntePosted>().single.amount, 50);
    });

    test('antes are conserved through random hands', () {
      final rng = Random(4);
      for (var h = 0; h < 3000; h++) {
        final n = 2 + rng.nextInt(8);
        final stacks = [for (var i = 0; i < n; i++) 1 + rng.nextInt(3000)];
        var s = startHand(
          players: [for (var i = 0; i < n; i++) SeatSetup('P$i', stacks[i])],
          button: rng.nextInt(n),
          smallBlind: 50,
          bigBlind: 100,
          ante: 100,
          handNumber: h,
          rng: rng,
        );
        while (!s.isComplete) {
          final l = legalActions(s);
          final r = rng.nextDouble();
          s = applyAction(
              s,
              l.canRaise && r < 0.3
                  ? PlayerAction(ActionType.raise, l.maxRaiseTo)
                  : (l.canFold && r < 0.5 ? fold : (l.canCheck ? check : call)));
        }
        expect(s.seats.fold(0, (a, p) => a + p.stack), stacks.fold(0, (a, b) => a + b));
      }
    });
  });

  group('payouts and levels', () {
    test('prizes sum to the pool', () {
      for (final style in PayoutStyle.values) {
        for (var n = 2; n <= 9; n++) {
          final p = prizesFor(style, n, 333);
          expect(p.fold(0, (a, b) => a + b), 333 * n);
          expect(p, orderedEquals([...p]..sort((a, b) => b.compareTo(a))));
        }
      }
      expect(prizesFor(PayoutStyle.standard, 9, 100), [450, 270, 180]);
      expect(prizesFor(PayoutStyle.standard, 6, 100), [390, 210]);
      expect(prizesFor(PayoutStyle.winnerTakesAll, 9, 100), [900]);
    });

    test('levels rise and keep doubling', () {
      expect(levelAt(0).bigBlind, 20);
      expect(levelAt(5).ante, 200);
      expect(levelAt(blindLevels.length).bigBlind, blindLevels.last.bigBlind * 2);
    });
  });

  group('ICM', () {
    test('matches a hand-computed three-way case', () {
      final e = icmEquities([50, 30, 20], [50, 30, 20]);
      expect(e[0], closeTo(38.3929, 1e-3));
      expect(e[1], closeTo(32.75, 1e-3));
      expect(e[2], closeTo(28.8571, 1e-3));
    });

    test('basic properties', () {
      final e = icmEquities([1000, 1000, 1000, 1000], [50, 30, 20]);
      for (final x in e) {
        expect(x, closeTo(25, 1e-9));
      }
      final wta = icmEquities([100, 300, 600], [1000]);
      expect(wta, [closeTo(100, 1e-9), closeTo(300, 1e-9), closeTo(600, 1e-9)]);
      final bust = icmEquities([0, 500, 500], [70, 30]);
      expect(bust[0], 0);
      expect(bust.fold(0.0, (a, b) => a + b), closeTo(100, 1e-9));
    });
  });

  test('simultaneous busts: bigger starting stack finishes higher', () {
    final t = Tournament(
      seats: [
        TablePlayer(name: 'A', stack: 100),
        TablePlayer(name: 'B', stack: 200),
        TablePlayer(name: 'C', stack: 5000),
      ],
      buyIn: 10,
      payoutStyle: PayoutStyle.standard,
      rng: Random(1),
    );
    t.button = 1; // next hand: button 2, SB 0, BB 1
    // Deal order from the SB: seats 0, 1, 2. Seat 2 makes a full house.
    var s = t.startNextHand(deck: stackedDeck(['2c 7d', '3c 8d', 'Ah Ad'], 'As Ac 4h 4s 9c'));
    expect(s.toAct, 2);
    s = act(s, raise(5000));
    s = act(s, call);
    s = act(s, call);
    final out = t.settle(s);
    expect(out.map((e) => e.seat), [0, 1]);
    expect(t.places, {0: 3, 1: 2, 2: 1});
    expect(t.isFinished, isTrue);
    expect(t.winner, 2);
  });

  test('bot Sit & Gos always finish with one winner and correct prizes', () {
    final rng = Random(21);
    for (var g = 0; g < 120; g++) {
      final n = 2 + rng.nextInt(8);
      final speed = BlindSpeed.values[rng.nextInt(3)];
      final style = PayoutStyle.values[rng.nextInt(2)];
      final t = Tournament(
        seats: [
          for (var i = 0; i < n; i++)
            TablePlayer(
              name: 'B$i',
              stack: StartingStack.short.chips,
              personality: Personality.all[rng.nextInt(Personality.all.length)],
              difficulty: Difficulty.casual,
            ),
        ],
        buyIn: 100,
        speed: speed,
        payoutStyle: style,
        rng: rng,
      );
      final total = n * StartingStack.short.chips;
      var hands = 0;
      while (!t.isFinished && hands < 3000) {
        expect(t.currentLevel, levelAt(hands ~/ speed.handsPerLevel));
        var s = t.startNextHand();
        while (!s.isComplete) {
          s = applyAction(s, t.seats[s.toAct].bot!.decide(buildBotContext(s), rng));
        }
        t.settle(s);
        hands++;
        expect(t.seats.fold(0, (a, p) => a + p.stack), total, reason: 'chips conserved');
      }
      expect(t.isFinished, isTrue, reason: 'game $g finished');
      expect(t.places.values.toSet(), {for (var p = 1; p <= n; p++) p});
      expect(t.seats[t.winner!].stack, total);
      final paid = [for (var i = 0; i < n; i++) t.prizeFor(i)].fold(0, (a, b) => a + b);
      expect(paid, t.prizePool);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('simulateRest finishes a tournament of bots', () {
    final t = Tournament(
      seats: [for (var i = 0; i < 6; i++) TablePlayer(name: 'B$i', stack: 1000, personality: Personality.lag)],
      buyIn: 50,
      speed: BlindSpeed.hyper,
      rng: Random(5),
    );
    t.simulateRest();
    expect(t.isFinished, isTrue);
    expect(t.places.length, 6);
  });

  group('push / fold', () {
    test('ranges widen as stacks shrink and position gets later', () {
      const order = ['UTG', 'MP', 'HJ', 'CO', 'BTN', 'SB'];
      for (final pos in order) {
        for (var i = 1; i < pushFoldStacks.length; i++) {
          expect(shoveWidth(pos, pushFoldStacks[i]), greaterThanOrEqualTo(shoveWidth(pos, pushFoldStacks[i - 1])));
        }
      }
      for (final b in pushFoldStacks) {
        for (var i = 1; i < order.length; i++) {
          expect(shoveWidth(order[i], b), greaterThan(shoveWidth(order[i - 1], b)));
        }
      }
      expect(topFraction(0.1).contains(parseRange('AA').single), isTrue);
    });

    test('grading short-stack shoves', () {
      // 6 players, button 3: SB 4, BB 5, hero (seat 0) is UTG with 10 bb.
      HandState spot(String hand) => deal([100, 1000, 1000, 1000, 1000, 1000],
          button: 3, deck: stackedDeck(['2c 3d', '4c 5d', hand, '8s 8d', 'Tc Td', 'Js Jd'], '2h 7s 9c 4d 3h'));
      DecisionReview g(String hand, PlayerAction a) =>
          gradeDecision(analyzeDecision(buildBotContext(spot(hand)), rng: Random(1)), a)!;
      expect(g('As Ah', raise(100)).grade, Grade.best);
      final folded = g('As Ah', fold);
      expect(folded.grade, Grade.blunder);
      expect(folded.kind, MistakeKind.shoveTooTight);
      final wide = g('7s 2h', raise(100));
      expect(wide.kind, MistakeKind.shoveTooLoose);
      expect(wide.grade.index, greaterThanOrEqualTo(Grade.mistake.index));
    });

    test('ICM makes bubble calls tighter than chips do', () {
      HandState bubble(String hand) {
        final t = Tournament(
          seats: [
            for (final (n, s) in [('Hero', 3000), ('Leo', 3000), ('Short', 1000), ('X', 1), ('Y', 1), ('Z', 1)])
              TablePlayer(name: n, stack: s, personality: Personality.tag),
          ],
          buyIn: 100,
          speed: BlindSpeed.hyper,
          rng: Random(1),
        );
        for (final i in [3, 4, 5]) {
          t.seats[i].stack = 0;
          t.places[i] = i + 1;
        }
        t.handNumber = 25; // level 6: 100/200, ante 200
        t.button = 0; // next button: seat 1 (Leo); SB seat 2; BB seat 0 (hero)
        var s = t.startNextHand();
        s.seats[0].hole = holeFor(hand);
        s = act(s, raise(s.seats[1].stack + s.seats[1].streetBet)); // Leo shoves
        s = act(s, fold); // short stack folds
        return s;
      }

      const info = TournamentInfo(prizes: [390, 210], playersLeft: 3);
      final s = bubble('KQo');
      final icm = analyzeDecision(buildBotContext(s, tournament: info), samples: 4000, rng: Random(2));
      final chips = analyzeDecision(buildBotContext(s), samples: 4000, rng: Random(2));
      expect(icm.shoveCall!.icm, isTrue);
      expect(icm.shoveCall!.onBubble, isTrue);
      expect(chips.shoveCall!.callIsBetter, isTrue, reason: 'a call in chips');
      expect(icm.shoveCall!.callIsBetter, isFalse, reason: 'a fold under ICM');
      final r = gradeDecision(icm, call)!;
      expect(r.kind, MistakeKind.callShoveTooLoose);
      expect(r.explanation, contains('bubble'));

      final aa = analyzeDecision(buildBotContext(bubble('AA'), tournament: info), samples: 4000, rng: Random(2));
      expect(aa.shoveCall!.callIsBetter, isTrue, reason: 'aces still call');
    });

    test('push/fold drill questions have one valid answer', () {
      final rng = Random(3);
      for (var i = 0; i < 200; i++) {
        final q = generateQuestion(DrillKind.pushFold, rng);
        expect(q.choices.length, 2);
        expect(q.answer, inInclusiveRange(0, 1));
      }
    });
  });

  test('tournament results and hand modes round-trip', () {
    final r = TournamentResult(
      at: DateTime(2026, 11, 23),
      players: 6,
      buyIn: 500,
      place: 2,
      prize: 1050,
      speed: BlindSpeed.turbo,
      payoutStyle: PayoutStyle.standard,
    );
    final back = TournamentResult.fromJson(r.toJson());
    expect(back.place, 2);
    expect(back.profit, 550);
    expect(back.speed, BlindSpeed.turbo);
  });
}
