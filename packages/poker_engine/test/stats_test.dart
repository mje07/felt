import 'dart:math';

import 'package:poker_engine/poker_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

HandHistory record(HandState s) => HandHistory.fromState(s, heroSeat: 0);

void main() {
  test('positions at a 6-max table', () {
    final active = [0, 1, 2, 3, 4, 5];
    String pos(int seat) => positionOf(seat: seat, button: 0, bbSeat: 2, active: active);
    expect([for (var i = 0; i < 6; i++) pos(i)], ['BTN', 'SB', 'BB', 'UTG', 'HJ', 'CO']);
    expect(positionOf(seat: 1, button: 0, bbSeat: 1, active: [0, 1]), 'BB');
    expect(positionOf(seat: 0, button: 0, bbSeat: 1, active: [0, 1]), 'BTN');
    final nine = [for (var i = 0; i < 9; i++) i];
    expect([for (var i = 3; i < 9; i++) positionOf(seat: i, button: 0, bbSeat: 2, active: nine)],
        ['UTG', 'MP', 'MP', 'MP', 'HJ', 'CO']);
  });

  test('open-raise that takes the blinds', () {
    // 3-handed, hero on the button acts first preflop.
    var s = deal([1000, 1000, 1000], button: 0);
    s = act(s, raise(30));
    s = act(s, fold);
    s = act(s, fold);
    final st = computeStats([record(s)]);
    expect(st.hands, 1);
    expect(st.vpip, 1);
    expect(st.pfr, 1);
    expect(st.handsWon, 1);
    expect(st.netChips, 15);
    expect(st.netBb, 1.5);
    expect(st.sawFlop, 0);
    expect(st.byPosition['BTN']!.hands, 1);
  });

  test('calling a raise, then folding to the c-bet', () {
    // Hero is the big blind (seat 0) with button at seat 1, 3-handed:
    // button=1, sb=2, bb=0. Preflop order: 1, 2, 0.
    var s = deal([1000, 1000, 1000], button: 1);
    expect(s.bigBlindSeat, 0);
    s = act(s, raise(30)); // seat 1 opens
    s = act(s, fold); // seat 2
    s = act(s, call); // hero calls (faced one raise: 3-bet opportunity, not taken)
    // Flop: hero (BB) first to act.
    s = act(s, check);
    s = act(s, PlayerAction(ActionType.bet, 30)); // c-bet by preflop raiser
    s = act(s, fold);
    final st = computeStats([record(s)]);
    expect(st.vpip, 1);
    expect(st.pfr, 0);
    expect(st.threeBetOpp, 1);
    expect(st.threeBet, 0);
    expect(st.sawFlop, 1);
    expect(st.foldToCbetOpp, 1);
    expect(st.foldToCbet, 1);
    expect(st.postChecks, 1);
    expect(st.postFolds, 1);
    expect(st.netChips, -30);
    expect(st.byPosition['BB']!.netBb, -3);
  });

  test('c-bet and showdown accounting', () {
    final deck = stackedDeck(['2c 3d', 'As Ad'], 'Kh 7s 2h 9c 4d');
    var s = deal([1000, 1000], button: 1, deck: deck); // HU: button=1 is SB, hero=0 is BB
    s = act(s, call); // seat 1 limps
    s = act(s, raise(40)); // hero raises
    s = act(s, call);
    s = act(s, PlayerAction(ActionType.bet, 40)); // hero c-bets (BB acts first postflop)
    s = act(s, call);
    while (!s.isComplete) {
      s = act(s, check);
    }
    final st = computeStats([record(s)]);
    expect(st.cbetOpp, 1);
    expect(st.cbet, 1);
    expect(st.showdowns, 1);
    expect(st.wonAtShowdown, 1);
    expect(categoryOf(st.bestHandValue!), HandCategory.pair);
    expect(st.handCount[startingHandIndex(parseCard('As'), parseCard('Ad'))], 1);
  });

  test('bot personalities are classified as what they are', () {
    Archetype classify(Personality p) {
      final rng = Random(5);
      final players = [
        TablePlayer(name: 'Hero', stack: 1000, personality: p, difficulty: Difficulty.casual),
        for (var i = 0; i < 5; i++)
          TablePlayer(name: 'B$i', stack: 1000, personality: Personality.tag, difficulty: Difficulty.casual),
      ];
      final game = CashGame(seats: players, smallBlind: 5, bigBlind: 10, rng: rng);
      final hands = <HandHistory>[];
      for (var h = 0; h < 1200; h++) {
        for (var i = 0; i < players.length; i++) {
          if (players[i].stack < 500) game.rebuy(i, 1000 - players[i].stack);
        }
        var s = game.startNextHand();
        while (!s.isComplete) {
          s = applyAction(s, players[s.toAct].bot!.decide(buildBotContext(s), rng));
        }
        game.settle(s);
        hands.add(record(s));
      }
      return profileFor(computeStats(hands))!.archetype;
    }

    expect(classify(Personality.rock), anyOf(Archetype.rock, Archetype.nit, Archetype.shark));
    expect(classify(Personality.tag), Archetype.shark);
    expect(classify(Personality.station), Archetype.station);
    expect(classify(Personality.maniac), anyOf(Archetype.maniac, Archetype.maverick));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('no profile below the minimum sample', () {
    expect(profileFor(PlayerStats()), isNull);
  });
}
