import 'dart:math';

import 'package:poker_engine/poker_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

int idx(String hand) {
  final r = parseRange(hand);
  expect(r.length, 1, reason: hand);
  return r.single;
}

/// Grades the hero's (seat 0) [action] in state [s].
DecisionReview grade(HandState s, PlayerAction action, {int samples = 1500}) {
  expect(s.toAct, 0);
  final a = analyzeDecision(buildBotContext(s), samples: samples, rng: Random(1));
  return gradeDecision(a, action)!;
}

void main() {
  group('notation', () {
    test('parses common forms', () {
      expect(parseRange('77+').length, 8);
      expect(parseRange('A2s+').length, 12);
      expect(parseRange('KTo+').length, 3);
      expect(parseRange('QJs-Q9s').length, 3);
      expect(parseRange('99-55').length, 5);
      expect(parseRange('AK').length, 2);
      expect(parseRange('AKs, AKo'), parseRange('AK'));
      expect(rangeCombos(parseRange('AA')), 6);
      expect(rangeCombos(parseRange('AKs')), 4);
      expect(rangeCombos(parseRange('AKo')), 12);
      expect(startingHandName(idx('T9s')), 'T9s');
      expect(() => parseRange('AXs'), throwsFormatException);
    });
  });

  group('ranges', () {
    test('chart sizes are sensible', () {
      final utg = rangeFraction(openCharts['UTG']!.raise);
      final btn = rangeFraction(openCharts['BTN']!.raise);
      expect(utg, inInclusiveRange(0.11, 0.18));
      expect(btn, inInclusiveRange(0.38, 0.52));
      // Every position opens wider than the one before it.
      final order = ['UTG', 'MP', 'HJ', 'CO', 'BTN'];
      for (var i = 1; i < order.length; i++) {
        expect(openCharts[order[i]]!.raise.containsAll(openCharts[order[i - 1]]!.raise), isTrue,
            reason: '${order[i]} should include ${order[i - 1]}');
      }
      for (final c in [vsEarlyOpenChart, vsLateOpenChart, bbDefenseChart, vs3betChart]) {
        expect(c.raise.intersection(c.call), isEmpty);
      }
    });

    test('advice', () {
      expect(adviseFor('UTG', PreflopScenario.unopened, idx('AA')).action, PreAction.raise);
      expect(adviseFor('UTG', PreflopScenario.unopened, idx('72o')).action, PreAction.fold);
      expect(adviseFor('BTN', PreflopScenario.unopened, idx('K2s')).action, PreAction.raise);
      expect(adviseFor('BB', PreflopScenario.bbDefense, idx('T8s')).action, PreAction.call);
      expect(adviseFor('BB', PreflopScenario.unopened, idx('72o')).action, PreAction.check);
      expect(adviseFor('UTG', PreflopScenario.unopened, idx('AA')).depth, greaterThan(0));
      expect(adviseFor('UTG', PreflopScenario.unopened, idx('72o')).depth, lessThan(0));
    });
  });

  group('preflop grading', () {
    // 6 players, button 3: SB 4, BB 5, hero (seat 0) is UTG. Deal order: 4,5,0,1,2,3.
    HandState utgWith(String hand) => deal([1000, 1000, 1000, 1000, 1000, 1000],
        button: 3, deck: stackedDeck(['2c 3d', '4c 5d', hand, '8s 8d', 'Tc Td', 'Js Jd'], '2h 7s 9c 4d 3h'));

    test('folding aces is a blunder', () {
      final r = grade(utgWith('As Ah'), fold);
      expect(r.grade, Grade.blunder);
      expect(r.kind, MistakeKind.preflopTooTight);
    });

    test('raising aces is best', () {
      expect(grade(utgWith('As Ah'), raise(25)).grade, Grade.best);
    });

    test('opening 72o under the gun is at least a mistake', () {
      final r = grade(utgWith('7s 2h'), raise(25));
      expect(r.grade.index, greaterThanOrEqualTo(Grade.mistake.index));
      expect(r.kind, MistakeKind.preflopTooLoose);
      expect(grade(utgWith('7s 2h'), fold).grade, Grade.best);
    });

    test('open-limping a raising hand is flagged', () {
      final r = grade(utgWith('Ks Qs'), call);
      expect(r.kind, MistakeKind.openLimp);
    });
  });

  group('postflop grading', () {
    // Heads-up, button = seat 1 (SB), hero = seat 0 (BB) acts first postflop.
    // Deal order starts at the SB: [seat 1, seat 0].
    HandState toRiver(String villain, String hero, String board, {List<int> stacks = const [1000, 1000]}) {
      var s = deal(stacks, button: 1, deck: stackedDeck([villain, hero], board));
      s = act(s, call);
      s = act(s, check);
      while (s.street != Street.river) {
        s = act(s, check);
      }
      return s;
    }

    test('calling an all-in with the nuts is best; folding it is a blunder', () {
      var s = toRiver('Kc Kd', 'Ah Kh', 'Qh Jh Th 2c 3d');
      s = act(s, check); // hero
      s = act(s, raise(990)); // villain shoves
      expect(grade(s, call).grade, Grade.best);
      final folded = grade(s, fold);
      expect(folded.grade, Grade.blunder);
      expect(folded.kind, MistakeKind.foldingWithOdds);
    });

    test('calling a pot-size bet with nothing is a mistake or worse', () {
      var s = toRiver('Ac Ad', '7s 2h', 'Kc Qd 9h 4s 3c');
      s = act(s, check);
      s = act(s, PlayerAction(ActionType.bet, 20)); // pot is 20
      final r = grade(s, call);
      expect(r.grade.index, greaterThanOrEqualTo(Grade.mistake.index));
      expect(r.kind, MistakeKind.callingWithoutOdds);
      expect(r.requiredEquity, closeTo(1 / 3, 0.01));
    });

    test('checking the nuts on the turn misses value (equity model)', () {
      var s = deal(const [1000, 1000], button: 1, deck: stackedDeck(['Kc Kd', 'Ah Kh'], 'Qh Jh Th 2c 3d'));
      s = act(s, call);
      s = act(s, check);
      while (s.street != Street.turn) {
        s = act(s, check);
      }
      final r = grade(s, check);
      expect(r.bySolver, isFalse);
      expect(r.grade.index, greaterThanOrEqualTo(Grade.inaccuracy.index));
      expect(r.kind, MistakeKind.missedValue);
      expect(grade(s, PlayerAction(ActionType.bet, 15)).grade.index, lessThanOrEqualTo(Grade.good.index));
    });

    test('on the river the solver decides: checking the nuts out of position can be right', () {
      // Out of position with a royal flush, the solver mostly checks to let
      // the opponent bet or bluff: checking and betting are worth about the same.
      final s = toRiver('Kc Kd', 'Ah Kh', 'Qh Jh Th 2c 3d');
      final r = grade(s, check);
      expect(r.bySolver, isTrue);
      expect(r.grade.index, lessThanOrEqualTo(Grade.good.index));
      expect(grade(s, PlayerAction(ActionType.bet, 20)).grade.index, lessThanOrEqualTo(Grade.good.index));
    });
  });

  test('grades separate strong play from random play', () {
    double run(String mode) {
      final rng = Random(3);
      final hero = TablePlayer(
          name: 'Hero', stack: 1000, personality: Personality.tag, difficulty: Difficulty.expert);
      final players = [
        hero,
        for (var i = 0; i < 5; i++)
          TablePlayer(name: 'B$i', stack: 1000, personality: Personality.all[i], difficulty: Difficulty.casual),
      ];
      final game = CashGame(seats: players, smallBlind: 5, bigBlind: 10, rng: rng);
      final all = <DecisionReview>[];
      for (var h = 0; h < 400; h++) {
        for (var i = 0; i < 6; i++) {
          if (players[i].stack < 500) game.rebuy(i, 1000 - players[i].stack);
        }
        var s = game.startNextHand();
        while (!s.isComplete) {
          final ctx = buildBotContext(s);
          PlayerAction a;
          if (s.toAct == 0) {
            final l = ctx.legal;
            if (mode == 'random') {
              final r = rng.nextDouble();
              a = l.canRaise && r < 0.3
                  ? PlayerAction(l.isBet ? ActionType.bet : ActionType.raise,
                      l.minRaiseTo + rng.nextInt(l.maxRaiseTo - l.minRaiseTo + 1))
                  : (l.canFold && r < 0.6 ? fold : (l.canCheck ? check : call));
            } else {
              a = hero.bot!.decide(ctx, rng);
            }
            final rv = gradeDecision(analyzeDecision(ctx, samples: 500, rng: rng), a);
            if (rv != null) all.add(rv);
          } else {
            a = players[s.toAct].bot!.decide(ctx, rng);
          }
          s = applyAction(s, a);
        }
        game.settle(s);
      }
      return accuracyOf(all)!;
    }

    final expert = run('expert'), random = run('random');
    expect(expert, greaterThan(85));
    expect(random, lessThan(72));
    expect(expert - random, greaterThan(15));
  }, timeout: const Timeout(Duration(minutes: 5)));

  group('drills', () {
    test('outs for classic draws', () {
      int outs(String hole, String board) => outsToStraightOrBetter(parseCards(hole), parseCards(board)).length;
      expect(outs('Ah Kh', '2h 7h 9c'), 9); // flush draw
      expect(outs('8c 9d', '6h 7s Kc'), 8); // open-ended
      expect(outs('8c 9d', '5h 6s Kc'), 4); // gutshot
      expect(outs('8h 9h', '6h 7h Kc'), 15); // flush + open-ended
      expect(hitChanceByRiver(9, 3), closeTo(0.35, 0.01));
      expect(hitChanceByRiver(9, 4), closeTo(9 / 46, 1e-9));
    });

    test('exact equity', () {
      expect(exactEquity(parseCards('As Ad'), parseCards('Ks Kd'), parseCards('2c 7d 9h')), closeTo(0.91, 0.02));
      expect(exactEquity(parseCards('Ah Kh'), parseCards('Ac Kc'), parseCards('2d 7s 9h Qs')), closeTo(0.5, 0.05));
    });

    test('every generator yields one valid answer', () {
      final rng = Random(9);
      for (final kind in DrillKind.values) {
        for (var i = 0; i < 150; i++) {
          final q = generateQuestion(kind, rng);
          expect(q.answer, inInclusiveRange(0, q.choices.length - 1), reason: kind.name);
          expect(q.choices.toSet().length, q.choices.length, reason: '${kind.name}: duplicate choices ${q.choices}');
          expect(q.explanation, isNotEmpty);
          if (kind == DrillKind.potOdds) {
            final req = q.bet! / (q.pot! + 2 * q.bet!);
            expect(q.choices[q.answer], '${(req * 100).round()}%');
          }
          if (kind == DrillKind.outs) {
            expect(q.choices[q.answer], '${outsToStraightOrBetter(q.hole, q.board).length}');
          }
        }
      }
    });
  });

  test('history keeps reviews through JSON, and old records still load', () {
    final game = CashGame(
        seats: [TablePlayer(name: 'A', stack: 500, isHuman: true), TablePlayer(name: 'B', stack: 500)],
        smallBlind: 5,
        bigBlind: 10,
        rng: Random(3));
    var s = game.startNextHand();
    final reviews = <DecisionReview>[];
    while (!s.isComplete) {
      final l = legalActions(s);
      final a = l.canCheck ? check : call;
      if (s.toAct == 0) {
        reviews.add(gradeDecision(analyzeDecision(buildBotContext(s), samples: 200), a) ??
            const DecisionReview(street: Street.preflop, taken: 'x', recommended: 'x', grade: Grade.good, explanation: ''));
      }
      s = applyAction(s, a);
    }
    final h = HandHistory.fromState(s, heroSeat: 0, reviews: reviews);
    final back = HandHistory.decode(h.encode());
    expect(back.reviews.length, reviews.length);
    expect(back.reviews.first.grade, reviews.first.grade);
    final old = h.toJson()..remove('reviews');
    expect(HandHistory.fromJson(old).reviews, isEmpty);
    final st = computeStats([back]);
    expect(st.decisions, reviews.length);
  });
}
