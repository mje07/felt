import 'dart:async';
import 'dart:isolate';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';

import '../app/theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/controls.dart';
import '../widgets/playing_card.dart';
import '../widgets/range_grid.dart';

/// Range-vs-range equity and hand-class breakdown on any board: Felt's
/// Equilab / Flopzilla.
class EquityLabScreen extends StatefulWidget {
  const EquityLabScreen({super.key});

  @override
  State<EquityLabScreen> createState() => _EquityLabScreenState();
}

/// Fixed categorical order for players (never re-assigned when one is
/// removed); always shown with a name, so colour is never the only cue.
List<Color> playerColors(Palette p) => p.isDark
    ? const [Color(0xFF0A84FF), Color(0xFFFF9F0A), Color(0xFF40C8E0), Color(0xFFBF5AF2)]
    : const [Color(0xFF007AFF), Color(0xFFFF9500), Color(0xFF30B0C7), Color(0xFFAF52DE)];

class _Player {
  _Player(this.slot, this.range) : text = TextEditingController(text: range.toNotation());
  final int slot;
  WeightedRange range;
  final TextEditingController text;
}

typedef _Preset = (String, WeightedRange Function());

final List<_Preset> _presets = [
  ('Any two', WeightedRange.full),
  ('Top 5%', () => WeightedRange.fromWidth(0.05)),
  ('Top 15%', () => WeightedRange.fromWidth(0.15)),
  ('Top 30%', () => WeightedRange.fromWidth(0.30)),
  ('UTG open', () => WeightedRange.fromChart(chartFor('UTG', PreflopScenario.unopened))),
  ('CO open', () => WeightedRange.fromChart(chartFor('CO', PreflopScenario.unopened))),
  ('BTN open', () => WeightedRange.fromChart(chartFor('BTN', PreflopScenario.unopened))),
  ('BB defend', () => WeightedRange.fromChart(bbDefenseChart)),
  ('3-bet', () => WeightedRange.fromChart(vs3betChart, call: false)),
];

