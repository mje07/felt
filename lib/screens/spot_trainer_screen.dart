import 'dart:async';
import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:poker_engine/poker_engine.dart';

import '../app/achievements.dart';
import '../app/learn_progress.dart';
import '../app/skills.dart';
import '../app/solver_worker.dart';
import '../learn/lessons.dart' show Skill;
import '../app/theme.dart';
import '../widgets/common.dart';
import '../widgets/controls.dart';
import '../widgets/playing_card.dart';
import '../widgets/review_panel.dart';
import 'study_screen.dart';

const _bb = 10;

enum TrainerStreet {
  river('River', 5),
  turn('Turn', 4),
  flop('Flop', 3);

  const TrainerStreet(this.label, this.cards);
  final String label;
  final int cards;
}

/// One prepared hand: a solved spot plus both players' cards.
class _Question {
  _Question(this.spot, this.heroPlayer, this.heroCombo, this.villainCombo);
  final SolverSpot spot;
  final int heroPlayer, heroCombo, villainCombo;
  SolverWorker? worker;
  final Completer<void> ready = Completer();

  void dispose() => worker?.dispose();
}

/// Play solved spots against an opponent who follows the solver, and get
/// every decision graded by how much EV it gives up.
class SpotTrainerScreen extends StatefulWidget {
  const SpotTrainerScreen({super.key, this.hands = 10, this.random, this.street});

  /// Street to start on (from a plan or leak); the player can still change it.
  final TrainerStreet? street;

  /// Hands per session.
  final int hands;
  final math.Random? random;

  @override
  State<SpotTrainerScreen> createState() => _SpotTrainerScreenState();
}

class _SpotTrainerScreenState extends State<SpotTrainerScreen> {
  late final math.Random _rng = widget.random ?? math.Random();
  int _preset = 0;
  late TrainerStreet _street = widget.street ?? TrainerStreet.river;
  int? _side; // null = random, 0 = out of position, 1 = in position
  bool _running = false;

  // Session state.
  int _handNo = 0;
  _Question? _q, _next;
  final List<int> _path = [];
  SolverNodeView? _view;
  final List<String> _log = [];
  final List<DecisionReview> _reviews = [];
  DecisionReview? _lastReview;
  bool _handOver = false, _waiting = false, _summary = false;
  String? _result;

  @override
  void dispose() {
    _q?.dispose();
    _next?.dispose();
    super.dispose();
  }

  StudyPreset get _p => studyPresets[_preset];

  String _name(int player) => player == 0 ? _p.oopName : _p.ipName;

