import 'dart:convert';
import 'dart:math';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../learn/lessons.dart';
import 'drill_progress.dart';
import 'skills.dart';

/// A spaced-repetition card: something to revisit (a lesson, a drill, a
/// Spot Trainer street), scheduled SM-2 style.
class ReviewCard {
  ReviewCard(this.id);
  final String id;
  double ease = 2.5;
  int interval = 0, reps = 0;
  DateTime due = DateTime(2000);

  /// Updates the schedule after a session scored [accuracy] (0..1) on [today].
  void review(double accuracy, DateTime today) {
    final q = (accuracy.clamp(0.0, 1.0) * 5).round();
    if (q < 3) {
      reps = 0;
      interval = 1;
    } else {
      reps++;
      interval = switch (reps) { 1 => 1, 2 => 3, _ => max(1, (interval * ease).round()) };
    }
    ease = max(1.3, ease + 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02));
    due = dayOf(today).add(Duration(days: interval));
  }

  Map<String, Object?> toJson() => {'e': ease, 'i': interval, 'r': reps, 'd': due.toIso8601String()};
  static ReviewCard fromJson(String id, Map<String, Object?> j) => ReviewCard(id)
    ..ease = (j['e'] as num?)?.toDouble() ?? 2.5
    ..interval = (j['i'] as int?) ?? 0
    ..reps = (j['r'] as int?) ?? 0
    ..due = DateTime.tryParse(j['d'] as String? ?? '') ?? DateTime(2000);
}

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);
String dayKey(DateTime t) => '${t.year}-${t.month}-${t.day}';

enum PlanKind { lesson, drill, trainer }

/// One activity in today's plan.
class PlanItem {
  const PlanItem(this.kind, this.target, this.title, this.reason, this.minutes);
  final PlanKind kind;

  /// Lesson id, [DrillKind] name, or trainer street.
  final String target;
  final String title, reason;
  final int minutes;

  String get cardId => '${kind.name}:$target';
}

/// Lessons done, the review schedule, and the daily streak.
class LearnProgress extends ChangeNotifier {
  LearnProgress._(this._prefs);

  static LearnProgress current = LearnProgress._(null);
  factory LearnProgress.memory() => LearnProgress._(null);

