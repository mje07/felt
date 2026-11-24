import 'package:cupertino_ui/cupertino_ui.dart';

import 'app/achievements.dart';
import 'app/bankroll.dart';
import 'app/career.dart';
import 'app/drill_progress.dart';
import 'app/history_store.dart';
import 'app/learn_progress.dart';
import 'app/settings.dart';
import 'app/skills.dart';
import 'app/sounds.dart';
import 'app/theme.dart';
import 'app/tournament_store.dart';
import 'app/updater.dart';
import 'screens/home_screen.dart';
import 'widgets/achievement_toast.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  final history = await HistoryStore.open();
  final sounds = await SoloudSounds.start(settings);
  await DrillProgress.load();
  await Bankroll.load();
  await Bankroll.loadCareer();
  await SkillRatings.load();
  await LearnProgress.load();
  await Career.load();
  await Achievements.load();
  await TournamentStore.open();
  Achievements.current.evaluate(hands: history.hands);
  await Updater.start(settings);
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
              child: Stack(children: [child!, const AchievementToast()]),
            ),
            home: HomeScreen(history: history),
          );
        },
      ),
      ),
    );
  }
}
