import 'dart:math';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:poker_engine/poker_engine.dart';

import '../app/achievements.dart';
import '../app/drill_progress.dart';
import '../app/learn_progress.dart';
import '../app/skills.dart';
import '../app/history_store.dart';
import '../app/sounds.dart';
import '../app/theme.dart';
import '../widgets/common.dart';
import '../widgets/playing_card.dart';
import 'spot_trainer_screen.dart';

IconData drillIcon(DrillKind k) => switch (k) {
      DrillKind.preflop => CupertinoIcons.square_grid_3x2_fill,
      DrillKind.potOdds => CupertinoIcons.percent,
      DrillKind.outs => CupertinoIcons.number,
      DrillKind.equity => CupertinoIcons.chart_pie_fill,
      DrillKind.showdown => CupertinoIcons.eye_fill,
      DrillKind.pushFold => CupertinoIcons.arrow_up_circle_fill,
    };

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key, required this.history, this.startWith, this.rng});
  final HistoryStore history;

  /// Jump straight into a drill.
  final DrillKind? startWith;
  final Random? rng;

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  DrillKind? _active;

  @override
  void initState() {
    super.initState();
    _active = widget.startWith;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: p.isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      child: SafeArea(
        child: AnimatedSwitcher(
          duration: Motion.medium,
          child: _active == null
              ? _Picker(
                  key: const ValueKey('picker'),
                  history: widget.history,
                  onStart: (k) => setState(() => _active = k),
                )
              : _Session(
                  key: ValueKey(_active),
                  kind: _active!,
                  rng: widget.rng ?? Random.secure(),
                  onExit: () => setState(() => _active = null),
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- picker

class _Picker extends StatelessWidget {
  const _Picker({super.key, required this.history, required this.onStart});
  final HistoryStore history;
  final ValueChanged<DrillKind> onStart;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final stats = computeStats(history.hands);
    final rec = recommendedDrill(stats);
    final why = stats.mistakeCounts.isEmpty
        ? 'A good place to start.'
        : 'Your most common coach note is "${stats.mistakeCounts.entries.reduce((a, b) => b.value > a.value ? b : a).key.label.toLowerCase()}".';
    return ListenableBuilder(
      listenable: DrillProgress.current,
      builder: (context, _) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.xl, 0),
            child: Row(children: [
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: () => Navigator.of(context).maybePop(),
                child: Row(children: [
                  Icon(CupertinoIcons.chevron_left, size: 18, color: p.accent),
                  const SizedBox(width: 2),
                  Text('Back', style: Typo.body(p.accent)),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Space.xxl, Space.s, Space.xxl, Space.xxl),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Training', style: Typo.largeTitle(p.label)),
                      const SizedBox(height: Space.xs),
                      Text('Short drills, ten questions each. Answer with the mouse or keys 1–5.',
                          style: Typo.body(p.secondaryLabel)),
                      const SizedBox(height: Space.xl),
                      const _SpotTrainerCard(),
                      const SizedBox(height: Space.l),
                      _DrillCard(kind: rec, recommended: why, onTap: () => onStart(rec)),
                      const SizedBox(height: Space.l),
                      LayoutBuilder(builder: (context, c) {
                        final cols = c.maxWidth > 640 ? 2 : 1;
                        final w = (c.maxWidth - (cols - 1) * Space.m) / cols;
                        return Wrap(
                          spacing: Space.m,
                          runSpacing: Space.m,
                          children: [
                            for (final k in DrillKind.values)
                              if (k != rec) SizedBox(width: w, child: _DrillCard(kind: k, onTap: () => onStart(k))),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrillCard extends StatefulWidget {
  const _DrillCard({required this.kind, required this.onTap, this.recommended});
  final DrillKind kind;
  final VoidCallback onTap;
  final String? recommended;

  @override
  State<_DrillCard> createState() => _DrillCardState();
}

class _DrillCardState extends State<_DrillCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final rec = DrillProgress.current.records[widget.kind]!;
    final featured = widget.recommended != null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hover ? 1.01 : 1,
          duration: Motion.fast,
          child: Container(
            padding: const EdgeInsets.all(Space.xl),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(Radii.l),
              border: Border.all(color: featured ? p.accent.withValues(alpha: 0.5) : p.separator, width: featured ? 1.5 : 0.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Radii.m),
                  ),
                  child: Icon(drillIcon(widget.kind), color: p.accent, size: 24),
                ),
                const SizedBox(width: Space.l),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (featured)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text('RECOMMENDED FOR YOU',
                              style: Typo.caption(p.accent).copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w700)),
                        ),
                      Text(widget.kind.title, style: Typo.headline(p.label).copyWith(fontSize: 17)),
                      const SizedBox(height: 2),
                      Text(featured ? '${widget.kind.description} ${widget.recommended}' : widget.kind.description,
                          style: Typo.callout(p.secondaryLabel)),
                      const SizedBox(height: Space.s),
                      Text(
                        rec.answered == 0
                            ? 'Not tried yet'
                            : '${(rec.accuracy * 100).round()}% correct · ${rec.answered} answered · best streak ${rec.bestStreak}',
                        style: Typo.caption(p.tertiaryLabel),
                      ),
                    ],
                  ),
                ),
                Icon(CupertinoIcons.chevron_right, size: 16, color: p.tertiaryLabel),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- session

class _Session extends StatefulWidget {
  const _Session({super.key, required this.kind, required this.rng, required this.onExit});
  final DrillKind kind;
  final Random rng;
  final VoidCallback onExit;

  @override
  State<_Session> createState() => _SessionState();
}

class _SessionState extends State<_Session> {
  static const length = 10;
  late Question _q = generateQuestion(widget.kind, widget.rng);
  int _index = 0, _correct = 0, _streak = 0, _bestStreak = 0;
  int? _picked;
  bool _done = false;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _answer(int i) {
    if (_picked != null || _done) return;
    final right = i == _q.answer;
    setState(() {
      _picked = i;
      if (right) {
        _correct++;
        _streak++;
        _bestStreak = max(_bestStreak, _streak);
      } else {
        _streak = 0;
      }
    });
    DrillProgress.current.record(widget.kind, correct: right, streak: _streak);
    SkillRatings.current.recordDrill(widget.kind, correct: right);
    SoundsScope.of(context).play(right ? Sfx.chip : Sfx.fold);
  }

  void _next() {
    if (_picked == null) return;
    setState(() {
      if (_index + 1 >= length) {
        _done = true;
        LearnProgress.current.recordActivity('drill:${widget.kind.name}', _correct / length);
        Achievements.current.evaluate(hands: const []);
      } else {
        _index++;
        _picked = null;
        _q = generateQuestion(widget.kind, widget.rng);
      }
    });
  }

  void _restart() => setState(() {
        _index = _correct = _streak = _bestStreak = 0;
        _picked = null;
        _done = false;
        _q = generateQuestion(widget.kind, widget.rng);
      });

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    const digits = [
      LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, //
      LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5,
    ];
    final d = digits.indexOf(k);
    if (d >= 0 && d < _q.choices.length) {
      _answer(d);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space) {
      _done ? _restart() : _next();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      widget.onExit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.xl, 0),
            child: Row(children: [
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: widget.onExit,
                child: Row(children: [
                  Icon(CupertinoIcons.chevron_left, size: 18, color: p.accent),
                  const SizedBox(width: 2),
                  Text('Drills', style: Typo.body(p.accent)),
                ]),
              ),
              const Spacer(),
              Text(widget.kind.title, style: Typo.headline(p.label)),
              const Spacer(),
              Row(children: [
                Icon(CupertinoIcons.flame_fill, size: 16, color: _streak > 0 ? const Color(0xFFFF9F0A) : p.tertiaryLabel),
                const SizedBox(width: 4),
                Text('$_streak', style: Typo.number(p.label, size: 15)),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xxl, vertical: Space.m),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                width: double.infinity,
                child: Stack(children: [
                  Positioned.fill(child: ColoredBox(color: p.accent.withValues(alpha: 0.15))),
                  AnimatedFractionallySizedBox(
                    duration: Motion.medium,
                    curve: Motion.spring,
                    widthFactor: (_index + (_picked != null || _done ? 1 : 0)) / length,
                    child: ColoredBox(color: p.accent),
                  ),
                ]),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Space.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: AnimatedSwitcher(
                    duration: Motion.medium,
                    transitionBuilder: (c, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                          position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(a), child: c),
                    ),
                    child: _done ? _summary(p) : _question(p),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _question(Palette p) {
    final q = _q;
    return Column(
      key: ValueKey('q$_index'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('QUESTION ${_index + 1} OF $length',
            textAlign: TextAlign.center, style: Typo.caption(p.secondaryLabel).copyWith(letterSpacing: 1)),
        const SizedBox(height: Space.s),
        Text(q.prompt, textAlign: TextAlign.center, style: Typo.title(p.label)),
        if (q.situation != null) ...[
          const SizedBox(height: Space.xs),
          Text(q.situation!, textAlign: TextAlign.center, style: Typo.body(p.secondaryLabel)),
        ],
        const SizedBox(height: Space.xl),
        _Scene(question: q),
        const SizedBox(height: Space.xl),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final (i, c) in q.choices.indexed)
              _AnswerButton(
                label: c,
                shortcut: '${i + 1}',
                state: _picked == null
                    ? _AnswerState.idle
                    : (i == q.answer ? _AnswerState.correct : (i == _picked ? _AnswerState.wrong : _AnswerState.dim)),
                onTap: () => _answer(i),
              ),
          ],
        ),
        AnimatedSize(
          duration: Motion.medium,
          curve: Motion.spring,
          child: _picked == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: Space.xl),
                  child: Column(children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(Space.l),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(Radii.m),
                        border: Border.all(color: p.separator, width: 0.5),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(
                          _picked == q.answer ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.xmark_circle_fill,
                          color: _picked == q.answer ? const Color(0xFF0CA30C) : const Color(0xFFD03B3B),
                          size: 22,
                        ),
                        const SizedBox(width: Space.m),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_picked == q.answer ? 'Correct' : 'Not quite — ${q.choices[q.answer]}',
                                style: Typo.headline(p.label)),
                            const SizedBox(height: 4),
                            Text(q.explanation, style: Typo.body(p.secondaryLabel).copyWith(height: 1.4)),
                          ]),
                        ),
                      ]),
                    ),
                    const SizedBox(height: Space.l),
                    PillButton(
                      label: _index + 1 >= length ? 'See Results' : 'Next Question',
                      shortcut: 'Enter',
                      style: PillStyle.filled,
                      minWidth: 220,
                      onPressed: _next,
                    ),
                  ]),
                ),
        ),
      ],
    );
  }

  Widget _summary(Palette p) {
    final pct = (_correct / length * 100).round();
    final verdict = pct >= 90 ? 'Excellent' : (pct >= 70 ? 'Solid work' : (pct >= 50 ? 'Getting there' : 'Keep practising'));
    return Column(
      key: const ValueKey('summary'),
      children: [
        Icon(CupertinoIcons.rosette, size: 48, color: p.accent),
        const SizedBox(height: Space.m),
        Text(verdict, style: Typo.largeTitle(p.label)),
        const SizedBox(height: Space.s),
        Text('$_correct of $length correct · best streak $_bestStreak', style: Typo.body(p.secondaryLabel)),
        const SizedBox(height: Space.xs),
        Text(
          'All-time: ${(DrillProgress.current.records[widget.kind]!.accuracy * 100).round()}% correct',
          style: Typo.callout(p.tertiaryLabel),
        ),
        const SizedBox(height: Space.xl),
        Row(mainAxisSize: MainAxisSize.min, children: [
          PillButton(label: 'Choose Another', onPressed: widget.onExit),
          const SizedBox(width: Space.s),
          PillButton(label: 'Go Again', shortcut: 'Enter', style: PillStyle.filled, onPressed: _restart),
        ]),
      ],
    );
  }
}

