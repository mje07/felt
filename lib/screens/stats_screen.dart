import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';

import '../app/history_store.dart';
import '../app/theme.dart';
import '../app/drill_progress.dart';
import '../widgets/charts.dart';
import '../widgets/controls.dart';
import '../widgets/review_panel.dart';
import 'range_screen.dart';
import 'training_screen.dart';

enum StatsRange {
  last100('Last 100', 100),
  last1000('Last 1,000', 1000),
  all('All time', null);

  const StatsRange(this.label, this.count);
  final String label;
  final int? count;
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.history});
  final HistoryStore history;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  StatsRange _range = StatsRange.all;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final all = widget.history.hands;
    final n = _range.count;
    final hands = n == null || all.length <= n ? all : all.sublist(all.length - n);
    final stats = computeStats(hands);
    final profile = profileFor(stats);

    return CupertinoPageScaffold(
      backgroundColor: p.isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.xl, Space.s),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Row(children: [
                      Icon(CupertinoIcons.chevron_left, size: 18, color: p.accent),
                      const SizedBox(width: 2),
                      Text('Back', style: Typo.body(p.accent)),
                    ]),
                  ),
                  const Spacer(),
                  ChoiceChips<StatsRange>(
                    value: _range,
                    options: {for (final r in StatsRange.values) r: r.label},
                    onChanged: (v) => setState(() => _range = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: stats.hands == 0
                  ? _Empty()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xxl),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1080),
                          child: _Body(stats: stats, profile: profile, history: widget.history),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.chart_bar_alt_fill, size: 44, color: p.tertiaryLabel),
          const SizedBox(height: Space.m),
          Text('No hands yet', style: Typo.title(p.label)),
          const SizedBox(height: Space.xs),
          Text('Play a few hands and your statistics will appear here.', style: Typo.body(p.secondaryLabel)),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.stats, required this.profile, required this.history});
  final PlayerStats stats;
  final PlayerProfile? profile;
  final HistoryStore history;



  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 860;
      Widget pair(Widget a, Widget b, {int fa = 1, int fb = 1}) => wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: fa, child: a),
                const SizedBox(width: Space.l),
                Expanded(flex: fb, child: b),
            ])
          : Column(children: [a, const SizedBox(height: Space.l), b]);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Statistics', style: Typo.largeTitle(p.label)),
          const SizedBox(height: Space.xs),
          Text('${formatChips(stats.hands)} hands analysed', style: Typo.body(p.secondaryLabel)),
          const SizedBox(height: Space.xl),
          pair(_ProfileCard(stats: stats, profile: profile), _StyleCard(profile: profile), fa: 3, fb: 2),
          const SizedBox(height: Space.l),
          _Tiles(stats: stats),
          if (stats.decisions > 0) ...[
            const SizedBox(height: Space.l),
            _DecisionCard(stats: stats, history: history),
          ],
          const SizedBox(height: Space.l),
          _Card(
            title: 'Results',
            subtitle: 'Running total in big blinds',
            trailing: Text(signedBb(stats.netBb),
                style: Typo.number(stats.netBb >= 0 ? p.positive : p.destructive, size: 17)),
            child: BankrollChart(values: stats.bankrollBb),
          ),
          const SizedBox(height: Space.l),
          pair(
            _Card(
              title: 'By position',
              subtitle: 'Win rate from each seat. Hover for hands played and VPIP.',
              child: PositionBars(stats: stats),
            ),
            _Card(
              title: 'Starting hands',
              subtitle: 'Total won or lost with each hand',
              child: StartingHandGrid(stats: stats),
            ),
          ),
          if (profile != null) ...[
            const SizedBox(height: Space.l),
            _InsightsCard(insights: profile!.insights),
          ],
        ],
      );
    });
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Radii.l),
        border: Border.all(color: p.separator, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: Typo.headline(p.label).copyWith(fontSize: 17)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: Typo.callout(p.secondaryLabel)),
                  ],
                ]),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: Space.l),
          child,
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.stats, required this.profile});
  final PlayerStats stats;
  final PlayerProfile? profile;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final pr = profile;
    if (pr == null) {
      final need = minHandsForProfile - stats.hands;
      return _Card(
        title: 'Your playing style',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Play $need more hand${need == 1 ? '' : 's'} to unlock your player profile.',
                style: Typo.body(p.secondaryLabel)),
            const SizedBox(height: Space.m),
            _Meter(value: stats.hands / minHandsForProfile),
          ],
        ),
      );
    }
    final a = pr.archetype;
    final confidence = stats.hands < 100 ? 'Early read' : (stats.hands < 500 ? 'Developing read' : 'Confident read');
    return _Card(
      title: 'YOUR PLAYING STYLE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(a.title, style: Typo.largeTitle(p.label).copyWith(fontSize: 38)),
          const SizedBox(height: 2),
          Text('${a.style} · $confidence', style: Typo.headline(p.accent)),
          const SizedBox(height: Space.m),
          Text(a.description, style: Typo.body(p.secondaryLabel).copyWith(height: 1.45)),
          const SizedBox(height: Space.l),
          Row(children: [
            _MiniStat('VPIP', _pct(stats.vpipPct)),
            _MiniStat('PFR', _pct(stats.pfrPct)),
            _MiniStat('AF', stats.aggressionFactor.toStringAsFixed(1)),
            _MiniStat('bb/100', stats.bbPer100.toStringAsFixed(1)),
          ]),
        ],
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({required this.profile});
  final PlayerProfile? profile;

  @override
  Widget build(BuildContext context) {
    final pr = profile;
    return _Card(
      title: 'Style map',
      subtitle: 'How loose and how aggressive you play',
      child: Center(
        child: Opacity(
          opacity: pr == null ? 0.35 : 1,
          child: StyleMap(looseness: pr?.looseness ?? 0.5, aggression: pr?.aggression ?? 0.5, size: 230),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Typo.caption(p.secondaryLabel)),
        Text(value, style: Typo.number(p.label, size: 20)),
      ]),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Stack(children: [
          Positioned.fill(child: ColoredBox(color: p.accent.withValues(alpha: 0.18))),
          FractionallySizedBox(widthFactor: value.clamp(0.0, 1.0), child: ColoredBox(color: p.accent)),
        ]),
      ),
    );
  }
}

