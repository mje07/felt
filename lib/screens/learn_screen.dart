import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';

import '../app/achievements.dart';
import '../app/career.dart';
import '../app/history_store.dart';
import '../app/learn_progress.dart';
import '../app/skills.dart';
import '../app/theme.dart';
import '../learn/lessons.dart';
import '../widgets/common.dart';
import '../widgets/controls.dart';
import 'career_screen.dart';
import 'lesson_screen.dart';
import 'spot_trainer_screen.dart';
import 'training_screen.dart';

/// Opens whatever a plan item points to.
Future<void> openPlanItem(BuildContext context, PlanItem item, HistoryStore history) {
  final Widget screen = switch (item.kind) {
    PlanKind.lesson => LessonScreen(lesson: lessonById(item.target)!, history: history),
    PlanKind.drill => TrainingScreen(history: history, startWith: DrillKind.values.byName(item.target)),
    PlanKind.trainer => SpotTrainerScreen(
        street: TrainerStreet.values.where((s) => s.name == item.target).firstOrNull ?? TrainerStreet.river),
  };
  return Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => screen));
}

/// Today's plan for [history]'s player.
List<PlanItem> todaysPlan(HistoryStore history) => LearnProgress.current.planFor(
      now: DateTime.now(),
      ratings: SkillRatings.current,
      leaks: findLeaks(history.hands.length > 2000 ? history.hands.sublist(history.hands.length - 2000) : history.hands),
    );

/// The learning hub: today's plan, skills, the course, career and achievements.
class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key, required this.history});
  final HistoryStore history;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: p.isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      child: SafeArea(
        child: Column(children: [
          backRow(context),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge(
                  [LearnProgress.current, SkillRatings.current, Achievements.current, Career.current]),
              builder: (context, _) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(Space.xxl, Space.s, Space.xxl, Space.xxl),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Learn', style: Typo.largeTitle(p.label)),
                      const SizedBox(height: Space.xs),
                      Text('A course from the basics to tournament pressure, a plan for today, and your skills.',
                          style: Typo.body(p.secondaryLabel)),
                      const SizedBox(height: Space.xl),
                      LayoutBuilder(builder: (context, c) {
                        final wide = c.maxWidth >= 820;
                        final plan = _TodayCard(history: history);
                        final skills = const _SkillsCard();
                        return wide
                            ? IntrinsicHeight(
                                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                  Expanded(flex: 6, child: plan),
                                  const SizedBox(width: Space.l),
                                  Expanded(flex: 5, child: skills),
                                ]),
                              )
                            : Column(children: [plan, const SizedBox(height: Space.l), skills]);
                      }),
                      const SizedBox(height: Space.l),
                      _CareerBanner(history: history),
                      const SizedBox(height: Space.xl),
                      for (final (i, u) in course.indexed) ...[
                        _UnitCard(index: i, unit: u, history: history),
                        const SizedBox(height: Space.l),
                      ],
                      const _AchievementsCard(),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.history});
  final HistoryStore history;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final plan = todaysPlan(history);
    final progress = LearnProgress.current;
    final done = plan.where(progress.doneToday).length;
    final streak = progress.streak;
    final minutes = plan.fold(0, (s, i) => s + i.minutes);
    return SettingsCard(
      title: 'Today',
      icon: CupertinoIcons.calendar_today,
      color: p.surface,
      children: [
        Row(children: [
          Expanded(
            child: Text(
              done == plan.length ? 'All done for today. Nice work.' : '$done of ${plan.length} done · about $minutes min',
              style: Typo.callout(p.secondaryLabel),
            ),
          ),
          Icon(CupertinoIcons.flame_fill, size: 16, color: streak > 0 ? const Color(0xFFFF9F0A) : p.tertiaryLabel),
          const SizedBox(width: 4),
          Text('$streak-day streak', style: Typo.callout(p.label)),
        ]),
        for (final item in plan)
          SettingRow(
            label: item.title,
            detail: '${item.reason} · ${item.minutes} min',
            trailing: progress.doneToday(item)
                ? Icon(CupertinoIcons.checkmark_circle_fill, color: p.positive)
                : PillButton(
                    label: 'Start',
                    style: PillStyle.tinted,
                    minWidth: 0,
                    height: 32,
                    onPressed: () => openPlanItem(context, item, history),
                  ),
          ),
      ],
    );
  }
}

