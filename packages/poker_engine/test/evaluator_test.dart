import 'package:poker_engine/poker_engine.dart';
import 'package:test/test.dart';

int ev(String s) => evaluate(parseCards(s));

void main() {
  test('category ordering on known hands', () {
    expect(categoryOf(ev('As Ks Qs Js Ts')), HandCategory.straightFlush);
    expect(categoryOf(ev('9c 9d 9h 9s 2c')), HandCategory.quads);
    expect(categoryOf(ev('Kc Kd Kh 5s 5c')), HandCategory.fullHouse);
    expect(categoryOf(ev('2h 7h 9h Jh Kh')), HandCategory.flush);
    expect(categoryOf(ev('5c 6d 7h 8s 9c')), HandCategory.straight);
    expect(categoryOf(ev('Ah 2c 3d 4s 5h')), HandCategory.straight);
    expect(categoryOf(ev('Qc Qd Qh 4s 2c')), HandCategory.trips);
    expect(categoryOf(ev('Jc Jd 4h 4s 2c')), HandCategory.twoPair);
    expect(categoryOf(ev('Tc Td 8h 4s 2c')), HandCategory.pair);
    expect(categoryOf(ev('Ac Jd 8h 4s 2c')), HandCategory.highCard);
  });

  test('wheel is the lowest straight; steel wheel is lowest straight flush', () {
    expect(ev('Ah 2c 3d 4s 5h') < ev('2c 3d 4s 5h 6c'), isTrue);
    expect(ev('Ah 2h 3h 4h 5h') < ev('2h 3h 4h 5h 6h'), isTrue);
    expect(describeHand(ev('Ah 2c 3d 4s 5h')), 'Straight, Five high');
  });

  test('7-card picks best five and kickers', () {
    // Three pairs: best two pair + best kicker (which is the third pair).
    expect(ev('Ac Ad Kc Kd Qc Qd 2s'), ev('Ac Ad Kc Kd Qs'));
    // Two trips make a full house.
    expect(describeHand(ev('9c 9d 9h 5s 5c 5d 2s')), 'Full House, Nines over Fives');
    // Flush beats straight when both are present.
    expect(categoryOf(ev('4h 5h 6c 7h 8d 9h Kh')), HandCategory.flush);
    // Straight flush inside a 7-card flush.
    expect(categoryOf(ev('4h 5h 6h 7h 8h Ah Kh')), HandCategory.straightFlush);
    // Kicker decides.
    expect(ev('Ac Ad Kc 7d 3s 2h 4c') > ev('Ah As Qc Jd 3c 2s 4d'), isTrue);
    // Board plays: split.
    expect(ev('2c 3d Ah Kh Qh Jh Th'), ev('4c 5d Ah Kh Qh Jh Th'));
    expect(describeHand(ev('Ah Kh Qh Jh Th')), 'Royal Flush');
  });

  test('exhaustive 5-card counts and 7462 distinct values', () {
    final counts = List<int>.filled(9, 0);
    final distinct = <int>{};
    final hand = List<int>.filled(5, 0);
    for (var a = 0; a < 52; a++) {
      for (var b = a + 1; b < 52; b++) {
        for (var c = b + 1; c < 52; c++) {
          for (var d = c + 1; d < 52; d++) {
            for (var e = d + 1; e < 52; e++) {
              hand[0] = a; hand[1] = b; hand[2] = c; hand[3] = d; hand[4] = e;
              final v = evaluate(hand);
              counts[v >> 20]++;
              distinct.add(v);
            }
          }
        }
      }
    }
    expect(counts, [1302540, 1098240, 123552, 54912, 10200, 5108, 3744, 624, 40]);
    expect(distinct.length, 7462);
  });

  test('exhaustive 7-card category counts', () {
    final counts = List<int>.filled(9, 0);
    final h = List<int>.filled(7, 0);
    for (var a = 0; a < 52; a++) {
      h[0] = a;
      for (var b = a + 1; b < 52; b++) {
        h[1] = b;
        for (var c = b + 1; c < 52; c++) {
          h[2] = c;
          for (var d = c + 1; d < 52; d++) {
            h[3] = d;
            for (var e = d + 1; e < 52; e++) {
              h[4] = e;
              for (var f = e + 1; f < 52; f++) {
                h[5] = f;
                for (var g = f + 1; g < 52; g++) {
                  h[6] = g;
                  counts[evaluate(h) >> 20]++;
                }
              }
            }
          }
        }
      }
    }
    expect(counts, [23294460, 58627800, 31433400, 6461620, 6180020, 4047644, 3473184, 224848, 41584]);
  }, tags: ['slow'], timeout: const Timeout(Duration(minutes: 20)));

  test('bestFive returns the made hand', () {
    final five = bestFive(parseCards('2c 3d Ah Kh Qh Jh Th'));
    expect(cardsToString(five..sort()), cardsToString(parseCards('Th Jh Qh Kh Ah')..sort()));
  });
}
