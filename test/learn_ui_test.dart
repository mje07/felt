import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:felt/app/achievements.dart';
import 'package:felt/app/history_store.dart';
import 'package:felt/app/learn_progress.dart';
import 'package:felt/app/settings.dart';
import 'package:felt/app/skills.dart';
import 'package:felt/learn/lessons.dart';
import 'package:felt/screens/learn_screen.dart';
import 'package:felt/screens/lesson_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => SettingsScope(settings: Settings.memory(), child: CupertinoApp(home: child));

void main() {
  setUp(() {
    LearnProgress.current = LearnProgress.memory();
    SkillRatings.current = SkillRatings.memory();
    Achievements.current = Achievements.memory();
  });

  testWidgets('a lesson plays through its pages and checks and is recorded', (tester) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lesson = lessonById('pot-odds')!;
    await tester.pumpWidget(host(LessonScreen(lesson: lesson, history: HistoryStore.memory())));
    for (var i = 0; i < lesson.pages.length; i++) {
      await tester.tap(find.text(i + 1 < lesson.pages.length ? 'Next' : 'Check your understanding'));
      await tester.pumpAndSettle();
    }
    for (final (i, c) in lesson.checks.indexed) {
      // Answer the first two right and the last one wrong.
      final pick = i < 2 ? c.answer : (c.answer + 1) % c.options.length;
      await tester.tap(find.text(c.options[pick]));
      await tester.pumpAndSettle();
      expect(find.text(c.why), findsOneWidget);
      await tester.tap(find.text(i + 1 < lesson.checks.length ? 'Next question' : 'Finish'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Lesson complete'), findsOneWidget);
    expect(find.textContaining('2 of 3 right'), findsOneWidget);
    expect(LearnProgress.current.lessonScores['pot-odds'], 67);
    expect(SkillRatings.current.ratings[Skill.maths]!.attempts, 3);
    expect(Achievements.current.has(Achievement.student), isTrue);
    expect(find.text('Practise: Pot odds'), findsOneWidget);
  });

  testWidgets('the Learn hub shows today\'s plan, skills, the course and achievements', (tester) async {
    tester.view.physicalSize = const Size(1280, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(LearnScreen(history: HistoryStore.memory())));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Hand rankings'), findsWidgets);
    expect(find.text('Career mode'), findsOneWidget);
    expect(find.textContaining('of ${Achievement.values.length} unlocked'), findsOneWidget);
  });
}