class _EquityLabScreenState extends State<EquityLabScreen> {
  late final List<_Player> _players = [
    _Player(0, WeightedRange.fromChart(chartFor('BTN', PreflopScenario.unopened))),
    _Player(1, WeightedRange.fromChart(bbDefenseChart)),
  ];
  int _sel = 0;
  final List<int> _board = [];
  double _brush = 1;
  bool _paintOn = true, _showEquity = false, _busy = false;
  RangeEquity? _result;
  HandClass? _focus;
  int? _hover;
  Timer? _debounce;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final p in _players) {
      p.text.dispose();
    }
    super.dispose();
  }

  _Player get _current => _players[_sel];

  void _changed({bool syncText = true}) {
    if (syncText) _current.text.text = _current.range.toNotation();
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _recompute);
  }

  Future<void> _recompute() async {
    final ranges = [for (final p in _players) p.range];
    if (ranges.any((r) => r.removeDead(_board).isEmpty)) {
      setState(() => _result = null);
      return;
    }
    final token = ++_token;
    setState(() => _busy = true);
    final board = List.of(_board);
    final result = await _computeEquity(ranges, board);
    if (!mounted || token != _token) return;
    setState(() {
      _result = result;
      _busy = false;
    });
  }

  void _paint(int cell, bool start) {
    final r = _current.range;
    if (start) _paintOn = r.gridWeights()[cell] < 0.5;
    r.setCell(cell, _paintOn ? _brush : 0);
    _changed();
  }

  void _onTextChanged(String text) {
    try {
      _current.range = text.trim().isEmpty ? WeightedRange() : WeightedRange.fromNotation(text);
      _changed(syncText: false);
    } on FormatException {
      // Keep the last valid range while the user is typing.
    }
  }

  void _toggleCard(int card) {
    setState(() {
      if (_board.contains(card)) {
        _board.remove(card);
      } else if (_board.length < 5) {
        _board.add(card);
      }
      if (_board.length < 3) _focus = null;
    });
    // A two-card "board" isn't a street: wait for the third card.
    if (_board.length != 1 && _board.length != 2) _changed(syncText: false);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final cc = ChartColors.of(context);
    final colors = playerColors(p);
    final result = _result;
    final range = _current.range;
    final breakdown = _board.length >= 3 ? handClassBreakdown(range, _board) : null;
    final focusCells = _focus == null || breakdown == null
        ? <int>{}
        : {for (final i in breakdown.members[_focus] ?? const <int>[]) comboCell[i]};

    // Grid fill: the range in its player colour, or each hand's equity.
    final weights = range.removeDead(_board).gridWeights();
    final heq = result?.handEquity[_sel];
    final cells = <List<GridSegment>>[
      for (var i = 0; i < 169; i++)
        if (weights[i] <= 0)
          const []
        else if (_showEquity && heq != null)
          [GridSegment(cc.diverging((_cellEquity(heq, i) - 0.5) * 2), 1)]
        else
          [GridSegment(colors[_current.slot], weights[i])],
    ];

    return CupertinoPageScaffold(
      backgroundColor: p.isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      child: SafeArea(
        child: Column(children: [
          _BackRow(p: p),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Space.xxl, Space.s, Space.xxl, Space.xxl),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Equity Lab', style: Typo.largeTitle(p.label)),
                    const SizedBox(height: Space.xs),
                    Text('Range against range on any board, and what each range holds.',
                        style: Typo.body(p.secondaryLabel)),
                    const SizedBox(height: Space.xl),
                    _EquityBar(players: _players, result: result, busy: _busy, colors: colors),
                    const SizedBox(height: Space.l),
                    LayoutBuilder(builder: (context, c) {
                      final wide = c.maxWidth >= 900;
                      final left = _rangeEditor(p, cells, focusCells, heq, colors);
                      final right = _sidePanel(p, breakdown, heq, colors);
                      return wide
                          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(flex: 11, child: left),
                              const SizedBox(width: Space.l),
                              Expanded(flex: 9, child: right),
                            ])
                          : Column(children: [left, const SizedBox(height: Space.l), right]);
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

  double _cellEquity(List<double> heq, int cell) {
    var s = 0.0, n = 0;
    for (final i in cellCombos[cell]) {
      final v = heq[i];
      if (v.isNaN) continue;
      s += v;
      n++;
    }
    return n == 0 ? 0.5 : s / n;
  }

  Widget _rangeEditor(Palette p, List<List<GridSegment>> cells, Set<int> focus, List<double>? heq, List<Color> colors) {
    final hover = _hover;
    String? hoverText;
    if (hover != null) {
      final name = startingHandName(hover);
      final w = _current.range.removeDead(_board).gridWeights()[hover];
      hoverText = w <= 0
          ? '$name · not in range'
          : '$name · ${(w * 100).round()}% weight'
              '${heq != null ? ' · equity ${(_cellEquity(heq, hover) * 100).toStringAsFixed(1)}%' : ''}';
    }
    return SettingsCard(
      title: 'Ranges',
      icon: CupertinoIcons.square_grid_3x2_fill,
      color: p.surface,
      children: [
        // Player tabs.
        Wrap(spacing: Space.s, runSpacing: Space.s, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (var i = 0; i < _players.length; i++)
            _PlayerTab(
              label: 'Player ${_players[i].slot + 1}',
              combos: _players[i].range.removeDead(_board).combos,
              color: colors[_players[i].slot],
              selected: i == _sel,
              onTap: () => setState(() {
                _sel = i;
                _focus = null;
              }),
              onRemove: _players.length > 2
                  ? () {
                      setState(() {
                        _players.removeAt(i).text.dispose();
                        _sel = 0;
                      });
                      _changed(syncText: false);
                    }
                  : null,
            ),
          if (_players.length < 4)
            PillButton(
              label: 'Add player',
              style: PillStyle.plain,
              minWidth: 0,
              height: 32,
              onPressed: () {
                final used = {for (final pl in _players) pl.slot};
                final slot = [0, 1, 2, 3].firstWhere((s) => !used.contains(s));
                setState(() {
                  _players.add(_Player(slot, WeightedRange.full()));
                  _sel = _players.length - 1;
                });
                _changed(syncText: false);
              },
            ),
        ]),
        SettingRow(
          label: 'Presets',
          below: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (label, make) in _presets)
              PillButton(
                label: label,
                style: PillStyle.tinted,
                minWidth: 0,
                height: 30,
                onPressed: () {
                  _current.range = make();
                  _changed();
                },
              ),
            PillButton(
              label: 'Clear',
              style: PillStyle.plain,
              minWidth: 0,
              height: 30,
              onPressed: () {
                _current.range = WeightedRange();
                _changed();
              },
            ),
          ]),
        ),
        SettingRow(
          label: 'Brush',
          detail: 'Drag across the grid to add or remove hands at this weight.',
          trailing: ChoiceChips<double>(
            value: _brush,
            options: {1.0: '100%', 0.75: '75%', 0.5: '50%', 0.25: '25%'},
            onChanged: (v) => setState(() => _brush = v),
          ),
        ),
        RangeGrid(
          cells: cells,
          highlight: focus,
          onPaint: _paint,
          onHover: (i) => setState(() => _hover = i),
        ),
        SizedBox(
          height: 20,
          child: Text(hoverText ?? (_showEquity ? 'Blue: ahead of the other ranges · red: behind' : ''),
              style: Typo.callout(p.secondaryLabel)),
        ),
        SettingRow(
          label: 'Colour by equity',
          detail: 'Show how each hand does against the other ranges.',
          trailing: FeltToggle(
            label: 'Colour by equity',
            value: _showEquity,
            onChanged: (v) => setState(() => _showEquity = v),
          ),
        ),
        SettingRow(
          label: 'Range text',
          below: FeltTextField(
            controller: _current.text,
            placeholder: 'e.g. 22+, A2s+, KTo+',
            width: double.infinity,
            onChanged: _onTextChanged,
          ),
        ),
      ],
    );
  }

  Widget _sidePanel(Palette p, ClassBreakdown? breakdown, List<double>? heq, List<Color> colors) {
    final blocked = <int>{};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsCard(
        title: 'Board',
        icon: CupertinoIcons.suit_diamond_fill,
        color: p.surface,
        children: [
          Row(children: [
            for (var i = 0; i < 5; i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: i < _board.length
                    ? GestureDetector(
                        onTap: () => _toggleCard(_board[i]),
                        child: PlayingCard(card: _board[i], width: 40),
                      )
                    : Container(
                        width: 40,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: p.separator),
                        ),
                      ),
              ),
            const Spacer(),
            if (_board.isNotEmpty)
              PillButton(
                label: 'Clear',
                style: PillStyle.plain,
                minWidth: 0,
                height: 30,
                onPressed: () {
                  setState(() {
                    _board.clear();
                    _focus = null;
                  });
                  _changed(syncText: false);
                },
              ),
          ]),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: CardPicker(selected: _board, blocked: blocked, onToggle: _toggleCard, tile: 28),
          ),
          if (_board.length == 1 || _board.length == 2)
            Text('Pick ${3 - _board.length} more for a flop.', style: Typo.callout(p.secondaryLabel)),
        ],
      ),
      const SizedBox(height: Space.l),
      SettingsCard(
        title: breakdown == null ? 'What the range holds' : 'Player ${_current.slot + 1} on this board',
        icon: CupertinoIcons.list_bullet,
        color: p.surface,
        children: [
          if (breakdown == null)
            Text('Add a flop to break the range down into made hands and draws.',
                style: Typo.callout(p.secondaryLabel))
          else
            _ClassTable(
              breakdown: breakdown,
              heq: heq,
              color: colors[_current.slot],
              focus: _focus,
              onFocus: (c) => setState(() => _focus = _focus == c ? null : c),
            ),
        ],
      ),
    ]);
  }
}

