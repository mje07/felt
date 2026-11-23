import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';

import '../app/history_store.dart';
import '../app/theme.dart';
import '../widgets/charts.dart';

/// Chart entries shown in the sidebar.
class _Entry {
  const _Entry(this.section, this.label, this.position, this.scenario);
  final String section, label, position;
  final PreflopScenario scenario;
  bool get isOpen => scenario == PreflopScenario.unopened;
  RangeChart get chart => chartFor(position, scenario);
}

const _entries = [
  _Entry('Open raise', 'Under the gun', 'UTG', PreflopScenario.unopened),
  _Entry('Open raise', 'Middle position', 'MP', PreflopScenario.unopened),
  _Entry('Open raise', 'Hijack', 'HJ', PreflopScenario.unopened),
  _Entry('Open raise', 'Cutoff', 'CO', PreflopScenario.unopened),
  _Entry('Open raise', 'Button', 'BTN', PreflopScenario.unopened),
  _Entry('Open raise', 'Small blind', 'SB', PreflopScenario.unopened),
  _Entry('Facing a raise', 'vs early raise', 'BTN', PreflopScenario.vsEarlyOpen),
  _Entry('Facing a raise', 'vs late raise', 'BTN', PreflopScenario.vsLateOpen),
  _Entry('Facing a raise', 'Big blind defence', 'BB', PreflopScenario.bbDefense),
  _Entry('Facing a raise', 'Facing a 3-bet', 'CO', PreflopScenario.vs3bet),
];

/// Categorical slots 1 and 2 (blue, orange) from the validated palette.
(Color, Color) _actionColors(Palette p) =>
    p.isDark ? (const Color(0xFF3987E5), const Color(0xFFD95926)) : (const Color(0xFF2A78D6), const Color(0xFFEB6834));

class RangeScreen extends StatefulWidget {
  const RangeScreen({super.key, required this.history, this.initialPosition});
  final HistoryStore history;
  final String? initialPosition;

  @override
  State<RangeScreen> createState() => _RangeScreenState();
}

class _RangeScreenState extends State<RangeScreen> {
  late int _selected = math.max(0, _entries.indexWhere((e) => e.isOpen && e.position == widget.initialPosition));
  bool _compare = false;
  int? _hover;
  late final PlayerStats _stats = computeStats(widget.history.hands);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final entry = _entries[_selected];
    final chart = entry.chart;
    final (raiseC, callC) = _actionColors(p);
    final dealt = entry.isOpen ? _stats.rfiDealt[entry.position] : null;
    final played = entry.isOpen ? _stats.rfiPlayed[entry.position] : null;
    final hasData = dealt != null && dealt.any((d) => d > 0);
    final compare = _compare && hasData;

    // Deviation markers: + played though outside the chart, − folded though inside.
    final loose = <int>{}, tight = <int>{};
    if (compare) {
      for (var i = 0; i < 169; i++) {
        if (dealt[i] == 0) continue;
        final frac = played![i] / dealt[i];
        final inRange = chart.played.contains(i);
        if (!inRange && frac >= 0.5) loose.add(i);
        if (inRange && frac < 0.5) tight.add(i);
      }
    }