  static Future<LearnProgress> load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    final p = LearnProgress._(prefs);
    final raw = prefs?.getString('learn');
    if (raw != null) {
      try {
        final j = (jsonDecode(raw) as Map).cast<String, Object?>();
        p.lessonScores.addAll(((j['lessons'] as Map?) ?? const {}).cast<String, int>());
        for (final e in ((j['cards'] as Map?) ?? const {}).entries) {
          p.cards[e.key as String] = ReviewCard.fromJson(e.key as String, (e.value as Map).cast<String, Object?>());
        }
        p.activeDays.addAll(((j['days'] as List?) ?? const []).cast<String>());
        for (final e in ((j['today'] as Map?) ?? const {}).entries) {
          p._doneToday[e.key as String] = (e.value as List).cast<String>().toSet();
        }
      } catch (_) {}
    }
    return current = p;
  }

  final SharedPreferences? _prefs;

  /// Best score (0..100) per completed lesson.
  final Map<String, int> lessonScores = {};
  final Map<String, ReviewCard> cards = {};

  /// Days (see [dayKey]) with at least one learning activity.
  final Set<String> activeDays = {};
  final Map<String, Set<String>> _doneToday = {};

  bool isComplete(String lessonId) => lessonScores.containsKey(lessonId);
  int get lessonsDone => lessonScores.length;

  /// Consecutive days with activity, ending today (or yesterday, so the
  /// streak survives until the end of today).
  int streakOn(DateTime now) {
    var day = dayOf(now);
    if (!activeDays.contains(dayKey(day))) day = day.subtract(const Duration(days: 1));
    var n = 0;
    while (activeDays.contains(dayKey(day))) {
      n++;
      day = day.subtract(const Duration(days: 1));
    }
    return n;
  }

  int get streak => streakOn(DateTime.now());

  /// Records a finished activity: updates its review card and today's log.
  void recordActivity(String cardId, double accuracy, {DateTime? now}) {
    final t = now ?? DateTime.now();
    (cards[cardId] ??= ReviewCard(cardId)).review(accuracy, t);
    activeDays.add(dayKey(t));
    (_doneToday[dayKey(t)] ??= {}).add(cardId);
    _doneToday.removeWhere((k, _) => k != dayKey(t));
    _save();
    notifyListeners();
  }

  void completeLesson(String id, double accuracy, {DateTime? now}) {
    final score = (accuracy * 100).round();
    lessonScores[id] = max(lessonScores[id] ?? 0, score);
    recordActivity('lesson:$id', accuracy, now: now);
  }

  bool doneToday(PlanItem item, {DateTime? now}) =>
      _doneToday[dayKey(now ?? DateTime.now())]?.contains(item.cardId) ?? false;

  /// Today's plan: reviews that are due, the next new lesson, your biggest
  /// leak and your weakest skill, about 10–20 minutes in all.
  List<PlanItem> planFor({
    required DateTime now,
    required SkillRatings ratings,
    List<Leak> leaks = const [],
  }) {
    final today = dayOf(now);
    final items = <PlanItem>[];
    bool has(String cardId) => items.any((i) => i.cardId == cardId);
    void add(PlanItem i) {
      if (!has(i.cardId) && items.length < 4) items.add(i);
    }

    // Reviews that are due, oldest first.
    final due = cards.values.where((c) => !c.due.isAfter(today)).toList()..sort((a, b) => a.due.compareTo(b.due));
    for (final c in due.take(2)) {
      final item = _itemFor(c.id, 'Review: it\'s been ${c.interval} day${c.interval == 1 ? '' : 's'}');
      if (item != null) add(item);
    }
    // The next lesson in the course.
    final next = allLessons.where((l) => !isComplete(l.id)).firstOrNull;
    if (next != null) {
      add(PlanItem(PlanKind.lesson, next.id, next.title, 'Next in the course', next.minutes));
    }
    // Your costliest leak.
    if (leaks.isNotEmpty) {
      final l = leaks.first;
      if (l.street == Street.preflop) {
        final d = drillFor(l.kind);
        add(PlanItem(PlanKind.drill, d.name, d.title, 'Your biggest leak: ${l.kind.label.toLowerCase()}', 4));
      } else {
        add(PlanItem(PlanKind.trainer, l.street.name, 'Spot Trainer: ${l.street.name}',
            'Your biggest leak: ${l.title.toLowerCase()}', 6));
      }
    }
    // Your weakest practised skill.
    final weak = ratings.weakest.firstOrNull;
    if (weak != null) {
      final item = _practiseFor(weak);
      if (item != null) add(item);
    }
    // Something to fill a short plan.
    if (items.length < 3) add(const PlanItem(PlanKind.drill, 'potOdds', 'Pot odds', 'Quick maths warm-up', 3));
    if (items.length < 3) add(const PlanItem(PlanKind.trainer, 'river', 'Spot Trainer: river', 'Practise against the solver', 6));
    return items;
  }

  PlanItem? _itemFor(String cardId, String reason) {
    final parts = cardId.split(':');
    if (parts.length != 2) return null;
    final kind = PlanKind.values.where((k) => k.name == parts[0]).firstOrNull;
    switch (kind) {
      case PlanKind.lesson:
        final l = lessonById(parts[1]);
        return l == null ? null : PlanItem(PlanKind.lesson, l.id, l.title, reason, max(3, l.minutes ~/ 2));
      case PlanKind.drill:
        final d = DrillKind.values.where((k) => k.name == parts[1]).firstOrNull;
        return d == null ? null : PlanItem(PlanKind.drill, d.name, d.title, reason, 4);
      case PlanKind.trainer:
        return PlanItem(PlanKind.trainer, parts[1], 'Spot Trainer: ${parts[1]}', reason, 6);
      case null:
        return null;
    }
  }

  PlanItem? _practiseFor(Skill s) {
    final reason = 'Your weakest skill: ${s.label.toLowerCase()}';
    return switch (s) {
      Skill.maths => PlanItem(PlanKind.drill, DrillKind.equity.name, DrillKind.equity.title, reason, 4),
      Skill.preflop => PlanItem(PlanKind.drill, DrillKind.preflop.name, DrillKind.preflop.title, reason, 4),
      Skill.pushFold || Skill.icm => PlanItem(PlanKind.drill, DrillKind.pushFold.name, DrillKind.pushFold.title, reason, 4),
      Skill.postflop => PlanItem(PlanKind.trainer, 'flop', 'Spot Trainer: flop', reason, 6),
      Skill.river => PlanItem(PlanKind.trainer, 'river', 'Spot Trainer: river', reason, 6),
      Skill.reading => () {
          final l = allLessons.where((l) => l.skill == Skill.reading && !isComplete(l.id)).firstOrNull;
          return l == null ? null : PlanItem(PlanKind.lesson, l.id, l.title, reason, l.minutes);
        }(),
    };
  }

  void reset() {
    lessonScores.clear();
    cards.clear();
    activeDays.clear();
    _doneToday.clear();
    _save();
    notifyListeners();
  }

  void _save() => _prefs?.setString(
      'learn',
      jsonEncode({
        'lessons': lessonScores,
        'cards': {for (final c in cards.values) c.id: c.toJson()},
        'days': activeDays.toList(),
        'today': {for (final e in _doneToday.entries) e.key: e.value.toList()},
      }));
}