class _BackRow extends StatelessWidget {
  const _BackRow({required this.p});
  final Palette p;

  @override
  Widget build(BuildContext context) => Padding(
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
      );
}

class _PlayerTab extends StatelessWidget {
  const _PlayerTab({
    required this.label,
    required this.combos,
    required this.color,
    required this.selected,
    required this.onTap,
    this.onRemove,
  });
  final String label;
  final double combos;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: Motion.fast,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.16) : p.surfaceRaised,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? color : p.separator),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: Typo.callout(p.label)),
            const SizedBox(width: 6),
            Text('${(combos / 1326 * 100).toStringAsFixed(1)}%', style: Typo.number(p.secondaryLabel, size: 12)),
            if (onRemove != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onRemove,
                child: Icon(CupertinoIcons.xmark, size: 12, color: p.secondaryLabel),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _EquityBar extends StatelessWidget {
  const _EquityBar({required this.players, required this.result, required this.busy, required this.colors});
  final List<_Player> players;
  final RangeEquity? result;
  final bool busy;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final r = result;
    return GlassPanel(
      padding: const EdgeInsets.all(Space.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          for (var i = 0; i < players.length; i++) ...[
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: colors[players[i].slot], shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('Player ${players[i].slot + 1}', style: Typo.callout(p.secondaryLabel)),
                ]),
                const SizedBox(height: 2),
                Text(r == null || i >= r.equity.length ? '–' : '${(r.equity[i] * 100).toStringAsFixed(1)}%',
                    style: Typo.number(p.label, size: 26, weight: FontWeight.w700)),
              ]),
            ),
          ],
          if (busy) const CupertinoActivityIndicator(),
        ]),
        const SizedBox(height: Space.m),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: r == null
                ? DecoratedBox(decoration: BoxDecoration(color: p.separator))
                : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = 0; i < r.equity.length && i < players.length; i++)
                      Expanded(
                        flex: (r.equity[i] * 1000).round().clamp(1, 1000),
                        child: Padding(
                          padding: EdgeInsets.only(right: i < r.equity.length - 1 ? 2 : 0),
                          child: ColoredBox(color: colors[players[i].slot]),
                        ),
                      ),
                  ]),
          ),
        ),
        const SizedBox(height: Space.s),
        Text(
          r == null
              ? 'Every player needs at least one hand.'
              : r.exact
                  ? 'Exact: all ${formatChips(r.runouts)} runouts.'
                  : 'Estimated from ${formatChips(r.runouts)} random deals (±0.5%).',
          style: Typo.caption(p.tertiaryLabel),
        ),
      ]),
    );
  }
}

