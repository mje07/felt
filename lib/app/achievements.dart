import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../learn/lessons.dart';
import 'career.dart';
import 'drill_progress.dart';
import 'learn_progress.dart';
import 'skills.dart';
import 'tournament_store.dart';

enum Achievement {
  firstHand('First hand', 'Play a hand at the tables.', CupertinoIcons.suit_spade_fill),
  firstPot('In the black', 'Win a pot.', CupertinoIcons.circle_grid_hex_fill),
  showdown('Show me', 'Win a pot at showdown.', CupertinoIcons.eye_fill),
  bigPot('Big pot', 'Win a pot worth 100 big blinds or more.', CupertinoIcons.flame_fill),
  quads('Four of a kind', 'Make quads at showdown.', CupertinoIcons.square_grid_2x2_fill),
  royal('Royal flush', 'Make the best hand in poker.', CupertinoIcons.star_circle_fill),
  hammer('The hammer', 'Win a hand with 7-2.', CupertinoIcons.hammer_fill),
  regular('Regular', 'Play 100 hands in Felt.', CupertinoIcons.clock_fill),
  grinder('Grinder', 'Play 1,000 hands in Felt.', CupertinoIcons.timer),
  sharp('Sharp', 'Average 95% accuracy over your last 50 graded decisions.', CupertinoIcons.scope),
  sngWin('Last one standing', 'Win a Sit & Go.', CupertinoIcons.flag_fill),
  finalTable('Final table', 'Reach the final table of a multi-table tournament.', CupertinoIcons.person_3_fill),
  mttWin('Champion', 'Win a multi-table tournament.', CupertinoIcons.rosette),
  millionaire('Millionaire', 'Win the Sunday Million.', CupertinoIcons.money_dollar_circle_fill),
  legend('Legend', 'Win The Big One.', CupertinoIcons.sparkles),
  student('Student', 'Finish a lesson.', CupertinoIcons.book_fill),
  unit('Unit complete', 'Finish every lesson in a unit.', CupertinoIcons.book_circle_fill),
  graduate('Graduate', 'Finish the whole course.', CupertinoIcons.checkmark_seal_fill),
  week('Week streak', 'Train seven days in a row.', CupertinoIcons.calendar),
  month('Month streak', 'Train thirty days in a row.', CupertinoIcons.calendar_badge_plus),
  perfectTen('Perfect ten', 'Answer ten drill questions in a row correctly.', CupertinoIcons.bolt_fill),
  solverApproved('Solver approved', 'Score 90% or better over a Spot Trainer session.', CupertinoIcons.checkmark_shield_fill),
  importer('Bring your own hands', 'Import hands from a poker site.', CupertinoIcons.tray_arrow_down_fill),
  expert('Expert', 'Reach a 1,600 rating in any skill.', CupertinoIcons.chart_bar_alt_fill),
  goingPro('Going pro', 'Reach the Pro stage in career mode.', CupertinoIcons.briefcase_fill),
  hallOfFame('Hall of fame', 'Win The Big One in career mode.', CupertinoIcons.star_fill);

  const Achievement(this.title, this.description, this.icon);
  final String title, description;
  final IconData icon;
}

/// Unlocked achievements, with a queue of fresh ones for the toast.
class Achievements extends ChangeNotifier {
  Achievements._(this._prefs);

  static Achievements current = Achievements._(null);
  factory Achievements.memory() => Achievements._(null);

