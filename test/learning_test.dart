import 'dart:math';

import 'package:felt/app/achievements.dart';
import 'package:felt/app/bankroll.dart';
import 'package:felt/app/career.dart';
import 'package:felt/app/drill_progress.dart';
import 'package:felt/app/learn_progress.dart';
import 'package:felt/app/skills.dart';
import 'package:felt/learn/lessons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poker_engine/poker_engine.dart';

void main() {
  group('skill ratings', () {
    test('a perfect player climbs, a coin-flipper stays near the middle, a bad one sinks', () {
      final perfect = SkillRatings.memory(), random = SkillRatings.memory(), bad = SkillRatings.memory();
      final rng = Random(1);
      for (var i = 0; i < 300; i++) {
        perfect.record(Skill.maths, 1);
        random.record(Skill.maths, rng.nextBool() ? 1 : 0);
        bad.record(Skill.maths, rng.nextDouble() < 0.2 ? 1 : 0);
      }
      expect(perfect.ratings[Skill.maths]!.rating, greaterThan(1700));
      expect(random.ratings[Skill.maths]!.rating, closeTo(SkillRatings.difficulty, 90));
      expect(bad.ratings[Skill.maths]!.rating, lessThan(1250));
      expect(perfect.ratings[Skill.maths]!.history, isNotEmpty);
    });

    test('decisions and drills map to the right skills', () {
      DecisionReview r(Street s, [MistakeKind? k]) =>
          DecisionReview(street: s, taken: '', recommended: '', grade: Grade.best, explanation: '', kind: k);
      expect(skillForReview(r(Street.preflop)), Skill.preflop);
      expect(skillForReview(r(Street.turn)), Skill.postflop);
      expect(skillForReview(r(Street.river)), Skill.river);
      expect(skillForReview(r(Street.preflop, MistakeKind.shoveTooLoose)), Skill.pushFold);
      expect(skillForReview(r(Street.preflop, MistakeKind.callShoveTooLoose)), Skill.icm);
      expect(skillForDrill(DrillKind.outs), Skill.maths);
      expect(skillForDrill(DrillKind.pushFold), Skill.pushFold);
    });
  });

  group('spaced repetition and the daily plan', () {
    test('good sessions space reviews out; a bad one brings it back tomorrow', () {
      final day = DateTime(2026, 1, 1);
      final c = ReviewCard('drill:outs');
      c.review(1.0, day);
      expect(c.due, DateTime(2026, 1, 2));
      c.review(0.9, day);
      expect(c.due, DateTime(2026, 1, 4));
      c.review(1.0, day);
      expect(c.interval, greaterThan(3));
      c.review(0.2, day);
      expect(c.interval, 1);
      expect(c.ease, greaterThanOrEqualTo(1.3));
    });

    test('streaks count consecutive days', () {
      final p = LearnProgress.memory();
      for (final d in [1, 2, 3, 5, 6]) {
        p.recordActivity('drill:outs', 1, now: DateTime(2026, 1, d, 12));
      }
      expect(p.streakOn(DateTime(2026, 1, 6, 20)), 2);
      expect(p.streakOn(DateTime(2026, 1, 7, 9)), 2, reason: 'still alive until the end of today');
      expect(p.streakOn(DateTime(2026, 1, 8)), 0);
    });

    test('the plan starts with the course and follows leaks, weak skills and due reviews', () {
      final p = LearnProgress.memory();
      final ratings = SkillRatings.memory();
      final now = DateTime(2026, 2, 1, 9);
      var plan = p.planFor(now: now, ratings: ratings);
      expect(plan.first.kind, PlanKind.lesson);
      expect(plan.first.target, allLessons.first.id);
      expect(plan.length, inInclusiveRange(3, 4));

      p.completeLesson(allLessons.first.id, 1, now: now.subtract(const Duration(days: 2)));
      for (var i = 0; i < 20; i++) {
        ratings.record(Skill.river, 0);
      }
      final leak = Leak(Street.flop, MistakeKind.missedValue)
        ..spots = 5
        ..lostBb = 10;
      plan = p.planFor(now: now, ratings: ratings, leaks: [leak]);
      final kinds = plan.map((i) => i.cardId).toList();
      expect(kinds, contains('lesson:${allLessons.first.id}'), reason: 'due for review');
      expect(kinds, contains('lesson:${allLessons[1].id}'), reason: 'next lesson');
      expect(kinds, contains('trainer:flop'), reason: 'biggest leak');
      expect(plan.length, lessThanOrEqualTo(4));
      expect(p.doneToday(plan.first, now: now), isFalse);
      p.recordActivity(plan.first.cardId, 1, now: now);
      expect(p.doneToday(plan.first, now: now), isTrue);
    });
  });

  group('career', () {
    test('promotion needs both bankroll and skill', () {
      final c = Career.memory();
      final bank = Bankroll.memory(Career.startingBankroll);
      final ratings = SkillRatings.memory();
      expect(c.allowsStake(0), isTrue);
      expect(c.allowsStake(1), isFalse);
      expect(c.allowsEvent('Sunday Million'), isFalse);
      expect(c.canPromote(bankroll: bank, ratings: ratings), isFalse);
      bank.credit(20000);
      expect(c.missingFor(bankroll: bank, ratings: ratings), ['Average skill 1250']);
      for (var i = 0; i < 40; i++) {
        ratings.record(Skill.preflop, 1);
      }
      expect(c.canPromote(bankroll: bank, ratings: ratings), isTrue);
      c.promote();
      expect(c.stageInfo.name, 'Regular');
      expect(c.allowsStake(1), isTrue);
      c.restart(bank);
      expect(c.stage, 0);
      expect(bank.balance, Career.startingBankroll);
    });

    test('the top stage has no promotion', () {
      final c = Career.memory()..stage = careerStages.length - 1;
      expect(c.next, isNull);
      expect(c.missingFor(bankroll: Bankroll.memory(), ratings: SkillRatings.memory()), isNull);
      expect(c.allowsEvent('The Big One'), isTrue);
    });
  });

  group('achievements', () {
    test('unlock once, from real hand data', () {
      final a = Achievements.memory();
      final learn = LearnProgress.memory();
      final ratings = SkillRatings.memory();
      final career = Career.memory();
      final drills = DrillProgress.memory();
      // A hand won at showdown with 7-2.
      var s = startHand(
        players: const [SeatSetup('You', 1000), SeatSetup('Bot', 1000)],
        button: 0,
        smallBlind: 5,
        bigBlind: 10,
        handNumber: 1,
        deck: [
          parseCard('7c'), parseCard('Kd'), parseCard('2h'), parseCard('Qs'), // holes: SB/BTN = You
          parseCard('3s'), parseCard('7d'), parseCard('7h'), parseCard('2c'), // burn, flop
          parseCard('4s'), parseCard('9d'), parseCard('5c'), parseCard('Jh'), // burn turn burn river
          ...List.generate(52, (i) => i).where((c) => ![
                for (final x in ['7c', 'Kd', '2h', 'Qs', '3s', '7d', '7h', '2c', '4s', '9d', '5c', 'Jh']) parseCard(x)
              ].contains(c)),
        ],
      );
      while (!s.isComplete) {
        s = applyAction(s, legalActions(s).canCheck ? const PlayerAction.check() : const PlayerAction.call());
      }
      final hand = HandHistory.fromState(s, heroSeat: 0);
      expect(hand.heroNet, greaterThan(0));
      a.evaluate(hands: [hand], results: const [], learn: learn, ratings: ratings, career: career, drills: drills);
      expect(a.has(Achievement.firstHand), isTrue);
      expect(a.has(Achievement.firstPot), isTrue);
      expect(a.has(Achievement.showdown), isTrue);
      expect(a.has(Achievement.hammer), isTrue);
      expect(a.has(Achievement.student), isFalse);
      final freshCount = a.fresh.length;
      a.evaluate(hands: [hand], results: const [], learn: learn, ratings: ratings, career: career, drills: drills);
      expect(a.fresh.length, freshCount, reason: 'nothing unlocks twice');

      learn.completeLesson(allLessons.first.id, 1);
      a.evaluate(hands: const [], results: [
        TournamentResult(
            at: DateTime(2026), players: 180, buyIn: 5000, place: 1, prize: 250000, speed: BlindSpeed.regular,
            payoutStyle: PayoutStyle.standard, format: 'mtt', eventName: 'Sunday Million'),
      ], learn: learn, ratings: ratings, career: career, drills: drills);
      expect(a.has(Achievement.student), isTrue);
      expect(a.has(Achievement.finalTable), isTrue);
      expect(a.has(Achievement.mttWin), isTrue);
      expect(a.has(Achievement.millionaire), isTrue);
      expect(a.has(Achievement.legend), isFalse);
      expect(a.takeFresh(), Achievement.firstHand);
    });
  });
}
