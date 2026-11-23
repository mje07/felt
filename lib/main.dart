import 'package:cupertino_ui/cupertino_ui.dart';

import 'app/history_store.dart';
import 'app/settings.dart';
import 'app/theme.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  final history = await HistoryStore.open();
  runApp(FeltApp(settings: settings, history: history));
}

class FeltApp extends StatelessWidget {
  const FeltApp({super.key, required this.settings, required this.history});
  final Settings settings;
  final HistoryStore history;

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
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
    );
  }
}
