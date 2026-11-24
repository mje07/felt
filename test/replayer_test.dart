import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:felt/app/settings.dart';
import 'package:felt/screens/replayer_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poker_engine/poker_engine.dart';

void main() {
  final imported = importHandHistories(
    File('packages/poker_engine/test/fixtures/sample_hands.txt').readAsStringSync(),
    review: true,
    samples: 200,
  ).hands;

  test('frames conserve chips and attach reviews to the player\'s actions', () {
    for (final h in imported) {
      final frames = buildReplay(h);
      expect(frames.length, greaterThan(3));
      final start = h.events.first;
      final total = [for (final s in start['seats'] as List) (s as Map)['stack'] as int].reduce((a, b) => a + b);
      for (final f in frames.take(frames.length - 1)) {
        expect(f.stacks.reduce((a, b) => a + b) + f.pot, total);
      }
      // After the award, the final stacks match the hand's end state.
      final end = (h.events.last['stacks'] as Map).cast<String, Object?>();
      for (final e in end.entries) {
        expect(frames.last.stacks[int.parse(e.key)], e.value);
      }
    }
    final first = buildReplay(imported.first);
    expect(first.where((f) => f.review != null).length, imported.first.reviews.length);
    expect(first.last.revealed.length, 2);
  });

  testWidgets('the replayer steps through a hand with the arrow keys', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final hand = imported.first;
    await tester.pumpWidget(SettingsScope(
      settings: Settings.memory(),
      child: CupertinoApp(home: ReplayerScreen(hand: hand)),
    ));
    await tester.pump();
    final frames = buildReplay(hand);
    expect(find.text('1 / ${frames.length}'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('2 / ${frames.length}'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(find.text('${frames.length} / ${frames.length}'), findsOneWidget);
    expect(find.text(r'You win $5.53'), findsOneWidget);
  });
}
