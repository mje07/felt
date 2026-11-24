// Renders the real UI to PNGs for visual review.
// Run: flutter test test_screenshots --dart-define=OUT=<dir>
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:felt/app/bankroll.dart';
import 'package:felt/app/controller.dart';
import 'package:felt/app/history_store.dart';
import 'package:felt/app/settings.dart';
import 'package:felt/app/tournament_store.dart';
import 'package:felt/main.dart';
import 'package:felt/app/theme.dart';
import 'package:felt/screens/history_panel.dart';
import 'package:felt/screens/panel_route.dart';
import 'package:felt/screens/range_screen.dart';
import 'package:felt/screens/equity_lab_screen.dart';
import 'package:felt/screens/settings_panel.dart';
import 'package:felt/screens/study_screen.dart';
import 'package:felt/screens/spot_trainer_screen.dart';
import 'package:felt/screens/replayer_screen.dart';
import 'package:flutter/services.dart';
import 'package:felt/screens/stats_screen.dart';
import 'package:felt/screens/training_screen.dart';
import 'package:felt/widgets/common.dart' show PillButton;
import 'package:felt/widgets/review_panel.dart';
import 'package:felt/screens/table_screen.dart';
import 'package:felt/widgets/charts.dart';
import 'package:felt/widgets/controls.dart';
import 'package:flutter/gestures.dart';
import 'package:felt/widgets/action_bar.dart';
import 'package:flutter/rendering.dart';
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
  statsShots();
  coachShots();
  suiteShots();
  studyShots();
  trainerShots();
  importShots();
  settingsShots();
  historyShots();
  sngShots();
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
            debugShowCheckedModeBanner: false,
            theme: CupertinoThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
              textTheme: const CupertinoTextThemeData(
                textStyle: TextStyle(fontFamily: 'Inter', fontSize: 15, color: CupertinoColors.label),
              ),
            ),
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

HistoryStore _simulatedHistory(int n) {
  final store = HistoryStore.memory();
  final rng = Random(11);
  final players = [
    TablePlayer(name: 'You', stack: 1000, personality: Personality.lag, difficulty: Difficulty.casual),
    for (var i = 0; i < 5; i++)
      TablePlayer(name: 'B$i', stack: 1000, personality: Personality.all[i], difficulty: Difficulty.casual),
  ];
  final game = CashGame(seats: players, smallBlind: 5, bigBlind: 10, rng: rng);
  for (var h = 0; h < n; h++) {
    for (var i = 0; i < players.length; i++) {
      if (players[i].stack < 500) game.rebuy(i, 1000 - players[i].stack);
    }
    var s = game.startNextHand();
    final reviews = <DecisionReview>[];
    while (!s.isComplete) {
      final ctx = buildBotContext(s);
      final a = players[s.toAct].bot!.decide(ctx, rng);
      if (s.toAct == 0) {
        final r = gradeDecision(analyzeDecision(ctx, samples: 300, rng: rng), a);
        if (r != null) reviews.add(r);
      }
      s = applyAction(s, a);
    }
    game.settle(s);
    store.hands.add(HandHistory.fromState(s, heroSeat: 0, reviews: reviews));
  }
  return store;
}

void statsShots() {
  for (final dark in [false, true]) {
    testWidgets('stats ${dark ? 'dark' : 'light'}', (tester) async {
      tester.view.physicalSize = const Size(1280, 3000);
      tester.view.devicePixelRatio = 1;
      final settings = Settings.memory()..appearance = dark ? Appearance.dark : Appearance.light;
      final history = _simulatedHistory(800);
      await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('shot'),
        child: SettingsScope(
          settings: settings,
          child: CupertinoApp(
            debugShowCheckedModeBanner: false,
            theme: CupertinoThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
              textTheme: const CupertinoTextThemeData(
                textStyle: TextStyle(fontFamily: 'Inter', fontSize: 15, color: CupertinoColors.label),
              ),
            ),
            home: StatsScreen(history: history),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // Hover a starting-hand cell and the bankroll line for the tooltip states.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.byType(BankrollChart).last) + const Offset(150, 0));
      await tester.pumpAndSettle();
      await _snap(tester, 'stats_${dark ? 'dark' : 'light'}');
      await gesture.removePointer();
    });
  }
}

Widget _themed(bool dark, Widget home) => RepaintBoundary(
      key: const ValueKey('shot'),
      child: SettingsScope(
        settings: Settings.memory()..appearance = dark ? Appearance.dark : Appearance.light,
        child: CupertinoApp(
          debugShowCheckedModeBanner: false,
          theme: CupertinoThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            textTheme: const CupertinoTextThemeData(
              textStyle: TextStyle(fontFamily: 'Inter', fontSize: 15, color: CupertinoColors.label),
            ),
          ),
          home: home,
        ),
      ),
    );

