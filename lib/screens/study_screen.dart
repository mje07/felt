import 'dart:async';
import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';

import '../app/solver_worker.dart';
import '../app/theme.dart';
import '../widgets/common.dart';
import '../widgets/controls.dart';
import '../widgets/playing_card.dart';
import '../widgets/range_grid.dart';

const _bb = 10;

/// A preflop line that leads to a heads-up postflop spot.
class StudyPreset {
  const StudyPreset(this.label, this.detail, this.oop, this.ip, this.potBb, this.stackBb, this.oopName, this.ipName);
  final String label, detail, oopName, ipName;
  final WeightedRange Function() oop, ip;
  final double potBb, stackBb;
}

final studyPresets = <StudyPreset>[
  StudyPreset('BTN vs BB', 'Button opens, big blind calls', () => WeightedRange.fromChart(bbDefenseChart, raise: false),
      () => WeightedRange.fromChart(chartFor('BTN', PreflopScenario.unopened)), 5.5, 97.5, 'BB', 'BTN'),
  StudyPreset('CO vs BB', 'Cutoff opens, big blind calls', () => WeightedRange.fromChart(bbDefenseChart, raise: false),
      () => WeightedRange.fromChart(chartFor('CO', PreflopScenario.unopened)), 5.5, 97.5, 'BB', 'CO'),
  StudyPreset('UTG vs BB', 'Early raise, big blind calls', () => WeightedRange.fromChart(bbDefenseChart, raise: false),
      () => WeightedRange.fromChart(chartFor('UTG', PreflopScenario.unopened)), 5.5, 97.5, 'BB', 'UTG'),
  StudyPreset('SB vs BB', 'Small blind opens, big blind calls',
      () => WeightedRange.fromChart(chartFor('SB', PreflopScenario.unopened)),
      () => WeightedRange.fromChart(bbDefenseChart, raise: false), 5.0, 97.5, 'SB', 'BB'),
  StudyPreset('BB 3-bets BTN', 'Big blind 3-bets, button calls', () => WeightedRange.fromChart(bbDefenseChart, call: false),
      () => WeightedRange.fromChart(vs3betChart, raise: false), 22.5, 89, 'BB', 'BTN'),
];

/// Colours for solver actions: passive actions blue, folds grey, bets and
/// raises a warm ramp that deepens with size. Always shown with a label.
Color actionColor(Palette p, SolverAction a, int index, int count) {
  switch (a.kind) {
    case 'fold':
      return p.isDark ? const Color(0xFF636366) : const Color(0xFFAEAEB2);
    case 'check':
    case 'call':
      return p.isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);
    default:
      const ramp = [Color(0xFFFFB340), Color(0xFFFF9500), Color(0xFFE8590C), Color(0xFFC92A2A)];
      final aggressive = count - index; // later actions are bigger
      return ramp[(ramp.length - aggressive).clamp(0, ramp.length - 1)];
  }
}

String _bbText(num chips) {
  final v = chips / _bb;
  return v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
}

String actionLabel(SolverAction a, SolverNodeView v) {
  final mine = v.player == 0 ? v.c0 : v.c1;
  switch (a.kind) {
    case 'check':
      return 'Check';
    case 'fold':
      return 'Fold';
    case 'call':
      return 'Call ${_bbText(a.amount)}';
    case 'bet':
      return 'Bet ${_bbText(a.amount - mine)} (${((a.amount - mine) / v.pot * 100).round()}%)';
    case 'raise':
      return 'Raise to ${_bbText(a.amount)}';
    default:
      return 'All-in ${_bbText(a.amount - mine)}';
  }
}