String _pct(double v) => '${(v * 100).round()}%';

class _Tile {
  const _Tile(this.label, this.value, this.hint, {this.sample});
  final String label, value, hint;

  /// Number of opportunities behind a percentage (null = not a rate).
  final int? sample;
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.stats});
  final PlayerStats stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final tiles = [
      _Tile('Hands played', formatChips(s.hands), '${formatChips(s.handsWon)} won'),
      _Tile('Net result', signedBb(s.netBb), '${s.netChips >= 0 ? '+' : '−'}${formatChips(s.netChips.abs())} chips'),
      _Tile('Win rate', '${s.bbPer100.toStringAsFixed(1)} bb/100', 'Big blinds won per 100 hands'),
      _Tile('VPIP', _pct(s.vpipPct), 'Put money in preflop · typical 18–28%'),
      _Tile('PFR', _pct(s.pfrPct), 'Raised preflop · typical 14–22%'),
      _Tile('3-Bet', _pct(s.threeBetPct), 'Re-raised a raise · typical 5–10%', sample: s.threeBetOpp),
      _Tile('Aggression factor', s.aggressionFactor.toStringAsFixed(1), '(Bets + raises) ÷ calls · typical 2–3.5',
          sample: s.postBets + s.postRaises + s.postCalls),
      _Tile('C-Bet', _pct(s.cbetPct), 'Bet the flop after raising · typical 55–75%', sample: s.cbetOpp),
      _Tile('Fold to C-Bet', _pct(s.foldToCbetPct), 'Folded to a flop c-bet · typical 40–55%',
          sample: s.foldToCbetOpp),
      _Tile('Saw flop', _pct(s.sawFlopPct), 'Hands that reached the flop'),
      _Tile('Went to showdown', _pct(s.wtsdPct), 'After seeing the flop · typical 25–32%', sample: s.sawFlop),
      _Tile('Won at showdown', _pct(s.wsdPct), 'Typical 50–55%', sample: s.showdowns),
      _Tile('Won when saw flop', _pct(s.wwsfPct), 'Typical 44–50%', sample: s.sawFlop),
      _Tile('Biggest pot', '${s.biggestPotBb.toStringAsFixed(0)} bb', 'Largest pot you won'),
      _Tile('Best hand', s.bestHandValue == null ? '—' : categoryOf(s.bestHandValue!).label,
          s.bestHandValue == null ? 'Shown down' : describeHand(s.bestHandValue!)),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / 200).floor().clamp(2, 5);
      final w = (c.maxWidth - (cols - 1) * Space.m) / cols;
      return Wrap(
        spacing: Space.m,
        runSpacing: Space.m,
        children: [for (final t in tiles) SizedBox(width: w, child: _TileView(tile: t))],
      );
    });
  }
}