void coachShots() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('ranges $mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 860);
      tester.view.devicePixelRatio = 1;
      final history = _simulatedHistory(1500);
      await tester.pumpWidget(_themed(dark, RangeScreen(history: history, initialPosition: 'BTN')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FeltToggle));
      await tester.pumpAndSettle();
      await _snap(tester, 'ranges_$mode');
    });

    testWidgets('training $mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 860);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(_themed(dark, TrainingScreen(history: _simulatedHistory(300))));
      await tester.pumpAndSettle();
      await _snap(tester, 'training_picker_$mode');
      await tester.tap(find.text(DrillKind.outs.title));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pumpAndSettle();
      await _snap(tester, 'training_question_$mode');
    });

    testWidgets('review $mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      final history = _simulatedHistory(200);
      final hand = history.hands.lastWhere((h) => h.reviews.length >= 3 && h.reviews.any((r) => r.bySolver),
          orElse: () => history.hands.lastWhere((h) => h.reviews.length >= 3 && h.reviews.any((r) => r.grade != Grade.best)));
      await tester.pumpWidget(_themed(
        dark,
        Builder(
          builder: (context) => CupertinoPageScaffold(
            backgroundColor: Palette.of(context).background,
            child: Center(
              child: SizedBox(
                width: 540,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  color: Palette.of(context).surface,
                  child: SingleChildScrollView(child: HandReviewList(reviews: hand.reviews)),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await _snap(tester, 'review_$mode');
    });
  }
}

void settingsShots() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('settings $mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 1500);
      tester.view.devicePixelRatio = 1;
      final history = _simulatedHistory(120);
      await tester.pumpWidget(_themed(
        dark,
        Builder(
          builder: (context) => CupertinoPageScaffold(
            backgroundColor: Palette.of(context).background,
            child: Center(
              child: CupertinoButton(
                onPressed: () => showPanel(context,
                    title: 'Settings', width: 540, builder: (_) => SettingsPanel(history: history)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _snap(tester, 'settings_$mode');
      await tester.tap(find.text('Reset…').first);
      await tester.pumpAndSettle();
      await _snap(tester, 'settings_confirm_$mode');
    });
  }
}

void historyShots() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('history $mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      final history = _simulatedHistory(60);
      await tester.pumpWidget(_themed(
        dark,
        Builder(
          builder: (context) => CupertinoPageScaffold(
            backgroundColor: Palette.of(context).background,
            child: Center(
              child: CupertinoButton(
                onPressed: () =>
                    showPanel(context, title: 'History', width: 560, builder: (_) => HistoryPanel(store: history)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Expand the most recent graded hand.
      final graded = history.hands.reversed.firstWhere((h) => h.reviews.length >= 2);
      await tester.ensureVisible(find.text('Hand #${graded.handNumber}'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hand #${graded.handNumber}'));
      await tester.pumpAndSettle();
      await _snap(tester, 'history_$mode');
    });
  }
}

void sngShots() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('sng lobby $mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      Bankroll.current = Bankroll.memory(8400);
      final settings = Settings.memory()..appearance = dark ? Appearance.dark : Appearance.light;
      await tester.pumpWidget(RepaintBoundary(
          key: const ValueKey('shot'), child: FeltApp(settings: settings, history: HistoryStore.memory())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sit & Go'));
      await tester.pumpAndSettle();
      await _snap(tester, 'sng_lobby_$mode');
    });

    testWidgets('sng table $mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      Bankroll.current = Bankroll.memory(10000);
      TournamentStore.current = TournamentStore.memory();
      GameController? c;
      await tester.pumpWidget(_themed(
        dark,
        TableScreen(
          config: const TableConfig(
            mode: GameMode.sitAndGo,
            seats: 6,
            sngBuyIn: 500,
            speed: BlindSpeed.hyper,
            startingStack: StartingStack.short,
            style: 'maniac',
            difficulty: Difficulty.casual,
          ),
          history: HistoryStore.memory(),
          useIsolates: false,
          onController: (x) => c = x,
        ),
      ));
      var shotTable = false;
      for (var i = 0; i < 20000 && c?.outcome == null; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final ctl = c;
        if (ctl == null) continue;
        final someoneOut = ctl.view.seats.any((s) => s.outPlace != null && !s.isHuman);
        if (!shotTable && someoneOut && ctl.heroLegal != null) {
          await tester.pump(const Duration(milliseconds: 600));
          await _snap(tester, 'sng_table_$mode');
          shotTable = true;
        }
        if (ctl.heroLegal != null) {
          // Fold most hands so the player survives a while, then call.
          ctl.act(ctl.heroLegal!.canCheck
              ? const PlayerAction.check()
              : (shotTable ? const PlayerAction.call() : const PlayerAction.fold()));
        }
        if (ctl.handOver) ctl.dealNext();
      }
      await tester.pump(const Duration(milliseconds: 800));
      await _snap(tester, 'sng_results_$mode');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('sng stats $mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1;
      final rng = Random(8);
      final store = TournamentStore.memory();
      final bank = Bankroll.memory(10000);
      for (var i = 0; i < 40; i++) {
        final players = [6, 9][rng.nextInt(2)];
        final place = 1 + rng.nextInt(players);
        final prizes = prizesFor(PayoutStyle.standard, players, 500);
        final prize = place <= prizes.length ? prizes[place - 1] : 0;
        bank.debit(500);
        if (prize > 0) bank.credit(prize);
        store.results.add(TournamentResult(
          at: DateTime(2026, 11, 1).add(Duration(hours: i)),
          players: players,
          buyIn: 500,
          place: place,
          prize: prize,
          speed: BlindSpeed.turbo,
          payoutStyle: PayoutStyle.standard,
        ));
      }
      TournamentStore.current = store;
      Bankroll.current = bank;
      await tester.pumpWidget(_themed(dark, StatsScreen(history: _simulatedHistory(150))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sit & Go').first);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -2000));
      await tester.pumpAndSettle();
      await _snap(tester, 'sng_stats_$mode');
    });

    testWidgets('pushfold chart $mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(_themed(dark, RangeScreen(history: HistoryStore.memory())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shove'));
      await tester.pumpAndSettle();
      await _snap(tester, 'pushfold_$mode');
    });
  }
}

void suiteShots() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('equity lab $mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(_themed(dark, const EquityLabScreen()));
      for (final c in ['Ks', '7d', '2c']) {
        await tester.tap(find.byKey(ValueKey('pick-$c')));
        await tester.pump();
      }
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Top pair, good kicker'));
      await tester.pumpAndSettle();
      await _snap(tester, 'equity_lab_$mode');
    });
  }
}

void studyShots() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('study $mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 1150);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(_themed(dark, const StudyScreen()));
      for (final c in ['2h', '7s']) {
        await tester.tap(find.byKey(ValueKey('pick-$c')).first);
        await tester.pump();
      }
      await tester.tap(find.text('Solve'));
      for (var i = 0; i < 20 && find.text('Check').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
        await tester.pump();
      }
      await tester.tap(find.textContaining('Check').first);
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump();
      }
      await _snap(tester, 'study_$mode');
    });
  }
}

void trainerShots() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('trainer $mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(_themed(dark, SpotTrainerScreen(random: Random(11))));
      await tester.tap(find.textContaining('Start ·'));
      Future<void> wait() async {
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
          await tester.pump(const Duration(milliseconds: 500));
        }
      }

      // Act until a graded decision is on screen with another decision to make.
      for (var guard = 0; guard < 12; guard++) {
        await wait();
        final actions = find.descendant(of: find.byType(Wrap), matching: find.byType(PillButton));
        if (find.text('Next hand').evaluate().isNotEmpty) {
          await tester.tap(find.text('Next hand'));
          continue;
        }
        if (actions.evaluate().isEmpty) continue;
        if (find.byType(HandReviewList).evaluate().isNotEmpty) break;
        await tester.tap(actions.last);
      }
      await wait();
      await _snap(tester, 'trainer_$mode');
    });
  }
}

void importShots() {
  final hand = importHandHistories(
    File('packages/poker_engine/test/fixtures/sample_hands.txt').readAsStringSync(),
    review: true,
    samples: 300,
  ).hands.first;
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('replayer $mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(_themed(dark, ReplayerScreen(hand: hand)));
      // Step to the river bet, which the coach graded.
      final frames = buildReplay(hand);
      final target = frames.lastIndexWhere((f) => f.review != null);
      for (var i = 0; i < target; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      }
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
      await tester.pumpAndSettle();
      await _snap(tester, 'replayer_$mode');
    });
  }
}
