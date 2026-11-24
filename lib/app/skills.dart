import 'dart:convert';
import 'dart:math';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../learn/lessons.dart';

/// One skill's rating.
class SkillRating {
  double rating = SkillRatings.startRating;
  int attempts = 0;

  /// Rating at the end of each day it changed (oldest first, up to 60).
  final List<double> history = [];

  Map<String, Object?> toJson() => {'r': rating, 'n': attempts, 'h': history};
  static SkillRating fromJson(Map<String, Object?> j) => SkillRating()
    ..rating = (j['r'] as num?)?.toDouble() ?? SkillRatings.startRating
    ..attempts = (j['n'] as int?) ?? 0
    ..history.addAll([for (final x in (j['h'] as List?) ?? const []) (x as num).toDouble()]);
}

/// Elo-style ratings per [Skill], fed by drills, lessons, the Spot Trainer
/// and graded decisions at the table. 1200 is a beginner; 1500 is solid;
/// 1700+ is expert.
class SkillRatings extends ChangeNotifier {
  SkillRatings._(this._prefs);

  static const startRating = 1200.0;

  /// The difficulty every answer is measured against: you need to be right
  /// more than half the time to climb above it.
  static const difficulty = 1400.0;

  static SkillRatings current = SkillRatings._(null);
  factory SkillRatings.memory() => SkillRatings._(null);

  static Future<SkillRatings> load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    final s = SkillRatings._(prefs);
    final raw = prefs?.getString('skills');
    if (raw != null) {
      try {
        final j = (jsonDecode(raw) as Map).cast<String, Object?>();
        for (final e in j.entries) {
          final skill = Skill.values.where((k) => k.name == e.key).firstOrNull;
          if (skill != null) s.ratings[skill] = SkillRating.fromJson((e.value as Map).cast<String, Object?>());
        }
      } catch (_) {}
    }
    return current = s;
  }

  final SharedPreferences? _prefs;
  final Map<Skill, SkillRating> ratings = {for (final k in Skill.values) k: SkillRating()};

  /// Records an outcome for [skill]: [score] is 1 for right, 0 for wrong,
  /// or anything between (a coach grade's score / 100).
  void record(Skill skill, double score) {
    final r = ratings[skill]!;
    final expected = 1 / (1 + pow(10, (difficulty - r.rating) / 400));
    final k = max(10.0, 48 / sqrt(1 + r.attempts / 15));
    r.rating += k * (score.clamp(0.0, 1.0) - expected);
    r.attempts++;
    if (r.history.isEmpty || r.attempts % 10 == 0) {
      r.history.add(r.rating);
      if (r.history.length > 60) r.history.removeAt(0);
    }
    _save();
    notifyListeners();
  }

  void recordDrill(DrillKind kind, {required bool correct}) => record(skillForDrill(kind), correct ? 1 : 0);

  void recordReview(DecisionReview r) => record(skillForReview(r), r.grade.score / 100);

  /// Skills that have been practised, weakest first.
  List<Skill> get weakest {
    final tried = [for (final e in ratings.entries) if (e.value.attempts > 0) e.key];
    tried.sort((a, b) => ratings[a]!.rating.compareTo(ratings[b]!.rating));
    return tried;
  }

  /// Mean rating of the skills that have been practised (start rating if none).
  double get average {
    final tried = [for (final r in ratings.values) if (r.attempts > 0) r.rating];
    return tried.isEmpty ? startRating : tried.reduce((a, b) => a + b) / tried.length;
  }

  void reset() {
    for (final k in Skill.values) {
      ratings[k] = SkillRating();
    }
    _save();
    notifyListeners();
  }

  void _save() => _prefs?.setString('skills', jsonEncode({for (final e in ratings.entries) e.key.name: e.value.toJson()}));
}

Skill skillForDrill(DrillKind kind) => switch (kind) {
      DrillKind.preflop => Skill.preflop,
      DrillKind.pushFold => Skill.pushFold,
      _ => Skill.maths,
    };

Skill skillForReview(DecisionReview r) {
  switch (r.kind) {
    case MistakeKind.shoveTooLoose || MistakeKind.shoveTooTight:
      return Skill.pushFold;
    case MistakeKind.callShoveTooLoose:
      return Skill.icm;
    default:
      return switch (r.street) {
        Street.preflop => Skill.preflop,
        Street.river => Skill.river,
        _ => Skill.postflop,
      };
  }
}

/// A word for a rating.
String ratingLabel(double r) => r >= 1700
    ? 'Expert'
    : r >= 1550
        ? 'Strong'
        : r >= 1400
            ? 'Solid'
            : r >= 1250
                ? 'Learning'
                : 'Beginner';
