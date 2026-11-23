// Renders the real UI to PNGs for visual review.
// Run: flutter test test_screenshots --dart-define=OUT=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:felt/app/controller.dart';
import 'package:felt/app/history_store.dart';
import 'package:felt/app/settings.dart';
import 'package:felt/main.dart';
import 'package:felt/screens/table_screen.dart';
import 'package:felt/widgets/action_bar.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poker_engine/poker_engine.dart';

const out = String.fromEnvironment('OUT', defaultValue: 'build/screenshots');

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await loader.load();
  }

  await family('Inter', [
    'assets/fonts/Inter-Regular.ttf',
    'assets/fonts/Inter-Medium.ttf',
    'assets/fonts/Inter-SemiBold.ttf',
    'assets/fonts/Inter-Bold.ttf',
  ]);
  await family('InterDisplay', ['assets/fonts/InterDisplay-SemiBold.ttf', 'assets/fonts/InterDisplay-Bold.ttf']);
  final pub = Platform.environment['PUB_CACHE'] ??
      '${Platform.environment['LOCALAPPDATA']}${Platform.pathSeparator}Pub${Platform.pathSeparator}Cache';
  final icons = Directory('$pub/hosted/pub.dev')
      .listSync()
      .whereType<Directory>()
      .firstWhere((d) => d.path.contains('cupertino_icons-'));
  await family('packages/cupertino_icons/CupertinoIcons', ['${icons.path}/assets/CupertinoIcons.ttf']);
  await family('CupertinoIcons', ['${icons.path}/assets/CupertinoIcons.ttf']);
}

Future<void> _snap(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final f = File('$out/$name.png')..createSync(recursive: true);
    f.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadFonts);

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('lobby $mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      final settings = Settings.memory()..appearance = dark ? Appearance.dark : Appearance.light;
      await tester.pumpWidget(RepaintBoundary(
          key: const ValueKey('shot'), child: FeltApp(settings: settings, history: HistoryStore.memory())));
      await tester.pumpAndSettle();
      await _snap(tester, 'lobby_$mode');
    });

    testWidgets('table $mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      final settings = Settings.memory()
        ..appearance = dark ? Appearance.dark : Appearance.light
        ..autoDeal = false;
      final history = HistoryStore.memory();
      GameController? c;
      await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('shot'),
        child: SettingsScope(
          settings: settings,
          child: CupertinoApp(
            theme: CupertinoThemeData(brightness: dark ? Brightness.dark : Brightness.light),
            home: TableScreen(
              config: const TableConfig(seats: 6, difficulty: Difficulty.casual, style: 'station'),
              history: history,
              useIsolates: false,
              onController: (x) => c = x,
            ),
          ),
        ),
      ));
      // Call along until the flop is out and it's our turn, then snapshot.
      var shot = false, showdown = false;
      for (var i = 0; i < 3000 && !(shot && showdown); i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final bar = find.byType(ActionBar);
        final v = c?.view;
        if (c?.heroLegal != null) {
          if (!shot && (v?.board.length ?? 0) >= 3) {
            await tester.pump(const Duration(milliseconds: 600));
            await _snap(tester, 'table_${mode}_decision');
            shot = true;
          }
          final call = find.descendant(of: bar, matching: find.text('Call'));
          final check = find.descendant(of: bar, matching: find.text('Check'));
          await tester.tap((call.evaluate().isNotEmpty ? call : check).last, warnIfMissed: false);
        }
        if (!showdown && v != null && v.highlight.isNotEmpty) {
          await tester.pump(const Duration(milliseconds: 700));
          await _snap(tester, 'table_${mode}_showdown');
          showdown = true;
        }
        if (c?.handOver ?? false) c?.dealNext();
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });
  }
}