  /// Deals a random spot and starts solving it in its own worker.
  _Question _prepare() {
    final deck = List<int>.generate(52, (i) => i)..shuffle(_rng);
    final board = deck.take(_street.cards).toList();
    final oop = _p.oop(), ip = _p.ip();
    final heroPlayer = _side ?? _rng.nextInt(2);
    int draw(WeightedRange r, int usedMask) {
      final c = WeightedRange.sample(r.cumulativeWeights(), _rng, usedMask);
      return c < 0 ? comboIndex(deck[10], deck[11]) : c;
    }

    var mask = 0;
    for (final c in board) {
      mask |= 1 << c;
    }
    final heroCombo = draw(heroPlayer == 0 ? oop : ip, mask);
    final (a, b) = comboCards[heroCombo];
    final villainCombo = draw(heroPlayer == 0 ? ip : oop, mask | 1 << a | 1 << b);
    final spot = SolverSpot(
      board: board,
      pot: (_p.potBb * _bb).round(),
      stack: (_p.stackBb * _bb).round(),
      oop: oop,
      ip: ip,
      // Lighter flop trees so a hand is ready while you play the last one.
      flopTurnCards: 6,
      flopRiverCards: 4,
    );
    final q = _Question(spot, heroPlayer, heroCombo, villainCombo);
    () async {
      final w = await SolverWorker.spawn();
      q.worker = w;
      final cache = await SolverWorker.defaultCacheDir();
      final target = switch (_street) {
        TrainerStreet.river => 0.5,
        TrainerStreet.turn => 1.0,
        TrainerStreet.flop => 2.0,
      };
      await for (final p in w.solve(spot, target: target, maxTime: const Duration(minutes: 2), cacheDir: cache)) {
        if (p.done) break;
      }
      if (!q.ready.isCompleted) q.ready.complete();
    }();
    return q;
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _summary = false;
      _handNo = 0;
      _reviews.clear();
    });
    _next = _prepare();
    await _nextHand();
  }

  Future<void> _nextHand() async {
    _q?.dispose();
    final q = _next ?? _prepare();
    _next = _handNo + 1 < widget.hands ? _prepare() : null;
    setState(() {
      _q = q;
      _handNo++;
      _path.clear();
      _log.clear();
      _view = null;
      _lastReview = null;
      _handOver = false;
      _result = null;
      _waiting = true;
    });
    await q.ready.future;
    if (!mounted || _q != q) return;
    setState(() => _waiting = false);
    await _advance();
  }

  /// Moves through opponent actions and dealt cards until it's our turn or
  /// the hand ends.
  Future<void> _advance() async {
    final q = _q!;
    final w = q.worker!;
    while (mounted) {
      final v = await w.view(_path);
      if (!mounted || _q != q) return;
      setState(() => _view = v);
      if (v.kind == NodeKind.action && v.player == q.heroPlayer) return;
      if (v.kind == NodeKind.action) {
        // The opponent samples the solver's strategy for their hand.
        final j = v.hands.indexOf(q.villainCombo);
        final h = v.hands.length;
        var choice = 0;
        if (j >= 0) {
          var x = _rng.nextDouble();
          for (var i = 0; i < v.actions.length; i++) {
            x -= v.strategy[i * h + j];
            if (x <= 0) {
              choice = i;
              break;
            }
            choice = i;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 450));
        if (!mounted || _q != q) return;
        setState(() {
          _log.add('${_name(v.player)} ${actionLabel(v.actions[choice], v).toLowerCase()}');
          _path.add(choice);
        });
        continue;
      }
      if (v.kind == NodeKind.chance) {
        final (a, b) = comboCards[q.heroCombo];
        final (c, d) = comboCards[q.villainCombo];
        final options = [
          for (var i = 0; i < v.cards.length; i++)
            if (!{a, b, c, d}.contains(v.cards[i])) i,
        ];
        final pick = options[_rng.nextInt(options.length)];
        setState(() {
          _log.add('${v.board.length == 3 ? 'Turn' : 'River'}: ${cardToString(v.cards[pick])}');
          _path.add(pick);
        });
        continue;
      }
      // Fold or showdown.
      _finishHand(v);
      return;
    }
  }

  void _finishHand(SolverNodeView v) {
    final q = _q!;
    String result;
    if (v.kind == NodeKind.fold) {
      final lastWasHero = _log.isNotEmpty && _log.last.startsWith('You');
      result = lastWasHero ? 'You folded.' : '${_name(1 - q.heroPlayer)} folded. You win the pot.';
    } else {
      final (a, b) = comboCards[q.heroCombo];
      final (c, d) = comboCards[q.villainCombo];
      final mine = evaluate([a, b, ...v.board]), theirs = evaluate([c, d, ...v.board]);
      result = mine > theirs
          ? 'You win with ${describeHand(mine).toLowerCase()}.'
          : mine == theirs
          ? 'Split pot.'
          : '${_name(1 - q.heroPlayer)} wins with ${describeHand(theirs).toLowerCase()}.';
    }
    setState(() {
      _handOver = true;
      _result = result;
    });
  }


  void _finishSession() {
    final acc = accuracyOf(_reviews);
    if (acc != null) {
      LearnProgress.current.recordActivity('trainer:${_street.name}', acc / 100);
      if (acc >= 90 && _reviews.length >= 5) Achievements.current.unlock(Achievement.solverApproved);
    }
    setState(() => _summary = true);
  }
  Future<void> _act(int i) async {
    final q = _q!, v = _view!;
    final evs = await q.worker!.actionEvs(_path, q.heroCombo);
    if (!mounted || _q != q) return;
    DecisionReview? review;
    if (evs != null) {
      final (ev, freq) = evs;
      var best = 0;
      for (var k = 1; k < ev.length; k++) {
        if (ev[k] > ev[best]) best = k;
      }
      final loss = math.max(0.0, ev[best] - ev[i]);
      final lossBb = loss / _bb;
      final grade = gradeForMix(freq: freq[i], lossBb: lossBb, lossFrac: loss / math.max(1, v.pot));
      final order = [for (var k = 0; k < ev.length; k++) k]..sort((x, y) => freq[y].compareTo(freq[x]));
      final mix = [
        for (final k in order)
          if (freq[k] >= 0.05) '${actionLabel(v.actions[k], v).split(' (').first} ${(freq[k] * 100).round()}%',
      ].join(' · ');
      final street = switch (v.board.length) {
        3 => Street.flop,
        4 => Street.turn,
        _ => Street.river,
      };
      final taken = actionLabel(v.actions[i], v);
      review = DecisionReview(
        street: street,
        taken: taken,
        recommended: actionLabel(v.actions[best], v),
        grade: grade,
        explanation: freq[i] >= 0.1
            ? 'Solver: $mix. ${taken.split(' ').first} is part of its strategy with this hand.'
            : 'Solver: $mix. This costs about ${lossBb.toStringAsFixed(1)} bb compared with '
                  '${actionLabel(v.actions[best], v).split(' (').first.toLowerCase()}.',
        lossBb: lossBb,
        solverMix: mix,
      );
    }
    setState(() {
      if (review != null) _reviews.add(review);
      if (review != null) SkillRatings.current.record(review.street == Street.river ? Skill.river : Skill.postflop, review.grade.score / 100);
      _lastReview = review;
      _log.add('You ${actionLabel(v.actions[i], v).toLowerCase()}');
      _path.add(i);
    });
    await _advance();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: p.isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.xl, 0),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.chevron_left, size: 18, color: p.accent),
                        const SizedBox(width: 2),
                        Text('Back', style: Typo.body(p.accent)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (_running && !_summary)
                    Text('Hand $_handNo of ${widget.hands}', style: Typo.callout(p.secondaryLabel)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(Space.xxl, Space.s, Space.xxl, Space.xxl),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: _summary ? _summaryView(p) : (_running ? _play(p) : _setup(p)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _setup(Palette p) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Spot Trainer', style: Typo.largeTitle(p.label)),
      const SizedBox(height: Space.xs),
      Text(
        'Play solved spots against an opponent who follows the solver. Every decision is graded '
        'by how much it gives up.',
        style: Typo.body(p.secondaryLabel),
      ),
      const SizedBox(height: Space.xl),
      SettingsCard(
        title: 'Session',
        icon: CupertinoIcons.scope,
        color: p.surface,
        children: [
          SettingRow(
            label: 'Spot',
            detail: '${_p.detail} · pot ${(_p.potBb).toStringAsFixed(1)} bb',
            below: ChoiceChips<int>(
              value: _preset,
              options: {for (var i = 0; i < studyPresets.length; i++) i: studyPresets[i].label},
              onChanged: (v) => setState(() => _preset = v),
            ),
          ),
          SettingRow(
            label: 'Start on the',
            detail: switch (_street) {
              TrainerStreet.river => 'Earlier streets checked through. Spots are ready instantly.',
              TrainerStreet.turn => 'The flop checked through. Each hand takes a few seconds to prepare.',
              TrainerStreet.flop =>
                'The whole hand. The first spot takes about a minute; later ones are '
                    'prepared while you play.',
            },
            trailing: ChoiceChips<TrainerStreet>(
              value: _street,
              options: {for (final s in TrainerStreet.values) s: s.label},
              onChanged: (v) => setState(() => _street = v),
            ),
          ),
          SettingRow(
            label: 'Play as',
            trailing: ChoiceChips<int>(
              value: _side ?? -1,
              options: {-1: 'Either', 0: _p.oopName, 1: _p.ipName},
              onChanged: (v) => setState(() => _side = v < 0 ? null : v),
            ),
          ),
          Row(
            children: [PillButton(label: 'Start · ${widget.hands} hands', style: PillStyle.filled, onPressed: _start)],
          ),
        ],
      ),
    ],
  );

  Widget _play(Palette p) {
    final q = _q;
    final v = _view;
    final heroCards = q == null ? const <int>[] : [comboCards[q.heroCombo].$1, comboCards[q.heroCombo].$2];
    final villainCards = q == null ? const <int>[] : [comboCards[q.villainCombo].$1, comboCards[q.villainCombo].$2];
    final heroTurn = v != null && v.kind == NodeKind.action && q != null && v.player == q.heroPlayer && !_handOver;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${_p.label} · ${q == null ? '' : 'you are ${_name(q.heroPlayer)}'}', style: Typo.title(p.label)),
        const SizedBox(height: Space.m),
        _Felt(
          board: v?.board ?? q?.spot.board ?? const [],
          hero: heroCards,
          villain: villainCards,
          showVillain: _handOver,
          villainName: q == null ? '' : _name(1 - q.heroPlayer),
          pot: v?.pot ?? q?.spot.pot ?? 0,
        ),
        const SizedBox(height: Space.m),
        if (_waiting)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CupertinoActivityIndicator(),
              const SizedBox(width: Space.s),
              Text('Solving this spot…', style: Typo.callout(p.secondaryLabel)),
            ],
          ),
        if (_log.isNotEmpty) Text(_log.join('  ·  '), style: Typo.callout(p.secondaryLabel)),
        const SizedBox(height: Space.m),
        if (_lastReview != null) ...[
          GlassPanel(
            padding: const EdgeInsets.all(Space.l),
            child: HandReviewList(reviews: [_lastReview!]),
          ),
          const SizedBox(height: Space.m),
        ],
        if (heroTurn)
          CallbackShortcuts(
            bindings: {
              for (var i = 0; i < v.actions.length && i < 9; i++)
                SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i)): () => _act(i),
            },
            child: Focus(
              autofocus: true,
              child: Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                alignment: WrapAlignment.center,
                children: [
                  for (var i = 0; i < v.actions.length; i++)
                    PillButton(
                      label: actionLabel(v.actions[i], v),
                      style: v.actions[i].aggressive ? PillStyle.filled : PillStyle.tinted,
                      minWidth: 0,
                      shortcut: '${i + 1}',
                      onPressed: () => _act(i),
                    ),
                ],
              ),
            ),
          ),
        if (_handOver) ...[
          Text(_result ?? '', textAlign: TextAlign.center, style: Typo.headline(p.label)),
          const SizedBox(height: Space.m),
          Center(
            child: PillButton(
              label: _handNo >= widget.hands ? 'See results' : 'Next hand',
              style: PillStyle.filled,
              onPressed: _handNo >= widget.hands ? _finishSession : _nextHand,
            ),
          ),
        ],
      ],
    );
  }

  Widget _summaryView(Palette p) {
    final lost = _reviews.fold(0.0, (s, r) => s + (r.lossBb ?? 0));
    final acc = accuracyOf(_reviews);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Session results', style: Typo.largeTitle(p.label)),
        const SizedBox(height: Space.l),
        GlassPanel(
          padding: const EdgeInsets.all(Space.l),
          child: Row(
            children: [
              _Stat(label: 'Decisions', value: '${_reviews.length}'),
              _Stat(label: 'Accuracy', value: acc == null ? '–' : '${acc.round()}%'),
              _Stat(label: 'EV given up', value: '${lost.toStringAsFixed(1)} bb'),
            ],
          ),
        ),
        const SizedBox(height: Space.l),
        if (_reviews.isNotEmpty)
          GlassPanel(
            padding: const EdgeInsets.all(Space.l),
            child: HandReviewList(reviews: [..._reviews]..sort((a, b) => (b.lossBb ?? 0).compareTo(a.lossBb ?? 0))),
          ),
        const SizedBox(height: Space.l),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PillButton(label: 'Train again', style: PillStyle.filled, onPressed: _start),
            const SizedBox(width: Space.s),
            PillButton(
              label: 'Change spot',
              style: PillStyle.plain,
              onPressed: () => setState(() {
                _running = false;
                _summary = false;
              }),
            ),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Typo.callout(p.secondaryLabel)),
          const SizedBox(height: 2),
          Text(value, style: Typo.number(p.label, size: 26, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// The felt scene: opponent's cards, board and pot, then ours.
class _Felt extends StatelessWidget {
  const _Felt({
    required this.board,
    required this.hero,
    required this.villain,
    required this.showVillain,
    required this.villainName,
    required this.pot,
  });
  final List<int> board, hero, villain;
  final bool showVillain;
  final String villainName;
  final int pot;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget label(String t) =>
        Text(t, style: Typo.caption(const Color(0xCCFFFFFF)).copyWith(letterSpacing: 1, fontWeight: FontWeight.w600));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.l, horizontal: Space.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xl),
        gradient: RadialGradient(colors: [p.feltCenter, p.feltEdge], radius: 1.2),
      ),
      child: Column(
        children: [
          label(villainName.toUpperCase()),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final c in villain)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: PlayingCard(card: c, width: 46, faceUp: showVillain),
                ),
            ],
          ),
          const SizedBox(height: Space.m),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final c in board)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: PlayingCard(card: c, width: 54),
                ),
            ],
          ),
          const SizedBox(height: 6),
          label('POT ${(pot / _bb).toStringAsFixed(1)} BB'),
          const SizedBox(height: Space.m),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final c in hero)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: PlayingCard(card: c, width: 58, lifted: true),
                ),
            ],
          ),
          const SizedBox(height: 6),
          label('YOU'),
        ],
      ),
    );
  }
}