    return CupertinoPageScaffold(
      backgroundColor: p.isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      child: SafeArea(
        child: Column(
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
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Range Charts', style: Typo.largeTitle(p.label)),
                        const SizedBox(height: Space.xs),
                        Text('Baseline 100 big blind ranges: a solid starting point, not solver output.',
                            style: Typo.body(p.secondaryLabel)),
                        const SizedBox(height: Space.xl),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 230, child: _sidebar(p)),
                            const SizedBox(width: Space.xl),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(Space.xl),
                                decoration: BoxDecoration(
                                  color: p.surface,
                                  borderRadius: BorderRadius.circular(Radii.l),
                                  border: Border.all(color: p.separator, width: 0.5),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Expanded(
                                        child: Text(chart.title, style: Typo.title(p.label)),
                                      ),
                                      if (entry.isOpen) ...[
                                        Text('Compare with my play', style: Typo.callout(p.secondaryLabel)),
                                        const SizedBox(width: Space.s),
                                        CupertinoSwitch(
                                          value: _compare,
                                          onChanged: hasData ? (v) => setState(() => _compare = v) : null,
                                        ),
                                      ],
                                    ]),
                                    const SizedBox(height: Space.s),
                                    Wrap(spacing: Space.l, runSpacing: 6, children: [
                                      _Legend(color: raiseC, label: 'Raise', value: rangeFraction(chart.raise)),
                                      if (chart.call.isNotEmpty)
                                        _Legend(color: callC, label: 'Call', value: rangeFraction(chart.call)),
                                      _Legend(
                                          color: null, label: 'Fold', value: 1 - rangeFraction(chart.played)),
                                    ]),
                                    const SizedBox(height: Space.l),
                                    _grid(p, chart, raiseC, callC, compare, loose, tight, dealt, played),
                                    const SizedBox(height: Space.m),
                                    if (entry.isOpen && !hasData)
                                      Text('Play some hands from the ${entry.position} to compare your opens.',
                                          style: Typo.callout(p.tertiaryLabel))
                                    else if (compare)
                                      Text(
                                        loose.isEmpty && tight.isEmpty
                                            ? 'Your opens from the ${entry.position} match the chart so far.'
                                            : '+ marks ${loose.length} hand${loose.length == 1 ? '' : 's'} you usually play '
                                                'but the chart folds; − marks ${tight.length} chart hand'
                                                '${tight.length == 1 ? '' : 's'} you usually fold.',
                                        style: Typo.callout(p.secondaryLabel),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebar(Palette p) {
    final children = <Widget>[];
    String? section;
    for (final (i, e) in _entries.indexed) {
      if (e.section != section) {
        section = e.section;
        children.add(Padding(
          padding: EdgeInsets.fromLTRB(12, children.isEmpty ? 0 : Space.l, 0, 6),
          child: Text(section.toUpperCase(), style: Typo.caption(p.secondaryLabel).copyWith(letterSpacing: 0.8)),
        ));
      }
      final sel = i == _selected;
      children.add(MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => setState(() {
            _selected = i;
            _hover = null;
          }),
          child: AnimatedContainer(
            duration: Motion.fast,
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: sel ? p.accent.withValues(alpha: 0.14) : const Color(0x00000000),
              borderRadius: BorderRadius.circular(Radii.s),
            ),
            child: Row(children: [
              Expanded(child: Text(e.label, style: Typo.body(sel ? p.accent : p.label))),
              if (e.isOpen) Text(e.position, style: Typo.caption(p.tertiaryLabel)),
            ]),
          ),
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _grid(Palette p, RangeChart chart, Color raiseC, Color callC, bool compare, Set<int> loose, Set<int> tight,
      List<int>? dealt, List<int>? played) {
    return LayoutBuilder(builder: (context, c) {
      final side = math.min(c.maxWidth, 520.0);
      final cell = (side - 24) / 13;
      final h = _hover;
      return SizedBox(
        width: side,
        height: side,
        child: Stack(clipBehavior: Clip.none, children: [
          for (var row = 0; row < 13; row++)
            for (var col = 0; col < 13; col++)
              () {
                final i = (12 - row) * 13 + (12 - col);
                final action = chart.actionFor(i);
                final fill = action == PreAction.raise ? raiseC : (action == PreAction.call ? callC : null);
                final mark = loose.contains(i) ? '+' : (tight.contains(i) ? '−' : null);
                return Positioned(
                  left: col * (cell + 2),
                  top: row * (cell + 2),
                  width: cell,
                  height: cell,
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _hover = i),
                    onExit: (_) => setState(() => _hover = null),
                    child: Container(
                      decoration: BoxDecoration(
                        color: fill ?? (p.isDark ? const Color(0x0FFFFFFF) : const Color(0x0A000000)),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: h == i ? p.label : (mark != null ? p.label.withValues(alpha: 0.7) : const Color(0x00000000)),
                          width: mark != null || h == i ? 1.5 : 0,
                        ),
                      ),
                      child: Stack(children: [
                        Center(
                          child: Text(
                            startingHandName(i).replaceAll('o', ''),
                            style: TextStyle(
                              fontFamily: Typo.family,
                              fontSize: cell * 0.3,
                              fontWeight: FontWeight.w600,
                              color: fill != null ? const Color(0xFFFFFFFF) : p.tertiaryLabel,
                            ),
                          ),
                        ),
                        if (mark != null)
                          Positioned(
                            right: 3,
                            top: 0,
                            child: Text(mark,
                                style: TextStyle(
                                    fontFamily: Typo.family,
                                    fontSize: cell * 0.36,
                                    fontWeight: FontWeight.w700,
                                    color: fill != null ? const Color(0xFFFFFFFF) : p.label)),
                          ),
                      ]),
                    ),
                  ),
                );
              }(),
          if (h != null)
            positionedTooltip(
              Offset(((12 - h % 13)) * (cell + 2) + cell / 2, (12 - h ~/ 13) * (cell + 2) + cell / 2),
              Size(side, side),
              ChartTooltip(
                title: startingHandName(h),
                lines: [
                  'Chart: ${switch (chart.actionFor(h)) { PreAction.raise => 'raise', PreAction.call => 'call', _ => 'fold' }}',
                  if (compare && dealt != null && dealt[h] > 0) 'You played ${played![h]} of ${dealt[h]}',
                ],
              ),
              width: 160,
            ),
        ]),
      );
    });
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, required this.value});
  final Color? color;
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color ?? (p.isDark ? const Color(0x0FFFFFFF) : const Color(0x0A000000)),
          borderRadius: BorderRadius.circular(3),
          border: color == null ? Border.all(color: p.separator) : null,
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: Typo.callout(p.label)),
      const SizedBox(width: 4),
      Text('${(value * 100).round()}%', style: Typo.number(p.secondaryLabel, size: 12.5)),
    ]);
  }
}
