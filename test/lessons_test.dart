import 'package:felt/learn/lessons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poker_engine/poker_engine.dart';

void main() {
  test('every lesson is well formed', () {
    final ids = <String>{};
    for (final l in allLessons) {
      expect(ids.add(l.id), isTrue, reason: 'duplicate id ${l.id}');
      expect(l.pages, isNotEmpty, reason: l.id);
      expect(l.checks.length, greaterThanOrEqualTo(3), reason: l.id);
      for (final c in l.checks) {
        expect(c.answer, inInclusiveRange(0, c.options.length - 1), reason: '${l.id}: ${c.question}');
        expect(c.options.toSet().length, c.options.length, reason: '${l.id}: duplicate options');
        expect(c.why, isNotEmpty);
      }
      final figures = [for (final p in l.pages) p.figure, for (final c in l.checks) c.figure].whereType<LessonFigure>();
      for (final f in figures) {
        final cards = [...f.holeCards, ...f.boardCards];
        expect(cards.toSet().length, cards.length, reason: '${l.id}: repeated card');
        if (f.range != null) expect(parseRange(f.range!), isNotEmpty, reason: '${l.id}: ${f.range}');
      }
    }
    expect(course.length, 6);
    expect(allLessons.length, 24);
  });

  group('the numbers in the lessons are right', () {
    int value(String hole, String board) => evaluate(parseCards('$hole $board'));

    test('kickers: A-Q beats A-9 on a paired board', () {
      expect(value('Ah Qh', 'Ks Kd 7c 2h 3s'), greaterThan(value('Ac 9d', 'Ks Kd 7c 2h 3s')));
    });

    test('outs and hit chances', () {
      int outs(String hole, String board) => outsToStraightOrBetter(parseCards(hole), parseCards(board)).length;
      expect(outs('Jh Th', '9h 8h 2c'), 15);
      expect(hitChanceByRiver(9, 3), closeTo(0.35, 0.005));
      expect(hitChanceByRiver(9, 4), closeTo(0.196, 0.001));
      expect(hitChanceByRiver(8, 4), closeTo(0.174, 0.001));
      expect(hitChanceByRiver(4, 4), closeTo(0.087, 0.001));
    });

    test('a 15-out draw is a slight favourite against aces on the flop', () {
      WeightedRange hand(String c) {
        final x = parseCards(c);
        return WeightedRange()..[comboIndex(x[0], x[1])] = 1;
      }

      final e = rangeVsRange([hand('Jh Th'), hand('Ac Ad')], parseCards('9h 8h 2c'));
      expect(e.equity.first, closeTo(0.54, 0.03));
    });

    test('push/fold examples match the charts', () {
      final btn10 = shoveRange(shoveWidth('BTN', 10));
      expect(btn10.contains(startingHandIndex(parseCard('Kd'), parseCard('7d'))), isTrue);
      final utg8 = shoveRange(shoveWidth('UTG', 8));
      expect(utg8.contains(startingHandIndex(parseCard('9c'), parseCard('4d'))), isFalse);
    });
  });
}