class _TileView extends StatelessWidget {
  const _TileView({required this.tile});
  final _Tile tile;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final noData = tile.sample == 0;
    return Container(
      height: 112,
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Radii.m),
        border: Border.all(color: p.separator, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tile.label, style: Typo.callout(p.secondaryLabel)),
          const SizedBox(height: 4),
          Text(noData ? '—' : tile.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Typo.number(p.label, size: 22, weight: FontWeight.w600)),
          const Spacer(),
          Text(
            tile.sample != null && tile.sample! > 0 && tile.sample! < 20
                ? '${tile.hint} · small sample (${tile.sample})'
                : tile.hint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Typo.caption(p.tertiaryLabel),
          ),
        ],
      ),
    );
  }
}

class _InsightsCard extends StatelessWidget {
  const _InsightsCard({required this.insights});
  final List<Insight> insights;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final ordered = [...insights.where((i) => !i.positive), ...insights.where((i) => i.positive)];
    return _Card(
      title: 'Coaching notes',
      subtitle: 'What your numbers say about your game',
      child: Column(
        children: [
          for (final (i, ins) in ordered.indexed) ...[
            if (i > 0) Container(height: 0.5, color: p.separator, margin: const EdgeInsets.symmetric(vertical: 12)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  ins.positive ? CupertinoIcons.checkmark_seal_fill : CupertinoIcons.lightbulb_fill,
                  size: 20,
                  color: ins.positive ? p.positive : const Color(0xFFFF9F0A),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(ins.title, style: Typo.headline(p.label)),
                    const SizedBox(height: 2),
                    Text(ins.detail, style: Typo.body(p.secondaryLabel).copyWith(height: 1.4)),
                  ]),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DecisionCard extends StatelessWidget {
  const _DecisionCard({required this.stats, required this.history});
  final PlayerStats stats;
  final HistoryStore history;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final acc = stats.accuracy!;
    final total = stats.decisions;
    final mistakes = stats.mistakeCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    // 20-hand rolling accuracy.
    final rolling = <double>[];
    final a = stats.accuracyByHand;
    for (var i = 0; i < a.length; i++) {
      final from = i < 19 ? 0 : i - 19;
      final window = a.sublist(from, i + 1);
      rolling.add(window.reduce((x, y) => x + y) / window.length);
    }
    return _Card(
      title: 'Decision quality',
      subtitle: 'How the coach graded $total decision${total == 1 ? '' : 's'}',
      trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${acc.round()}%', style: Typo.number(p.label, size: 28)),
        Text('accuracy', style: Typo.caption(p.secondaryLabel)),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grade distribution: one whole split into parts, 2px gaps.
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 10,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (i, g) in Grade.values.indexed)
                  if ((stats.gradeCounts[g] ?? 0) > 0)
                    Expanded(
                      flex: stats.gradeCounts[g]!,
                      child: Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
                        child: ColoredBox(color: gradeStyle(g, p).$1),
                      ),
                    ),
              ]),
            ),
          ),
          const SizedBox(height: Space.m),
          Wrap(spacing: Space.l, runSpacing: 6, children: [
            for (final g in Grade.values)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(gradeStyle(g, p).$2, size: 14, color: gradeStyle(g, p).$1),
                const SizedBox(width: 4),
                Text(g.label, style: Typo.callout(p.label)),
                const SizedBox(width: 4),
                Text('${stats.gradeCounts[g] ?? 0}', style: Typo.number(p.secondaryLabel, size: 12.5)),
              ]),
          ]),
          if (rolling.length >= 10) ...[
            const SizedBox(height: Space.xl),
            Text('Accuracy over time (20-hand average)', style: Typo.callout(p.secondaryLabel)),
            const SizedBox(height: Space.s),
            BankrollChart(
              values: rolling,
              height: 160,
              prependZero: false,
              showDelta: false,
              valueLabel: (v) => '${v.round()}% accuracy',
              axisLabel: (v) => '${v.round()}%',
            ),
          ],
          if (mistakes.isNotEmpty) ...[
            const SizedBox(height: Space.xl),
            Text('Recurring mistakes', style: Typo.headline(p.label)),
            const SizedBox(height: Space.s),
            for (final m in mistakes.take(3))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: m.key.label, style: Typo.body(p.label)),
                      TextSpan(text: '  ×${m.value}', style: Typo.number(p.secondaryLabel, size: 13)),
                    ])),
                  ),
                  if (drillFor(m.key) == DrillKind.preflop)
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 30),
                      onPressed: () => Navigator.of(context)
                          .push(CupertinoPageRoute<void>(builder: (_) => RangeScreen(history: history))),
                      child: Text('Range charts', style: Typo.callout(p.accent)),
                    ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 30),
                    onPressed: () => Navigator.of(context).push(CupertinoPageRoute<void>(
                        builder: (_) => TrainingScreen(history: history, startWith: drillFor(m.key)))),
                    child: Text('Practise', style: Typo.callout(p.accent).copyWith(fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
          ],
        ],
      ),
    );
  }
}