class _ClassTable extends StatelessWidget {
  const _ClassTable({
    required this.breakdown,
    required this.heq,
    required this.color,
    required this.focus,
    required this.onFocus,
  });
  final ClassBreakdown breakdown;
  final List<double>? heq;
  final Color color;
  final HandClass? focus;
  final ValueChanged<HandClass> onFocus;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final rows = [for (final c in HandClass.values) if ((breakdown.combos[c] ?? 0) > 0) c];
    double? classEquity(HandClass c) {
      final h = heq;
      if (h == null) return null;
      var s = 0.0, n = 0;
      for (final i in breakdown.members[c] ?? const <int>[]) {
        if (h[i].isNaN) continue;
        s += h[i];
        n++;
      }
      return n == 0 ? null : s / n;
    }

    Widget row(HandClass c) {
      final share = breakdown.share(c);
      final eq = classEquity(c);
      final on = focus == c;
      return GestureDetector(
        onTap: () => onFocus(c),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
            decoration: BoxDecoration(
              color: on ? color.withValues(alpha: 0.14) : const Color(0x00000000),
              borderRadius: BorderRadius.circular(Radii.s),
            ),
            child: Row(children: [
              Expanded(flex: 5, child: Text(c.label, style: Typo.callout(p.label))),
              Expanded(
                flex: 4,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: share.clamp(0.02, 1.0),
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 52,
                child: Text('${(share * 100).toStringAsFixed(1)}%',
                    textAlign: TextAlign.right, style: Typo.number(p.label, size: 12)),
              ),
              SizedBox(
                width: 64,
                child: Text(eq == null ? '' : 'eq ${(eq * 100).round()}%',
                    textAlign: TextAlign.right, style: Typo.number(p.secondaryLabel, size: 12)),
              ),
            ]),
          ),
        ),
      );
    }

    final made = rows.where((c) => !c.isDraw).toList(), draws = rows.where((c) => c.isDraw).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${breakdown.total.toStringAsFixed(0)} combos · tap a row to find those hands on the grid',
          style: Typo.caption(p.tertiaryLabel)),
      const SizedBox(height: Space.s),
      ...made.map(row),
      if (draws.isNotEmpty) ...[
        const SizedBox(height: Space.s),
        Text('DRAWS', style: Typo.caption(p.secondaryLabel).copyWith(letterSpacing: 1)),
        const SizedBox(height: 2),
        ...draws.map(row),
      ],
    ]);
  }
}

/// Top-level so the isolate closure captures only the ranges and board.
Future<RangeEquity> _computeEquity(List<WeightedRange> ranges, List<int> board) =>
    Isolate.run(() => rangeVsRange(ranges, board));
