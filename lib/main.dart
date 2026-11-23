import 'package:cupertino_ui/cupertino_ui.dart';

import 'app/drill_progress.dart';
import 'app/history_store.dart';
import 'app/settings.dart';
import 'app/sounds.dart';
import 'app/theme.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  final history = await HistoryStore.open();
  final sounds = await SoloudSounds.start(settings);
  await DrillProgress.load();
  runApp(FeltApp(settings: settings, history: history, sounds: sounds));
}

class FeltApp extends StatelessWidget {
  const FeltApp({super.key, required this.settings, required this.history, this.sounds = Sounds.silent});
  final Settings settings;
  final HistoryStore history;
  final Sounds sounds;

  @override
  Widget build(BuildContext context) {
    return SoundsScope(
      sounds: sounds,
      child: SettingsScope(
      settings: settings,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final brightness = switch (settings.appearance) {
            Appearance.system => null,
            Appearance.light => Brightness.light,
            Appearance.dark => Brightness.dark,
          };
          return CupertinoApp(
            title: 'Felt',
            debugShowCheckedModeBanner: false,
            theme: CupertinoThemeData(
              brightness: brightness,
              primaryColor: CupertinoColors.systemBlue,
              textTheme: const CupertinoTextThemeData(
                textStyle: TextStyle(
                    fontFamily: Typo.family, fontSize: 15, letterSpacing: -0.2, color: CupertinoColors.label),
              ),
            ),
            builder: (context, child) => DefaultTextStyle(
              style: TextStyle(fontFamily: Typo.family, color: Palette.of(context).label),
              child: child!,
            ),
            home: HomeScreen(history: history),
          );
        },
      ),
      ),
    );
  }
}
