import 'dart:math';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:felt/app/settings.dart';
import 'package:felt/screens/spot_trainer_screen.dart';
import 'package:felt/widgets/common.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle(WidgetTester tester, {int steps = 6}) async {
  for (var i = 0; i < steps; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  testWidgets('a three-hand river session plays to the summary', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(SettingsScope(
      settings: Settings.memory(),
      child: CupertinoApp(home: SpotTrainerScreen(hands: 3, random: Random(7))),
    ));
    await tester.tap(find.text('Start · 3 hands'));
    var decisions = 0;
    for (var guard = 0; guard < 80 && find.text('Session results').evaluate().isEmpty; guard++) {
      await settle(tester, steps: 2);
      final next = find.text('Next hand'), results = find.text('See results');
      if (results.evaluate().isNotEmpty) {
        await tester.tap(results);
      } else if (next.evaluate().isNotEmpty) {
        await tester.tap(next);
      } else {
        // Our turn: take the first action offered.
        final actions = find.descendant(of: find.byType(Wrap), matching: find.byType(PillButton));
        if (actions.evaluate().isNotEmpty) {
          await tester.tap(actions.first);
          decisions++;
        }
      }
    }
    await settle(tester, steps: 2);
    expect(find.text('Session results'), findsOneWidget);
    expect(decisions, greaterThan(0));
    expect(find.text('Decisions'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
