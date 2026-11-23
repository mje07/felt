import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DrillRecord {
  int answered = 0, correct = 0, bestStreak = 0;
  double get accuracy => answered == 0 ? 0 : correct / answered;

  Map<String, int> toJson() => {'a': answered, 'c': correct, 's': bestStreak};
  static DrillRecord fromJson(Map<String, dynamic> j) => DrillRecord()
    ..answered = (j['a'] as int?) ?? 0
    ..correct = (j['c'] as int?) ?? 0
    ..bestStreak = (j['s'] as int?) ?? 0;
}

/// Per-drill answer counts and best streaks, persisted locally.
class DrillProgress extends ChangeNotifier {
  DrillProgress._(this._prefs);

  /// The app-wide instance (replaced at startup by [load]).
  static DrillProgress current = DrillProgress._(null);

  static Future<DrillProgress> load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    final p = DrillProgress._(prefs);
    final raw = prefs?.getString('drills');
    if (raw != null) {
      try {
        final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
        for (final e in m.entries) {
          final kind = DrillKind.values.where((k) => k.name == e.key).firstOrNull;
          if (kind != null) p.records[kind] = DrillRecord.fromJson((e.value as Map).cast<String, dynamic>());
        }
      } catch (_) {}
    }
    return current = p;
  }

  final SharedPreferences? _prefs;
  final Map<DrillKind, DrillRecord> records = {for (final k in DrillKind.values) k: DrillRecord()};

  void record(DrillKind kind, {required bool correct, required int streak}) {
    final r = records[kind]!;
    r.answered++;
    if (correct) r.correct++;
    if (streak > r.bestStreak) r.bestStreak = streak;
    _prefs?.setString('drills', jsonEncode({for (final e in records.entries) e.key.name: e.value.toJson()}));
    notifyListeners();
  }
}

/// Which drill practises the skill behind a mistake.
DrillKind drillFor(MistakeKind kind) => switch (kind) {
      MistakeKind.callingWithoutOdds || MistakeKind.foldingWithOdds => DrillKind.potOdds,
      MistakeKind.preflopTooLoose || MistakeKind.preflopTooTight || MistakeKind.openLimp => DrillKind.preflop,
      MistakeKind.missedValue || MistakeKind.passiveWithStrong || MistakeKind.overplayedWeak => DrillKind.equity,
    };

/// The drill to recommend from the player's most frequent coach mistakes.
DrillKind recommendedDrill(PlayerStats stats) {
  if (stats.mistakeCounts.isEmpty) return DrillKind.preflop;
  final top = stats.mistakeCounts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  return drillFor(top);
}