class _SkillsCard extends StatelessWidget {
  const _SkillsCard();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final ratings = SkillRatings.current;
    const lo = 1000.0, hi = 1900.0;
    return SettingsCard(
      title: 'Skills',
      icon: CupertinoIcons.chart_bar_alt_fill,
      color: p.surface,
      children: [
        for (final s in Skill.values)
          () {
            final r = ratings.ratings[s]!;
            final tried = r.attempts > 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 132, child: Text(s.label, style: Typo.callout(tried ? p.label : p.tertiaryLabel))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 8,
                      child: Stack(children: [
                        Positioned.fill(child: ColoredBox(color: p.separator)),
                        FractionallySizedBox(
                          heightFactor: 1,
                          widthFactor: ((r.rating - lo) / (hi - lo)).clamp(0.02, 1.0),
                          child: ColoredBox(color: tried ? p.accent : p.tertiaryLabel),
                        ),
                      ]),
                    ),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Text(tried ? '${r.rating.round()} · ${ratingLabel(r.rating)}' : 'Not yet',
                      textAlign: TextAlign.right, style: Typo.number(tried ? p.label : p.tertiaryLabel, size: 12)),
                ),
              ]),
            );
          }(),
        Text('Ratings move with every drill, lesson check, trainer decision and graded hand.',
            style: Typo.caption(p.tertiaryLabel)),
      ],
    );
  }
}

class _CareerBanner extends StatelessWidget {
  const _CareerBanner({required this.history});
  final HistoryStore history;

  @override
  Widget build(BuildContext context) {
    final c = Career.current;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => CareerScreen(history: history))),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.all(Space.l),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.l),
            gradient: const LinearGradient(colors: [Color(0xFF1F5440), Color(0xFF0F2C21)]),
          ),
          child: Row(children: [
            const Icon(CupertinoIcons.briefcase_fill, color: Color(0xFFFFD60A), size: 28),
            const SizedBox(width: Space.l),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Career mode', style: Typo.title(const Color(0xFFFFFFFF))),
                Text(
                  c.started
                      ? '${c.stageInfo.name} · ${c.stageInfo.blurb}'
                      : 'Start at micro stakes with ${formatChips(Career.startingBankroll)} chips and climb to The Big One.',
                  style: Typo.callout(const Color(0xD9FFFFFF)),
                ),
              ]),
            ),
            const Icon(CupertinoIcons.chevron_right, color: Color(0xB3FFFFFF)),
          ]),
        ),
      ),
    );
  }
}

class _UnitCard extends StatelessWidget {
  const _UnitCard({required this.index, required this.unit, required this.history});
  final int index;
  final Unit unit;
  final HistoryStore history;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final progress = LearnProgress.current;
    final done = unit.lessons.where((l) => progress.isComplete(l.id)).length;
    return SettingsCard(
      title: 'Unit ${index + 1}: ${unit.title}',
      icon: done == unit.lessons.length ? CupertinoIcons.checkmark_seal_fill : CupertinoIcons.book_fill,
      color: p.surface,
      children: [
        Text('${unit.blurb} $done of ${unit.lessons.length} done.', style: Typo.callout(p.secondaryLabel)),
        for (final l in unit.lessons)
          SettingRow(
            label: l.title,
            detail: '${l.summary} · ${l.minutes} min',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (progress.isComplete(l.id)) ...[
                Icon(CupertinoIcons.checkmark_circle_fill, size: 16, color: p.positive),
                const SizedBox(width: 4),
                Text('${progress.lessonScores[l.id]}%', style: Typo.number(p.secondaryLabel, size: 12)),
                const SizedBox(width: Space.s),
              ],
              PillButton(
                label: progress.isComplete(l.id) ? 'Review' : 'Start',
                style: progress.isComplete(l.id) ? PillStyle.plain : PillStyle.tinted,
                minWidth: 0,
                height: 32,
                onPressed: () => Navigator.of(context)
                    .push(CupertinoPageRoute<void>(builder: (_) => LessonScreen(lesson: l, history: history))),
              ),
            ]),
          ),
      ],
    );
  }
}

class _AchievementsCard extends StatelessWidget {
  const _AchievementsCard();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final a = Achievements.current;
    return SettingsCard(
      title: 'Achievements',
      icon: CupertinoIcons.rosette,
      color: p.surface,
      children: [
        Text('${a.unlocked.length} of ${Achievement.values.length} unlocked', style: Typo.callout(p.secondaryLabel)),
        Wrap(spacing: Space.s, runSpacing: Space.s, children: [
          for (final x in Achievement.values)
            SizedBox(
              width: 214,
              child: Opacity(
                opacity: a.has(x) ? 1 : 0.4,
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: a.has(x) ? RadialGradient(colors: [p.feltCenter, p.feltEdge]) : null,
                      color: a.has(x) ? null : p.separator,
                    ),
                    child: Icon(x.icon, size: 16, color: a.has(x) ? const Color(0xFFFFD60A) : p.secondaryLabel),
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(x.title, style: Typo.callout(p.label).copyWith(fontWeight: FontWeight.w600)),
                      Text(x.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: Typo.caption(p.secondaryLabel)),
                    ]),
                  ),
                ]),
              ),
            ),
        ]),
      ],
    );
  }
}
