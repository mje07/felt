import 'dart:math';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:felt/app/controller.dart';
import 'package:felt/app/drill_progress.dart';
import 'package:felt/app/history_store.dart';
import 'package:felt/app/settings.dart';
import 'package:felt/main.dart';
import 'package:felt/screens/settings_panel.dart';
import 'package:felt/screens/table_screen.dart';
import 'package:felt/screens/training_screen.dart';
import 'package:felt/widgets/action_bar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poker_engine/poker_engine.dart';

Widget _host(Settings settings, Widget child) => SettingsScope(
      settings: settings,
      child: CupertinoApp(home: child),
    );

void main() {
  testWidgets('lobby shows title and Sit Down', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FeltApp(settings: Settings.memory(), history: HistoryStore.memory()));
    await tester.pumpAndSettle();
    expect(find.text('Felt'), findsOneWidget);
    expect(find.text('Sit Down'), findsOneWidget);
  });

  testWidgets('human can play several hands through the action bar', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = Settings.memory()..speed = GameSpeed.quick;
    final history = HistoryStore.memory();
    await tester.pumpWidget(_host(
      settings,
      TableScreen(
        config: const TableConfig(seats: 4, difficulty: Difficulty.casual),
        history: history,
        useIsolates: false,
      ),
    ));

    var decisions = 0;
    var sawReview = false;
    for (var i = 0; i < 4000 && history.hands.length < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final rebuy = find.textContaining('Rebuy');
      if (rebuy.evaluate().isNotEmpty) await tester.tap(rebuy.first, warnIfMissed: false);
      // Prefer checking/calling so hands reach later streets.
      final review = find.text('Review Hand');
      if (!sawReview && review.evaluate().isNotEmpty) {
        await tester.tap(review.first, warnIfMissed: false);
        await tester.pumpAndSettle();
        sawReview = find.text('Hand Review').evaluate().isNotEmpty;
        await tester.tap(find.byIcon(CupertinoIcons.xmark_circle_fill), warnIfMissed: false);
        await tester.pumpAndSettle();
      }
      for (final label in ['Check', 'Call', 'Call All-in', 'Deal Next Hand']) {
        final f = find.descendant(of: find.byType(ActionBar), matching: find.text(label));
        if (f.evaluate().isNotEmpty) {
          await tester.tap(f.first, warnIfMissed: false);
          if (label != 'Deal Next Hand') decisions++;
          break;
        }
      }
    }
    expect(history.hands.length, greaterThanOrEqualTo(4));
    expect(history.hands.any((h) => h.reviews.isNotEmpty), isTrue, reason: 'the coach grades hero decisions');
    expect(sawReview, isTrue, reason: 'the review panel opened');
    expect(decisions, greaterThan(0));
    expect(tester.takeException(), isNull);

    // Tear down and let pending timers drain.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('hiding the coach mid-game keeps grading for stats', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = Settings.memory()..speed = GameSpeed.quick;
    final history = HistoryStore.memory();
    await tester.pumpWidget(_host(
      settings,
      TableScreen(
        config: const TableConfig(seats: 3, difficulty: Difficulty.casual),
        history: history,
        useIsolates: false,
      ),
    ));

    Future<void> playUntil(int hands) async {
      for (var i = 0; i < 4000 && history.hands.length < hands; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final rebuy = find.textContaining('Rebuy');
        if (rebuy.evaluate().isNotEmpty) await tester.tap(rebuy.first, warnIfMissed: false);
        for (final label in ['Check', 'Call', 'Call All-in', 'Deal Next Hand']) {
          final f = find.descendant(of: find.byType(ActionBar), matching: find.text(label));
          if (f.evaluate().isNotEmpty) {
            await tester.tap(f.first, warnIfMissed: false);
            break;
          }
        }
      }
    }

    // Coach on: wait for a graded hand.
    for (var n = 1; n <= 8 && !history.hands.any((h) => h.reviews.isNotEmpty); n++) {
      await playUntil(n);
    }
    expect(history.hands.any((h) => h.reviews.isNotEmpty), isTrue);

    expect(find.text('ACCURACY'), findsOneWidget);

    // Hide the coach mid-game (as the Settings switch does).
    settings.update((s) => s.showCoachAtTable = false);
    await tester.pump();
    expect(find.text('ACCURACY'), findsNothing);
    expect(find.text('Coach'), findsNothing, reason: 'no coach control in the top bar');

    final before = history.hands.length;
    var sawReviewButton = false;
    for (var i = 0; i < 4000 && history.hands.length < before + 3; i++) {
      await playUntil(history.hands.length + 1);
      if (find.text('Review Hand').evaluate().isNotEmpty) sawReviewButton = true;
    }
    expect(sawReviewButton, isFalse);
    expect(find.text('ACCURACY'), findsNothing);
    // Grades are still recorded for the stats.
    final later = history.hands.skip(before).toList();
    expect(later.length, greaterThanOrEqualTo(3));
    expect(later.any((h) => h.reviews.isNotEmpty), isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('resetting data asks first, then clears history and drills', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final history = HistoryStore.memory();
    final game = CashGame(
        seats: [TablePlayer(name: 'A', stack: 500, isHuman: true), TablePlayer(name: 'B', stack: 500)],
        smallBlind: 5,
        bigBlind: 10,
        rng: Random(2));
    for (var i = 0; i < 3; i++) {
      var s = game.startNextHand();
      while (!s.isComplete) {
        s = applyAction(s, legalActions(s).canCheck ? const PlayerAction.check() : const PlayerAction.call());
      }
      game.settle(s);
      history.hands.add(HandHistory.fromState(s, heroSeat: 0));
    }
    DrillProgress.current.record(DrillKind.outs, correct: true, streak: 1);

    await tester.pumpWidget(_host(
      Settings.memory(),
      CupertinoPageScaffold(child: SingleChildScrollView(child: SettingsPanel(history: history))),
    ));
    expect(find.text('3 hands saved'), findsOneWidget);

    // Cancel keeps everything.
    await tester.tap(find.text('Reset Hand History & Stats'));
    await tester.pumpAndSettle();
    expect(find.text('Reset hand history?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(history.hands.length, 3);

    // Confirm clears.
    await tester.tap(find.text('Reset Hand History & Stats'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, 'Reset'));
    await tester.pumpAndSettle();
    expect(history.hands, isEmpty);
    expect(find.text('No hands saved'), findsOneWidget);

    await tester.tap(find.text('Reset Training Progress'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, 'Reset'));
    await tester.pumpAndSettle();
    expect(DrillProgress.current.records[DrillKind.outs]!.answered, 0);
    expect(find.text('No drills answered yet'), findsOneWidget);
  });

  testWidgets('a drill session runs to the summary', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(
      Settings.memory(),
      TrainingScreen(history: HistoryStore.memory(), startWith: DrillKind.potOdds, rng: Random(4)),
    ));
    await tester.pumpAndSettle();
    for (var i = 0; i < 10; i++) {
      expect(find.text('QUESTION ${i + 1} OF 10'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pumpAndSettle();
      expect(find.textContaining(RegExp('Correct|Not quite')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('of 10 correct'), findsOneWidget);
  });

  test('preset sizing stays within the legal window', () {
    const l = LegalActions(
      seat: 0,
      canFold: true,
      canCheck: false,
      canCall: true,
      callAmount: 20,
      toCall: 20,
      canRaise: true,
      isBet: false,
      minRaiseTo: 50,
      maxRaiseTo: 400,
      currentBet: 30,
      streetBet: 10,
    );
    // Pot 60 incl. bets: pot-size raise = 30 + (60 + 20) = 110.
    expect(presetRaiseTo(l, 60, 1.0, 5), 110);
    expect(presetRaiseTo(l, 60, 0.1, 5), 50, reason: 'clamped to min-raise');
    expect(presetRaiseTo(l, 6000, 1.0, 5), 400, reason: 'clamped to stack');
  });
}