  static Future<Achievements> load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    final a = Achievements._(prefs);
    final raw = prefs?.getString('achievements');
    if (raw != null) {
      try {
        for (final e in (jsonDecode(raw) as Map).entries) {
          final k = Achievement.values.where((x) => x.name == e.key).firstOrNull;
          final t = DateTime.tryParse(e.value as String);
          if (k != null && t != null) a.unlocked[k] = t;
        }
      } catch (_) {}
    }
    return current = a;
  }

  final SharedPreferences? _prefs;
  final Map<Achievement, DateTime> unlocked = {};

  /// Newly unlocked, waiting to be shown.
  final List<Achievement> fresh = [];

  bool has(Achievement a) => unlocked.containsKey(a);

  void unlock(Achievement a) {
    if (has(a)) return;
    unlocked[a] = DateTime.now();
    fresh.add(a);
    _prefs?.setString('achievements', jsonEncode({for (final e in unlocked.entries) e.key.name: e.value.toIso8601String()}));
    notifyListeners();
  }

  Achievement? takeFresh() {
    if (fresh.isEmpty) return null;
    final a = fresh.removeAt(0);
    notifyListeners();
    return a;
  }

  /// Checks everything that can be worked out from saved data.
  void evaluate({
    required List<HandHistory> hands,
    List<TournamentResult>? results,
    LearnProgress? learn,
    SkillRatings? ratings,
    Career? career,
    DrillProgress? drills,
    DateTime? now,
  }) {
    final felt = [for (final h in hands) if (!h.isImported) h];
    if (felt.isNotEmpty) unlock(Achievement.firstHand);
    if (felt.length >= 100) unlock(Achievement.regular);
    if (felt.length >= 1000) unlock(Achievement.grinder);
    if (hands.any((h) => h.isImported)) unlock(Achievement.importer);
    for (final h in felt.reversed.take(200)) {
      if (h.heroNet <= 0) continue;
      unlock(Achievement.firstPot);
      final start = h.events.firstOrNull;
      final bb = (start?['bb'] as int?) ?? 0;
      if (bb > 0 && h.heroNet >= 100 * bb) unlock(Achievement.bigPot);
      final hole = h.heroHole;
      if (hole != null && {cardRank(hole[0]), cardRank(hole[1])}.containsAll({5, 0})) unlock(Achievement.hammer);
      for (final e in h.events) {
        if (e['e'] != 'showdown') continue;
        final mine = (e['hands'] as Map)['${h.heroSeat}'] as Map?;
        if (mine == null) continue;
        unlock(Achievement.showdown);
        final v = mine['value'] as int;
        final cat = categoryOf(v);
        if (cat == HandCategory.quads) unlock(Achievement.quads);
        if (cat == HandCategory.straightFlush && kickerRank(v, 0) == 12) unlock(Achievement.royal);
      }
    }
    final reviews = [for (final h in felt.reversed) ...h.reviews].take(50).toList();
    if (reviews.length >= 50 && (accuracyOf(reviews) ?? 0) >= 95) unlock(Achievement.sharp);

    final res = results ?? TournamentStore.current.results;
    if (res.any((r) => !r.isMtt && r.place == 1)) unlock(Achievement.sngWin);
    if (res.any((r) => r.isMtt && r.place <= 9)) unlock(Achievement.finalTable);
    if (res.any((r) => r.isMtt && r.place == 1)) unlock(Achievement.mttWin);
    if (res.any((r) => r.eventName == 'Sunday Million' && r.place == 1)) unlock(Achievement.millionaire);
    if (res.any((r) => r.eventName == 'The Big One' && r.place == 1)) unlock(Achievement.legend);

    final l = learn ?? LearnProgress.current;
    if (l.lessonsDone >= 1) unlock(Achievement.student);
    if (course.any((u) => u.lessons.every((x) => l.isComplete(x.id)))) unlock(Achievement.unit);
    if (allLessons.every((x) => l.isComplete(x.id))) unlock(Achievement.graduate);
    final streak = l.streakOn(now ?? DateTime.now());
    if (streak >= 7) unlock(Achievement.week);
    if (streak >= 30) unlock(Achievement.month);

    final d = drills ?? DrillProgress.current;
    if (d.records.values.any((r) => r.bestStreak >= 10)) unlock(Achievement.perfectTen);
    final r = ratings ?? SkillRatings.current;
    if (r.ratings.values.any((x) => x.rating >= 1600)) unlock(Achievement.expert);
    final c = career ?? Career.current;
    if (c.stage >= 3) unlock(Achievement.goingPro);
    if (c.champion) unlock(Achievement.hallOfFame);
  }
}
