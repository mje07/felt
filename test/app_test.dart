import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:felt/app/controller.dart';
import 'package:felt/app/history_store.dart';
import 'package:felt/app/settings.dart';
import 'package:felt/main.dart';
import 'package:felt/screens/table_screen.dart';
import 'package:felt/widgets/action_bar.dart';
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
    for (var i = 0; i < 4000 && history.hands.length < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final rebuy = find.textContaining('Rebuy');
      if (rebuy.evaluate().isNotEmpty) await tester.tap(rebuy.first, warnIfMissed: false);
      // Prefer checking/calling so hands reach later streets.
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
    expect(decisions, greaterThan(0));
    expect(tester.takeException(), isNull);

    // Tear down and let pending timers drain.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
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