/// Solve heads-up postflop spots on this computer and explore the strategy.
class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key, this.cacheDir});

  /// Overrides where solves are cached (tests pass a temp dir or none).
  final String? cacheDir;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  int _preset = 0;
  final List<int> _board = parseCards('Ks 9d 4c');
  SolverWorker? _worker;
  SolveProgress? _progress;
  bool _solving = false, _solved = false;
  final List<int> _path = [];
  final List<String> _crumbs = [];
  SolverNodeView? _view;
  int? _hover;
  StreamSubscription<SolveProgress>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    _worker?.dispose();
    super.dispose();
  }

  StudyPreset get _p => studyPresets[_preset];

  SolverSpot _spot() => SolverSpot(
        board: List.of(_board),
        pot: (_p.potBb * _bb).round(),
        stack: (_p.stackBb * _bb).round(),
        oop: _p.oop(),
        ip: _p.ip(),
      );

  Future<void> _solve() async {
    setState(() {
      _solving = true;
      _solved = false;
      _progress = null;
      _view = null;
      _path.clear();
      _crumbs.clear();
    });
    final worker = _worker ??= await SolverWorker.spawn();
    final cache = widget.cacheDir ?? await SolverWorker.defaultCacheDir();
    final target = _board.length == 3 ? 1.0 : 0.5;
    _sub?.cancel();
    _sub = worker.solve(_spot(), target: target, cacheDir: cache).listen((p) async {
      if (!mounted) return;
      setState(() => _progress = p);
      if (p.done) {
        final v = await worker.view(const []);
        if (!mounted) return;
        setState(() {
          _solving = false;
          _solved = true;
          _view = v;
        });
      }
    });
  }

  Future<void> _go(int child, String label) async {
    final worker = _worker;
    if (worker == null) return;
    final next = [..._path, child];
    final v = await worker.view(next);
    if (!mounted) return;
    setState(() {
      _path.add(child);
      _crumbs.add(label);
      _view = v;
      _hover = null;
    });
  }

  Future<void> _back(int depth) async {
    final worker = _worker;
    if (worker == null) return;
    final next = _path.sublist(0, depth);
    final v = await worker.view(next);
    if (!mounted) return;
    setState(() {
      _path.removeRange(depth, _path.length);
      _crumbs.removeRange(depth, _crumbs.length);
      _view = v;
    });
  }

  void _toggleBoard(int card) {
    setState(() {
      if (_board.contains(card)) {
        _board.remove(card);
      } else if (_board.length < 5) {
        _board.add(card);
      }
      _solved = false;
      _view = null;
    });
  }

  void _randomFlop() {
    final rng = math.Random();
    final deck = List<int>.generate(52, (i) => i)..shuffle(rng);
    setState(() {
      _board
        ..clear()
        ..addAll(deck.take(3));
      _solved = false;
      _view = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: p.isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      child: SafeArea(
        child: Column(children: [
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
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Study', style: Typo.largeTitle(p.label)),
                    const SizedBox(height: Space.xs),
                    Text('Solve heads-up spots on your own computer and see how to play every hand.',
                        style: Typo.body(p.secondaryLabel)),
                    const SizedBox(height: Space.xl),
                    LayoutBuilder(builder: (context, c) {
                      final wide = c.maxWidth >= 960;
                      final setup = _setup(p);
                      final results = _results(p);
                      return wide
                          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              SizedBox(width: 400, child: setup),
                              const SizedBox(width: Space.l),
                              Expanded(child: results),
                            ])
                          : Column(children: [setup, const SizedBox(height: Space.l), results]);
                    }),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _setup(Palette p) {
    final oop = _p.oop().removeDead(_board), ip = _p.ip().removeDead(_board);
    List<List<GridSegment>> cells(WeightedRange r, Color c) => [
          for (final w in r.gridWeights()) w > 0 ? [GridSegment(c, w)] : const <GridSegment>[],
        ];
    final prog = _progress;
    final canSolve = _board.length >= 3 && !_solving;
    return SettingsCard(
      title: 'Spot',
      icon: CupertinoIcons.scope,
      color: p.surface,
      children: [
        SettingRow(
          label: 'Preflop',
          detail: '${_p.detail} · pot ${_bbText(_p.potBb * _bb)} bb · ${_bbText(_p.stackBb * _bb)} bb behind',
          below: ChoiceChips<int>(
            value: _preset,
            options: {for (var i = 0; i < studyPresets.length; i++) i: studyPresets[i].label},
            onChanged: (v) => setState(() {
              _preset = v;
              _solved = false;
              _view = null;
            }),
          ),
        ),
        SettingRow(
          label: 'Board',
          trailing: PillButton(label: 'Random flop', style: PillStyle.plain, minWidth: 0, height: 30, onPressed: _randomFlop),
          below: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              for (var i = 0; i < 5; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: i < _board.length
                      ? GestureDetector(onTap: () => _toggleBoard(_board[i]), child: PlayingCard(card: _board[i], width: 38))
                      : Container(
                          width: 38,
                          height: 53,
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6), border: Border.all(color: p.separator))),
                ),
            ]),
            const SizedBox(height: Space.s),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: CardPicker(selected: _board, onToggle: _toggleBoard, tile: 24),
            ),
          ]),
        ),
        SettingRow(
          label: 'Ranges',
          detail: '${_p.oopName} (out of position, left) and ${_p.ipName} (in position, right), from the preflop charts.',
          below: Row(children: [
            Expanded(child: RangeGrid(cells: cells(oop, p.accent), maxSize: 180)),
            const SizedBox(width: Space.m),
            Expanded(child: RangeGrid(cells: cells(ip, const Color(0xFFFF9500)), maxSize: 180)),
          ]),
        ),
        SettingRow(
          label: _board.length == 3
              ? 'Flop solves take about a minute'
              : (_board.length == 4 ? 'Turn solves take a few seconds' : 'River solves are instant'),
          detail: 'Sizes: flop ⅓ and ¾ pot, turn ⅔, river ½ and pot, one raise. '
              '${_board.length == 3 ? 'Flops model a spread of 8 turn and 6 river cards.' : ''}',
        ),
        Row(children: [
          PillButton(
            label: _solving ? 'Solving…' : (_solved ? 'Solve again' : 'Solve'),
            style: PillStyle.filled,
            onPressed: canSolve ? _solve : null,
          ),
          const SizedBox(width: Space.s),
          if (_solving)
            PillButton(label: 'Stop', style: PillStyle.plain, minWidth: 0, onPressed: () => _worker?.stop()),
        ]),
        if (prog != null)
          Text(
            prog.fromCache
                ? 'Loaded from your saved solves.'
                : '${prog.iterations} iterations · ${(prog.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s · '
                    'exploitable by ${prog.exploitability.isFinite ? prog.exploitability.toStringAsFixed(2) : '–'}% of the pot',
            style: Typo.callout(p.secondaryLabel),
          ),
      ],
    );
  }

  Widget _results(Palette p) {
    final v = _view;
    if (v == null) {
      return GlassPanel(
        padding: const EdgeInsets.all(Space.xl),
        child: SizedBox(
          height: 420,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(CupertinoIcons.scope, size: 40, color: p.tertiaryLabel),
              const SizedBox(height: Space.m),
              Text(_solving ? 'Solving…' : 'Pick a spot and a board, then press Solve.',
                  style: Typo.body(p.secondaryLabel)),
              if (_solving) ...[const SizedBox(height: Space.m), const CupertinoActivityIndicator()],
            ]),
          ),
        ),
      );
    }
    return SettingsCard(
      title: _nodeTitle(v),
      icon: v.kind == NodeKind.chance ? CupertinoIcons.suit_club_fill : CupertinoIcons.person_fill,
      color: p.surface,
      children: [
        _Breadcrumbs(crumbs: _crumbs, onTap: _back),
        Row(children: [
          for (final c in v.board) Padding(padding: const EdgeInsets.only(right: 4), child: PlayingCard(card: c, width: 32)),
          const Spacer(),
          Text('Pot ${_bbText(v.pot)} bb', style: Typo.number(p.secondaryLabel, size: 13)),
        ]),
        if (v.kind == NodeKind.action) ..._actionNode(p, v),
        if (v.kind == NodeKind.chance)
          SettingRow(
            label: 'Deal the ${v.board.length == 3 ? 'turn' : 'river'}',
            detail: v.cards.length < 40 ? 'This solve models a spread of these cards.' : null,
            below: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: CardPicker(
                selected: const [],
                blocked: {for (var c = 0; c < 52; c++) if (!v.cards.contains(c)) c},
                onToggle: (c) => _go(v.cards.indexOf(c), '${v.board.length == 3 ? 'Turn' : 'River'} ${cardToString(c)}'),
                tile: 28,
              ),
            ),
          ),
        if (v.kind == NodeKind.fold || v.kind == NodeKind.showdown)
          Text(v.kind == NodeKind.fold ? 'The hand ends with a fold.' : 'The hand goes to showdown.',
              style: Typo.body(p.secondaryLabel)),
      ],
    );
  }

  String _nodeTitle(SolverNodeView v) => switch (v.kind) {
        NodeKind.action => '${v.player == 0 ? _oopName : _ipName} to act',
        NodeKind.chance => 'Next card',
        _ => 'End of hand',
      };

  String get _oopName => _p.oopName;
  String get _ipName => _p.ipName;

  List<Widget> _actionNode(Palette p, SolverNodeView v) {
    final freqs = v.actionFrequencies;
    final colors = [for (var i = 0; i < v.actions.length; i++) actionColor(p, v.actions[i], i, v.actions.length)];
    final h = v.hands.length;
    // Per grid cell: reach-weighted action mix, scaled by how much of the cell is in range.
    final sums = List.generate(169, (_) => List<double>.filled(v.actions.length, 0));
    final total = List<double>.filled(169, 0);
    final evSum = List<double>.filled(169, 0);
    for (var j = 0; j < h; j++) {
      final r = v.reach[j];
      if (r <= 0) continue;
      final cell = comboCell[v.hands[j]];
      total[cell] += r;
      for (var i = 0; i < v.actions.length; i++) {
        sums[cell][i] += r * v.strategy[i * h + j];
      }
      if (!v.ev[j].isNaN) evSum[cell] += r * v.ev[j];
    }
    final cells = [
      for (var c = 0; c < 169; c++)
        [
          for (var i = 0; i < v.actions.length; i++)
            GridSegment(colors[i], sums[c][i] / cellCombos[c].length),
        ],
    ];
    final hover = _hover;
    String? hoverText;
    if (hover != null && total[hover] > 0) {
      final mix = [
        for (var i = 0; i < v.actions.length; i++)
          if (sums[hover][i] / total[hover] >= 0.005)
            '${actionLabel(v.actions[i], v).split(' (').first} ${(sums[hover][i] / total[hover] * 100).round()}%',
      ].join(' · ');
      hoverText = '${startingHandName(hover)}: $mix · EV ${(evSum[hover] / total[hover] / _bb).toStringAsFixed(2)} bb';
    } else if (hover != null) {
      hoverText = '${startingHandName(hover)} isn\'t in this range here.';
    }
    final combos = total.fold(0.0, (s, x) => s + x);
    return [
      Wrap(spacing: Space.s, runSpacing: Space.s, children: [
        for (var i = 0; i < v.actions.length; i++)
          _ActionButton(
            label: actionLabel(v.actions[i], v),
            share: freqs[i],
            color: colors[i],
            onTap: () => _go(i, '${v.player == 0 ? _oopName : _ipName} ${actionLabel(v.actions[i], v).split(' (').first.toLowerCase()}'),
          ),
      ]),
      _FrequencyBar(freqs: freqs, colors: colors),
      RangeGrid(cells: cells, maxSize: 720, onHover: (i) => setState(() => _hover = i)),
      SizedBox(
        height: 20,
        child: Text(hoverText ?? '${combos.toStringAsFixed(0)} combos in range here. Hover a hand for its mix and EV.',
            style: Typo.callout(p.secondaryLabel)),
      ),
    ];
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.crumbs, required this.onTap});
  final List<String> crumbs;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final items = ['Start', ...crumbs];
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) Icon(CupertinoIcons.chevron_right, size: 12, color: p.tertiaryLabel),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          minimumSize: Size.zero,
          onPressed: i == items.length - 1 ? null : () => onTap(i),
          child: Text(items[i],
              style: Typo.callout(i == items.length - 1 ? p.label : p.accent)),
        ),
      ],
    ]);
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.share, required this.color, required this.onTap});
  final String label;
  final double share;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: p.surfaceRaised,
            borderRadius: BorderRadius.circular(Radii.m),
            border: Border.all(color: p.separator),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Typo.callout(p.label)),
              Text('${(share * 100).toStringAsFixed(1)}%', style: Typo.number(p.secondaryLabel, size: 12)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _FrequencyBar extends StatelessWidget {
  const _FrequencyBar({required this.freqs, required this.colors});
  final List<double> freqs;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 10,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < freqs.length; i++)
            if (freqs[i] > 0.001)
              Expanded(
                flex: (freqs[i] * 1000).round().clamp(1, 1000),
                child: Padding(
                  padding: EdgeInsets.only(right: i < freqs.length - 1 ? 2 : 0),
                  child: ColoredBox(color: colors[i]),
                ),
              ),
        ]),
      ),
    );
  }
}
