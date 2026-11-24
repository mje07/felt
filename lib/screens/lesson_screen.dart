import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';

import '../app/achievements.dart';
import '../app/history_store.dart';
import '../app/learn_progress.dart';
import '../app/skills.dart';
import '../app/theme.dart';
import '../learn/lessons.dart';
import '../widgets/common.dart';
import '../widgets/playing_card.dart';
import '../widgets/range_grid.dart';
import 'spot_trainer_screen.dart';
import 'training_screen.dart';

/// Shared back row for the learning screens.
Widget backRow(BuildContext context, {String label = 'Back'}) {
  final p = Palette.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.xl, 0),
    child: Row(children: [
      CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        onPressed: () => Navigator.of(context).maybePop(),
        child: Row(children: [
          Icon(CupertinoIcons.chevron_left, size: 18, color: p.accent),
          const SizedBox(width: 2),
          Text(label, style: Typo.body(p.accent)),
        ]),
      ),
    ]),
  );
}

/// Cards on a strip of felt, or a range grid, with a caption.
class LessonFigureView extends StatelessWidget {
  const LessonFigureView({super.key, required this.figure});
  final LessonFigure figure;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final f = figure;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (f.holeCards.isNotEmpty || f.boardCards.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(vertical: Space.l, horizontal: Space.xl),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.l),
            gradient: RadialGradient(colors: [p.feltCenter, p.feltEdge], radius: 1.4),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final c in f.holeCards)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: PlayingCard(card: c, width: 50, lifted: true)),
            if (f.holeCards.isNotEmpty && f.boardCards.isNotEmpty) const SizedBox(width: Space.xl),
            for (final c in f.boardCards)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: PlayingCard(card: c, width: 46)),
          ]),
        ),
      if (f.range != null)
        RangeGrid(
          cells: [
            for (final w in WeightedRange.fromNotation(f.range!).gridWeights())
              w > 0 ? [GridSegment(p.accent, w)] : const <GridSegment>[],
          ],
          maxSize: 340,
        ),
      if (f.caption != null) ...[
        const SizedBox(height: Space.s),
        Text(f.caption!, style: Typo.callout(p.secondaryLabel)),
      ],
    ]);
  }
}

/// Plays one lesson: its pages, then its checks, then a score.
class LessonScreen extends StatefulWidget {
  const LessonScreen({super.key, required this.lesson, required this.history});
  final Lesson lesson;
  final HistoryStore history;

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  int _step = 0;
  int? _picked;
  int _correct = 0;

  Lesson get _l => widget.lesson;
  int get _total => _l.pages.length + _l.checks.length;
  bool get _finished => _step >= _total;

  void _pick(int i) {
    if (_picked != null) return;
    final check = _l.checks[_step - _l.pages.length];
    final right = i == check.answer;
    setState(() {
      _picked = i;
      if (right) _correct++;
    });
    SkillRatings.current.record(_l.skill, right ? 1 : 0);
  }

