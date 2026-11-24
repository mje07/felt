import 'dart:math';

import 'package:poker_engine/poker_engine.dart';
import 'package:test/test.dart';


void main() {
  group('exact ranges', () {
    test('a range holds only hands within its width', () {
      for (final w in [0.004, 0.04, 0.1, 0.22, 0.5]) {
        final r = preflopRange(w);
        expect(r, isNotEmpty);
        for (final c in r) {
          expect(preflopPercentile(comboA(c), comboB(c)), lessThanOrEqualTo(max(w, 0.0046) + 1e-9));
        }
        expect(r.length / 1326, closeTo(w, 0.02), reason: 'width $w');
      }
      expect(preflopRange(1.0).length, 1326);
    });

    test('dead cards are removed', () {
      final dead = parseCards('As Ah');
      for (final c in preflopRange(0.1, dead: dead)) {
        expect(dead, isNot(contains(comboA(c))));
        expect(dead, isNot(contains(comboB(c))));
      }
    });

    test('sampling is uniform over the range and never strays outside it', () {
      final range = preflopRange(0.05);
      final counts = <int, int>{};
      final rng = Random(1);
      const draws = 60000;
      for (var i = 0; i < draws; i++) {
        final c = sampleCombo(range, 0, rng);
        expect(range, contains(c));
        final cls = startingHandIndex(comboA(c), comboB(c));
        counts[cls] = (counts[cls] ?? 0) + 1;
      }
      // Each class's share matches its combo count (chi-square, loose bound).
      final perClass = <int, int>{};
      for (final c in range) {
        final cls = startingHandIndex(comboA(c), comboB(c));
        perClass[cls] = (perClass[cls] ?? 0) + 1;
      }
      var chi = 0.0;
      for (final e in perClass.entries) {
        final expected = draws * e.value / range.length;
        final d = (counts[e.key] ?? 0) - expected;
        chi += d * d / expected;
      }
      expect(chi, lessThan(perClass.length * 3.0));
    });

    test('equity against a narrow range is not diluted by random hands', () {
      // KK vs AA only is about 18%. The old rejection sampler mixed in random
      // hands and reported far more.
      final e = monteCarloEquity(
        hole: parseCards('Kc Kd'),
        board: const [],
        opponents: 1,
        iterations: 6000,
        rng: Random(2),
        opponentRanges: const [0.004],
      ).equity;
      expect(e, closeTo(0.18, 0.03));
    });
  });

  group('board-aware narrowing', () {
    double share(List<int> combos, List<int> board, bool Function(int a, int b) test) =>
        combos.where((c) => test(comboA(c), comboB(c))).length / combos.length;

    bool strong(int a, int b, List<int> board) =>
        categoryOf(evaluate([a, b, ...board])).index >= HandCategory.twoPair.index ||
        drawOuts(a, b, board) >= 8;

    test('a bettor on a connected board holds more sets, straights and draws', () {
      final board = parseCards('9s 8s 7d');
      final before = preflopRange(0.5, dead: board);
      final after = narrowRange(before, board, RangeAction.bet);
      final strongBefore = share(before, board, (a, b) => strong(a, b, board));
      final strongAfter = share(after, board, (a, b) => strong(a, b, board));
      expect(strongAfter, greaterThan(strongBefore * 1.2));
      // Overpairs no longer dominate: two pair+, straights and draws outnumber AA/KK.
      final bigPairs = share(after, board, (a, b) => cardRank(a) == cardRank(b) && cardRank(a) >= 11);
      expect(strongAfter, greaterThan(bigPairs * 3));
    });

    test('a bettor still bluffs, more so when they bet a lot', () {
      final board = parseCards('Kd 7c 2h 4s 9d');
      final before = preflopRange(0.5, dead: board);
      final normal = narrowRange(before, board, RangeAction.bet);
      final maniac = narrowRange(before, board, RangeAction.bet, aggression: 2.5);
      bool air(int a, int b) => categoryOf(evaluate([a, b, ...board])) == HandCategory.highCard;
      expect(share(normal, board, air), greaterThan(0.05));
      expect(share(maniac, board, air), greaterThan(share(normal, board, air)));
    });

    test('draw outs', () {
      expect(drawOuts(parseCards('As 5s')[0], parseCards('As 5s')[1], parseCards('Ks 9s 2d')), 9);
      expect(drawOuts(parseCards('Jc Th')[0], parseCards('Jc Th')[1], parseCards('9s 8d 2c')), 8);
      expect(drawOuts(parseCards('Jc 2h')[0], parseCards('Jc 2h')[1], parseCards('9s 8d Tc')), 8); // J-T-9-8: a 7 or a Q
      expect(drawOuts(parseCards('Ac Kh')[0], parseCards('Ac Kh')[1], parseCards('9s 8d 2c 3h 4s')), 0); // river
    });
  });

  group('tournament bots', () {
    // Three-handed at 10 big blinds; the button acts first preflop.
    HandState spot(String hole) {
      final h = parseCards(hole);
      final deck = [for (var c = 0; c < 52; c++) if (!h.contains(c)) c];
      // Deal order: SB, BB, BTN, SB, BB, BTN.
      deck.insert(2, h[0]);
      deck.insert(5, h[1]);
      return startHand(
        players: const [SeatSetup('Btn', 100), SeatSetup('Sb', 100), SeatSetup('Bb', 100)],
        button: 0,
        smallBlind: 5,
        bigBlind: 10,
        handNumber: 1,
        deck: deck,
      );
    }

    const info = TournamentInfo(prizes: [450, 270, 180], playersLeft: 3);
    const bot = HeuristicBot(Personality.tag, Difficulty.expert);

    test('expert bots shove a premium hand and fold trash at 10bb', () {
      final rng = Random(4);
      final aa = bot.decide(buildBotContext(spot('Ah As'), tournament: info), rng);
      expect(aa.type, ActionType.raise);
      expect(aa.amount, 100);
      final trash = bot.decide(buildBotContext(spot('7c 2d'), tournament: info), rng);
      expect(trash.type, ActionType.fold);
    });

    test('outside tournaments the normal strategy applies', () {
      final aa = bot.decide(buildBotContext(spot('Ah As')), Random(4));
      expect(aa.type, ActionType.raise);
    });
  });
}
