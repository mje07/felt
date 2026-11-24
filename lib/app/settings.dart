import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Appearance { system, light, dark }

enum GameSpeed {
  relaxed('Relaxed', 1.5),
  normal('Normal', 1.0),
  quick('Quick', 0.6);

  const GameSpeed(this.label, this.factor);
  final String label;

  /// Multiplier applied to every delay and animation.
  final double factor;
}

/// Persisted user preferences.
class Settings extends ChangeNotifier {
  Settings._(this._prefs);

  static Future<Settings> load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null; // run without persistence rather than fail
    }
    final settings = Settings._(prefs);
    settings._read();
    return settings;
  }

  /// In-memory settings for tests.
  factory Settings.memory() => Settings._(null);

  final SharedPreferences? _prefs;

  Appearance appearance = Appearance.system;
  bool fourColorDeck = false;
  GameSpeed speed = GameSpeed.normal;
  bool autoDeal = true;
  bool reduceMotion = false;
  String playerName = 'You';
  bool soundEnabled = true;
  double volume = 0.8;

  /// Show the coach's grade on each of your actions as you play.
  bool showGradesLive = false;

  /// Show accuracy and coach grades at the table. Grading always runs in the
  /// background so statistics stay complete; this only controls display.
  bool showCoachAtTable = true;

  /// Check GitHub for new versions and install them when Felt starts.
  bool autoUpdate = true;

  /// Label each opponent at the table with their playing style.
  bool showOpponentStyles = true;

  void _read() {
    final p = _prefs;
    if (p == null) return;
    appearance = Appearance.values.elementAtOrNull(p.getInt('appearance') ?? 0) ?? Appearance.system;
    fourColorDeck = p.getBool('fourColor') ?? false;
    speed = GameSpeed.values.elementAtOrNull(p.getInt('speed') ?? 1) ?? GameSpeed.normal;
    autoDeal = p.getBool('autoDeal') ?? true;
    reduceMotion = p.getBool('reduceMotion') ?? false;
    soundEnabled = p.getBool('sound') ?? true;
    volume = p.getDouble('volume') ?? 0.8;
    showGradesLive = p.getBool('gradesLive') ?? false;
    showCoachAtTable = p.getBool('coachAtTable') ?? true;
    autoUpdate = p.getBool('autoUpdate') ?? true;
    showOpponentStyles = p.getBool('opponentStyles') ?? true;
    playerName = p.getString('playerName') ?? 'You';
  }

  void update(void Function(Settings s) change) {
    change(this);
    final p = _prefs;
    if (p != null) {
      p.setInt('appearance', appearance.index);
      p.setBool('fourColor', fourColorDeck);
      p.setInt('speed', speed.index);
      p.setBool('autoDeal', autoDeal);
      p.setBool('reduceMotion', reduceMotion);
      p.setBool('sound', soundEnabled);
      p.setDouble('volume', volume);
      p.setBool('gradesLive', showGradesLive);
      p.setBool('coachAtTable', showCoachAtTable);
      p.setBool('autoUpdate', autoUpdate);
      p.setBool('opponentStyles', showOpponentStyles);
      p.setString('playerName', playerName);
    }
    notifyListeners();
  }

  /// Duration scaled by speed (and collapsed when reducing motion).
  Duration scaled(Duration d) => reduceMotion
      ? Duration(milliseconds: (d.inMilliseconds * 0.35 * speed.factor).round())
      : Duration(milliseconds: (d.inMilliseconds * speed.factor).round());
}

/// Makes [Settings] available below the app.
class SettingsScope extends InheritedNotifier<Settings> {
  const SettingsScope({super.key, required Settings settings, required super.child})
      : super(notifier: settings);

  static Settings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()!.notifier!;
}
