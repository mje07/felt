import 'dart:io';
import 'dart:math';

import 'package:poker_engine/poker_engine.dart';
import 'package:test/test.dart';

void main() {
  final text = File('test/fixtures/sample_hands.txt').readAsStringSync();

  group('hand-history import', () {
    late ImportResult r;
    setUpAll(() => r = importHandHistories(text));

    test('reads PokerStars and GGPoker hands and skips what it can\'t replay', () {
      expect(r.hands, hasLength(4));
      expect(r.skipped, hasLength(1));
      expect(r.skipped.single, contains('straddle'));
      expect(r.site, 'PokerStars');
      expect(r.hands.map((h) => h.source), ['PokerStars', 'PokerStars', 'PokerStars', 'GGPoker']);
    });

    test('player results match the hand histories (rake included)', () {
      // Cash amounts are in cents; tournament amounts in chips.
      expect(r.hands.map((h) => h.heroNet), [268, 0, 860, 15]);
      expect(r.hands.map((h) => h.mode), ['cash', 'cash', 'sng', 'cash']);
      expect(r.hands[0].summary, r'You win $5.53');
      expect(r.hands[1].summary, r'Villain2 wins $0.25');
    });

    test('the replay keeps cards, positions and showdowns', () {
      final first = r.hands[0];
      expect(first.heroHole, parseCards('Ah Kd'));
      final start = first.events.first;
      expect(start['bb'], 10);
      final showdown = first.events.firstWhere((e) => e['e'] == 'showdown');
      expect((showdown['hands'] as Map).length, 2);
      // A player sitting out isn't dealt in.
      final second = r.hands[1].events.first;
      expect((second['seats'] as List).length, 5);
      // Everyone's ante shows up in the tournament hand.
      expect(r.hands[2].events.where((e) => e['e'] == 'ante').length, 3);
      // Final stacks add up.
      final end = r.hands[0].events.last;
      expect(end['e'], 'end');
      expect((end['stacks'] as Map)['${r.hands[0].heroSeat}'], 1268);
    });

    test('imported hands feed the statistics', () {
      final stats = computeStats(r.hands);
      expect(stats.hands, 4);
      expect(stats.vpip, 3); // raised in three hands, folded one
      expect(stats.showdowns, 2);
    });

    test('round-trips through JSON with its source', () {
      final back = HandHistory.decode(r.hands[3].encode());
      expect(back.source, 'GGPoker');
      expect(back.sourceId, 'RC1234567890');
      expect(back.isImported, isTrue);
    });
  });

  test('the coach can grade imported decisions', () {
    final r = importHandHistories(text, review: true, samples: 300);
    final first = r.hands.first;
    expect(first.reviews.length, greaterThanOrEqualTo(3)); // preflop, flop, turn, river
    expect(first.reviews.first.street, Street.preflop);
    expect(first.reviews.any((x) => x.street == Street.river), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('progress is reported per hand', () {
    final seen = <int>[];
    importHandHistories(text, onProgress: (done, total) {
      seen.add(done);
      expect(total, 5);
    });
    expect(seen, [1, 2, 3, 4, 5]);
  });


  group('export', () {
    test('imported hands survive export and re-import', () {
      final first = importHandHistories(text).hands;
      final again = importHandHistories(exportPokerStars(first));
      expect(again.skipped, isEmpty);
      expect(again.hands.map((h) => h.heroNet), first.map((h) => h.heroNet));
      for (var i = 0; i < first.length; i++) {
        List<String> acts(HandHistory h) => [for (final e in h.events) if (e['e'] == 'act') '${e['seat']}${e['type']}${e['to']}'];
        expect(acts(again.hands[i]), acts(first[i]));
        expect(again.hands[i].heroHole, first[i].heroHole);
      }
    });

    test('hands played in Felt export and import with the same result', () {
      final game = CashGame(
        seats: [
          TablePlayer(name: 'You', stack: 1000, isHuman: true),
          for (var i = 0; i < 3; i++) TablePlayer(name: 'Bot$i', stack: 1000, personality: Personality.all[i]),
        ],
        smallBlind: 5,
        bigBlind: 10,
        rng: Random(4),
      );
      final played = <HandHistory>[];
      for (var n = 0; n < 40; n++) {
        var s = game.startNextHand();
        while (!s.isComplete) {
          final p = game.seats[s.toAct]!;
          s = applyAction(s, p.isHuman
              ? (legalActions(s).canCheck ? const PlayerAction.check() : const PlayerAction.call())
              : p.bot!.decide(buildBotContext(s), Random(n)));
        }
        game.settle(s);
        played.add(HandHistory.fromState(s, heroSeat: 0));
      }
      final back = importHandHistories(exportPokerStars(played));
      expect(back.skipped, isEmpty);
      expect(back.hands.map((h) => h.heroNet).toList(), played.map((h) => h.heroNet).toList());
    });
  });
}