enum _AnswerState { idle, correct, wrong, dim }

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({required this.label, required this.shortcut, required this.state, required this.onTap});
  final String label, shortcut;
  final _AnswerState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    const green = Color(0xFF0CA30C), red = Color(0xFFD03B3B);
    final (Color bg, Color fg, IconData? icon) = switch (state) {
      _AnswerState.idle => (p.surface, p.label, null),
      _AnswerState.correct => (green.withValues(alpha: 0.16), p.label, CupertinoIcons.checkmark_alt),
      _AnswerState.wrong => (red.withValues(alpha: 0.16), p.label, CupertinoIcons.xmark),
      _AnswerState.dim => (p.surface, p.tertiaryLabel, null),
    };
    return MouseRegion(
      cursor: state == _AnswerState.idle ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          constraints: const BoxConstraints(minWidth: 120),
          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(Radii.m),
            border: Border.all(
              color: state == _AnswerState.correct
                  ? green
                  : (state == _AnswerState.wrong ? red : p.separator),
              width: state == _AnswerState.correct || state == _AnswerState.wrong ? 1.5 : 0.5,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(shortcut, style: Typo.caption(p.tertiaryLabel)),
            const SizedBox(width: Space.s),
            Text(label, style: Typo.headline(fg)),
            if (icon != null) ...[
              const SizedBox(width: Space.s),
              Icon(icon, size: 16, color: state == _AnswerState.correct ? green : red),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Cards / numbers that set up a question.
class _Scene extends StatelessWidget {
  const _Scene({required this.question});
  final Question question;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final q = question;
    Widget group(String label, List<int> cards, double w) => Column(children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final c in cards)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: DealIn(child: PlayingCard(card: c, width: w)),
              ),
          ]),
          const SizedBox(height: 6),
          Text(label, style: Typo.caption(const Color(0xB3FFFFFF)).copyWith(letterSpacing: 0.8)),
        ]);

    if (q.kind == DrillKind.potOdds) {
      Widget number(String label, int v) => Column(children: [
            Text(formatChips(v), style: Typo.number(p.label, size: 34, weight: FontWeight.w600)),
            Text(label, style: Typo.caption(p.secondaryLabel)),
          ]);
      return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        number('POT', q.pot!),
        const SizedBox(width: Space.xxl),
        number('BET', q.bet!),
      ]);
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.xl, horizontal: Space.l),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.l),
        gradient: RadialGradient(colors: [p.feltCenter, p.feltEdge], radius: 1.2),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Color(0xFFFFFFFF)),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: Space.xxl,
          runSpacing: Space.l,
          children: [
            group('YOU', q.hole, 62),
            if (q.board.isNotEmpty) group('BOARD', q.board, 52),
            if (q.villain != null) group('OPPONENT', q.villain!, 52),
          ],
        ),
      ),
    );
  }
}

/// Entry to the solver-backed spot trainer.
class _SpotTrainerCard extends StatelessWidget {
  const _SpotTrainerCard();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => const SpotTrainerScreen())),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.all(Space.l),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.l),
            gradient: RadialGradient(colors: [p.feltCenter, p.feltEdge], radius: 2.2, center: Alignment.topLeft),
          ),
          child: Row(children: [
            const Icon(CupertinoIcons.scope, size: 30, color: Color(0xFFFFFFFF)),
            const SizedBox(width: Space.l),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Spot Trainer', style: Typo.title(const Color(0xFFFFFFFF))),
                const SizedBox(height: 2),
                Text('Play whole hands against the solver, graded by the EV every decision gives up.',
                    style: Typo.callout(const Color(0xD9FFFFFF))),
              ]),
            ),
            const Icon(CupertinoIcons.chevron_right, color: Color(0xB3FFFFFF)),
          ]),
        ),
      ),
    );
  }
}