  void _next() {
    setState(() {
      _step++;
      _picked = null;
    });
    if (_finished) {
      LearnProgress.current.completeLesson(_l.id, _correct / _l.checks.length);
      Achievements.current.evaluate(hands: widget.history.hands);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: p.isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      child: SafeArea(
        child: Column(children: [
          backRow(context, label: 'Learn'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xxl, vertical: Space.s),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Stack(children: [
                  Positioned.fill(child: ColoredBox(color: p.separator)),
                  AnimatedFractionallySizedBox(
                    heightFactor: 1,
                    duration: Motion.medium,
                    widthFactor: (_step / _total).clamp(0.0, 1.0),
                    child: ColoredBox(color: p.accent),
                  ),
                ]),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Space.xxl, Space.l, Space.xxl, Space.xxl),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: AnimatedSwitcher(
                    duration: Motion.medium,
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: _finished ? _result(p) : (_step < _l.pages.length ? _page(p) : _check(p)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _page(Palette p) {
    final page = _l.pages[_step];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_l.title.toUpperCase(), style: Typo.caption(p.secondaryLabel).copyWith(letterSpacing: 1)),
      const SizedBox(height: Space.xs),
      Text(page.title, style: Typo.largeTitle(p.label)),
      const SizedBox(height: Space.l),
      for (final para in page.body) ...[
        Text(para, style: Typo.body(p.label).copyWith(fontSize: 17, height: 1.5)),
        const SizedBox(height: Space.m),
      ],
      if (page.figure != null) ...[const SizedBox(height: Space.s), LessonFigureView(figure: page.figure!)],
      const SizedBox(height: Space.xl),
      PillButton(
        label: _step + 1 < _l.pages.length ? 'Next' : 'Check your understanding',
        style: PillStyle.filled,
        onPressed: _next,
      ),
    ]);
  }

  Widget _check(Palette p) {
    final i = _step - _l.pages.length;
    final c = _l.checks[i];
    final picked = _picked;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('QUESTION ${i + 1} OF ${_l.checks.length}', style: Typo.caption(p.secondaryLabel).copyWith(letterSpacing: 1)),
      const SizedBox(height: Space.s),
      Text(c.question, style: Typo.title(p.label)),
      if (c.figure != null) ...[const SizedBox(height: Space.l), LessonFigureView(figure: c.figure!)],
      const SizedBox(height: Space.l),
      for (var k = 0; k < c.options.length; k++)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.s),
          child: _Option(
            label: c.options[k],
            state: picked == null
                ? _OptionState.open
                : k == c.answer
                    ? _OptionState.right
                    : (k == picked ? _OptionState.wrong : _OptionState.dim),
            onTap: () => _pick(k),
          ),
        ),
      if (picked != null) ...[
        const SizedBox(height: Space.s),
        GlassPanel(
          padding: const EdgeInsets.all(Space.l),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(picked == c.answer ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.xmark_circle_fill,
                color: picked == c.answer ? p.positive : p.destructive),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(picked == c.answer ? 'Right' : 'Not quite: ${c.options[c.answer]}', style: Typo.headline(p.label)),
                const SizedBox(height: 2),
                Text(c.why, style: Typo.body(p.secondaryLabel)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: Space.l),
        PillButton(
          label: i + 1 < _l.checks.length ? 'Next question' : 'Finish',
          style: PillStyle.filled,
          onPressed: _next,
        ),
      ],
    ]);
  }

  Widget _result(Palette p) {
    final n = _l.checks.length;
    final perfect = _correct == n;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(perfect ? CupertinoIcons.star_circle_fill : CupertinoIcons.checkmark_seal_fill, size: 48, color: p.accent),
      const SizedBox(height: Space.m),
      Text(perfect ? 'Perfect' : 'Lesson complete', style: Typo.largeTitle(p.label)),
      const SizedBox(height: Space.xs),
      Text('$_correct of $n right. We\'ll bring this back for review when it\'s due.', style: Typo.body(p.secondaryLabel)),
      const SizedBox(height: Space.xl),
      Wrap(spacing: Space.s, runSpacing: Space.s, children: [
        if (_l.drill != null)
          PillButton(
            label: 'Practise: ${_l.drill!.title}',
            style: PillStyle.filled,
            onPressed: () => Navigator.of(context).pushReplacement(CupertinoPageRoute<void>(
                builder: (_) => TrainingScreen(history: widget.history, startWith: _l.drill))),
          ),
        if (_l.trainerStreet != null)
          PillButton(
            label: 'Practise in the Spot Trainer',
            style: PillStyle.filled,
            onPressed: () => Navigator.of(context).pushReplacement(CupertinoPageRoute<void>(
                builder: (_) => SpotTrainerScreen(street: TrainerStreet.values.byName(_l.trainerStreet!)))),
          ),
        PillButton(label: 'Done', style: PillStyle.plain, onPressed: () => Navigator.of(context).maybePop()),
      ]),
    ]);
  }
}

enum _OptionState { open, right, wrong, dim }

class _Option extends StatelessWidget {
  const _Option({required this.label, required this.state, required this.onTap});
  final String label;
  final _OptionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (Color border, Color fill) = switch (state) {
      _OptionState.right => (p.positive, p.positive.withValues(alpha: 0.12)),
      _OptionState.wrong => (p.destructive, p.destructive.withValues(alpha: 0.12)),
      _ => (p.separator, p.surface),
    };
    return GestureDetector(
      onTap: state == _OptionState.open ? onTap : null,
      child: MouseRegion(
        cursor: state == _OptionState.open ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: AnimatedContainer(
          duration: Motion.fast,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 14),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(Radii.m),
            border: Border.all(color: border, width: state == _OptionState.open || state == _OptionState.dim ? 1 : 1.5),
          ),
          child: Opacity(
            opacity: state == _OptionState.dim ? 0.5 : 1,
            child: Text(label, style: Typo.body(p.label).copyWith(fontSize: 16)),
          ),
        ),
      ),
    );
  }
}
