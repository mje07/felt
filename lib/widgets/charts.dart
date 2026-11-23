import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';

import '../app/theme.dart';

/// Chart colours. Profit/loss is a polarity, so it uses a diverging pair
/// (blue = won, red = lost) around a neutral grey; never green/red, which
/// colour-blind players can't separate.
class ChartColors {
  const ChartColors._(this.positive, this.negative, this.neutral, this.grid, this.surface);
  final Color positive, negative, neutral, grid, surface;

  static ChartColors of(BuildContext context) {
    final p = Palette.of(context);
    return p.isDark
        ? ChartColors._(const Color(0xFF3987E5), const Color(0xFFE66767), const Color(0xFF383835),
            const Color(0x1FFFFFFF), p.surface)
        : ChartColors._(const Color(0xFF2A78D6), const Color(0xFFE34948), const Color(0xFFF0EFEC),
            const Color(0x14000000), p.surface);
  }

  /// Diverging fill for a value in -1..1.
  Color diverging(double t) {
    final c = t >= 0 ? positive : negative;
    return Color.lerp(neutral, c, math.sqrt(t.abs().clamp(0.0, 1.0)))!;
  }
}

String signedBb(double v, {int digits = 1}) =>
    '${v > 0 ? '+' : (v < 0 ? '−' : '')}${v.abs().toStringAsFixed(digits)} bb';

/// Small floating label used by every chart's hover layer.
class ChartTooltip extends StatelessWidget {
  const ChartTooltip({super.key, required this.title, required this.lines});
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: p.surfaceRaised,
          borderRadius: BorderRadius.circular(Radii.s),
          border: Border.all(color: p.separator, width: 0.5),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Typo.callout(p.label).copyWith(fontWeight: FontWeight.w600)),
            for (final l in lines) Text(l, style: Typo.number(p.secondaryLabel, size: 12, weight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

/// Places [tooltip] near [anchor] inside a box of [size], flipping to stay visible.
Widget positionedTooltip(Offset anchor, Size size, Widget tooltip, {double width = 170}) {
  final double left = anchor.dx + 14 + width > size.width ? anchor.dx - 14 - width : anchor.dx + 14;
  final double top = (anchor.dy - 30).clamp(0.0, math.max(0.0, size.height - 64)).toDouble();
  return Positioned(left: left, top: top, width: width, child: Align(alignment: Alignment.topLeft, child: tooltip));
}

// ---------------------------------------------------------------- bankroll

/// Cumulative result in big blinds, hand by hand.
class BankrollChart extends StatefulWidget {
  const BankrollChart({
    super.key,
    required this.values,
    this.height = 220,
    this.prependZero = true,
    this.valueLabel = signedBb,
    this.axisLabel,
    this.showDelta = true,
  });
  final List<double> values;

  /// Start the line at 0 (cumulative series).
  final bool prependZero;
  final String Function(double) valueLabel;
  final String Function(double)? axisLabel;
  final bool showDelta;
  final double height;

  @override
  State<BankrollChart> createState() => _BankrollChartState();
}

class _BankrollChartState extends State<BankrollChart> {
  int? _hover;
  static const _left = 52.0, _bottom = 22.0, _top = 8.0;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final cc = ChartColors.of(context);
    final v = widget.prependZero ? [0.0, ...widget.values] : widget.values;
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(builder: (context, c) {
        final size = Size(c.maxWidth, widget.height);
        final plotW = size.width - _left - 8;
        double xOf(int i) => _left + (v.length <= 1 ? 0 : i / (v.length - 1) * plotW);
        final scale = _Scale.nice(v.reduce(math.min), v.reduce(math.max));
        double yOf(double val) =>
            _top + (1 - (val - scale.min) / (scale.max - scale.min)) * (size.height - _top - _bottom);
        final h = _hover;
        return MouseRegion(
          onHover: (e) {
            final i = (((e.localPosition.dx - _left) / plotW) * (v.length - 1)).round().clamp(0, v.length - 1);
            if (i != _hover) setState(() => _hover = i);
          },
          onExit: (_) => setState(() => _hover = null),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                size: size,
                painter: _BankrollPainter(
                  values: v,
                  scale: scale,
                  xOf: xOf,
                  yOf: yOf,
                  line: p.accent,
                  grid: cc.grid,
                  zero: p.tertiaryLabel,
                  label: p.secondaryLabel,
                  surface: cc.surface,
                  hover: h,
                  axisLabel: widget.axisLabel,
                ),
              ),
              if (h != null)
                positionedTooltip(
                  Offset(xOf(h), yOf(v[h])),
                  size,
                  ChartTooltip(
                    title: widget.prependZero ? (h == 0 ? 'Start' : 'After hand ${formatChips(h)}') : 'Hand ${formatChips(h + 1)}',
                    lines: [
                      widget.valueLabel(v[h]),
                      if (widget.showDelta && h > 0) 'This hand ${widget.valueLabel(v[h] - v[h - 1])}',
                    ],
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

class _Scale {
  _Scale(this.min, this.max, this.step);
  final double min, max, step;

  /// Rounded axis bounds that always include zero.
  factory _Scale.nice(double lo, double hi) {
    lo = math.min(lo, 0);
    hi = math.max(hi, 0);
    if (hi - lo < 1e-9) hi = lo + 10;
    final raw = (hi - lo) / 4;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final step = [1.0, 2.0, 2.5, 5.0, 10.0].map((m) => m * mag).firstWhere((s) => s >= raw);
    return _Scale((lo / step).floor() * step, (hi / step).ceil() * step, step);
  }
}

class _BankrollPainter extends CustomPainter {
  _BankrollPainter({
    required this.values,
    required this.scale,
    required this.xOf,
    required this.yOf,
    required this.line,
    required this.grid,
    required this.zero,
    required this.label,
    required this.surface,
    required this.hover,
    this.axisLabel,
  });

  final List<double> values;
  final _Scale scale;
  final double Function(int) xOf;
  final double Function(double) yOf;
  final Color line, grid, zero, label, surface;
  final int? hover;
  final String Function(double)? axisLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final zeroPaint = Paint()
      ..color = zero
      ..strokeWidth = 1;
    final style = Typo.number(label, size: 11, weight: FontWeight.w500);
    for (var g = scale.min; g <= scale.max + 1e-9; g += scale.step) {
      final y = yOf(g);
      canvas.drawLine(Offset(52, y), Offset(size.width - 8, y), g.abs() < 1e-9 ? zeroPaint : gridPaint);
      final tp = TextPainter(
          text: TextSpan(text: axisLabel?.call(g) ?? '${g > 0 ? '+' : ''}${g.round()}', style: style),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(44 - tp.width, y - tp.height / 2));
    }
    final first = TextPainter(text: TextSpan(text: 'Hand 1', style: style), textDirection: TextDirection.ltr)
      ..layout();
    first.paint(canvas, Offset(52, size.height - 16));
    final last = TextPainter(
        text: TextSpan(text: formatChips(values.length - 1), style: style), textDirection: TextDirection.ltr)
      ..layout();
    last.paint(canvas, Offset(size.width - 8 - last.width, size.height - 16));

    if (values.length < 2) return;
    // Downsample to at most ~2 points per pixel.
    final stride = math.max(1, values.length ~/ (size.width * 2));
    final path = Path()..moveTo(xOf(0), yOf(values[0]));
    for (var i = stride; i < values.length; i += stride) {
      path.lineTo(xOf(i), yOf(values[i]));
    }
    path.lineTo(xOf(values.length - 1), yOf(values.last));
    final area = Path.from(path)
      ..lineTo(xOf(values.length - 1), yOf(0))
      ..lineTo(xOf(0), yOf(0))
      ..close();
    canvas.drawPath(area, Paint()..color = line.withValues(alpha: 0.08));
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);

    final h = hover;
    if (h != null) {
      final x = xOf(h), y = yOf(values[h]);
      canvas.drawLine(Offset(x, 8), Offset(x, size.height - 22), zeroPaint);
      canvas.drawCircle(Offset(x, y), 6, Paint()..color = surface);
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(_BankrollPainter old) =>
      old.values != values || old.hover != hover || old.line != line || old.surface != surface;
}

// ---------------------------------------------------------------- positions

/// Win rate by seat as diverging horizontal bars around zero.
class PositionBars extends StatefulWidget {
  const PositionBars({super.key, required this.stats});
  final PlayerStats stats;

  @override
  State<PositionBars> createState() => _PositionBarsState();
}

class _PositionBarsState extends State<PositionBars> {
  String? _hover;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final cc = ChartColors.of(context);
    final rows = [
      for (final pos in positionOrder)
        if (widget.stats.byPosition[pos]!.hands > 0) (pos, widget.stats.byPosition[pos]!)
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    final maxAbs = rows.map((r) => r.$2.bbPer100.abs()).fold(1.0, math.max);
    return Column(
      children: [
        for (final (pos, ps) in rows)
          MouseRegion(
            onEnter: (_) => setState(() => _hover = pos),
            onExit: (_) => setState(() => _hover = null),
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: _hover == pos ? cc.grid : const Color(0x00000000),
                borderRadius: BorderRadius.circular(Radii.s),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  SizedBox(
                      width: 40, child: Text(pos, style: Typo.callout(p.label).copyWith(fontWeight: FontWeight.w600))),
                  Expanded(
                    child: LayoutBuilder(builder: (context, c) {
                      final half = c.maxWidth / 2;
                      final w = math.max(2.0, ps.bbPer100.abs() / maxAbs * (half - 2));
                      final positive = ps.bbPer100 >= 0;
                      return Stack(
                        children: [
                          Positioned(left: half, top: 6, bottom: 6, width: 1, child: ColoredBox(color: p.tertiaryLabel)),
                          Positioned(
                            left: positive ? half + 1 : half - 1 - w,
                            width: w,
                            top: 10,
                            bottom: 10,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: positive ? cc.positive : cc.negative,
                                borderRadius: BorderRadius.horizontal(
                                  left: positive ? Radius.zero : const Radius.circular(4),
                                  right: positive ? const Radius.circular(4) : Radius.zero,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                  SizedBox(
                    width: 104,
                    child: Text(
                      _hover == pos
                          ? '${ps.hands} hands · ${(ps.vpipPct * 100).round()}%'
                          : '${ps.bbPer100 >= 0 ? '+' : '−'}${ps.bbPer100.abs().toStringAsFixed(1)}',
                      textAlign: TextAlign.right,
                      style: Typo.number(_hover == pos ? p.secondaryLabel : p.label, size: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            const SizedBox(width: 46),
            Expanded(
              child: Row(children: [
                Text('Losing', style: Typo.caption(p.secondaryLabel)),
                const Spacer(),
                Text('bb / 100 hands', style: Typo.caption(p.tertiaryLabel)),
                const Spacer(),
                Text('Winning', style: Typo.caption(p.secondaryLabel)),
              ]),
            ),
            const SizedBox(width: 110),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- hand grid

/// 13x13 starting-hand grid coloured by total result.
class StartingHandGrid extends StatefulWidget {
  const StartingHandGrid({super.key, required this.stats});
  final PlayerStats stats;

  @override
  State<StartingHandGrid> createState() => _StartingHandGridState();
}

class _StartingHandGridState extends State<StartingHandGrid> {
  int? _hover;
  Offset _at = Offset.zero;

  /// Grid row/col -> index. Rows/cols run A..2, suited above the diagonal.
  static int _index(int row, int col) {
    final r = 12 - row, c = 12 - col;
    // Above the diagonal r > c (suited: hi*13+lo); below r < c (offsuit: lo*13+hi).
    return r * 13 + c;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final cc = ChartColors.of(context);
    final s = widget.stats;
    final maxAbs = s.handNetBb.map((v) => v.abs()).fold(1.0, math.max);
    return LayoutBuilder(builder: (context, c) {
      final side = math.min(c.maxWidth, 440.0);
      final cell = (side - 12 * 2) / 13;
      final size = Size(side, side);
      final h = _hover;
      return Center(
        child: SizedBox(
          width: side,
          child: Column(
            children: [
              SizedBox.fromSize(
                size: size,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var row = 0; row < 13; row++)
                      for (var col = 0; col < 13; col++)
                        Positioned(
                          left: col * (cell + 2),
                          top: row * (cell + 2),
                          width: cell,
                          height: cell,
                          child: _cell(_index(row, col), cell, maxAbs, p, cc,
                              Offset(col * (cell + 2) + cell / 2, row * (cell + 2) + cell / 2)),
                        ),
                    if (h != null)
                      positionedTooltip(
                        _at,
                        size,
                        ChartTooltip(
                          title: startingHandName(h),
                          lines: s.handCount[h] == 0
                              ? ['Not dealt yet']
                              : [
                                  '${s.handCount[h]} hand${s.handCount[h] == 1 ? '' : 's'}',
                                  'Total ${signedBb(s.handNetBb[h])}',
                                  'Per hand ${signedBb(s.handNetBb[h] / s.handCount[h])}',
                                ],
                        ),
                        width: 150,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(signedBb(-maxAbs, digits: 0), style: Typo.caption(p.secondaryLabel)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(colors: [
                          for (var t = -1.0; t <= 1.0001; t += 0.25) cc.diverging(t),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(signedBb(maxAbs, digits: 0), style: Typo.caption(p.secondaryLabel)),
                ],
              ),
              const SizedBox(height: 4),
              Text('Suited hands above the diagonal, offsuit below', style: Typo.caption(p.tertiaryLabel)),
            ],
          ),
        ),
      );
    });
  }

  Widget _cell(int i, double cell, double maxAbs, Palette p, ChartColors cc, Offset anchor) {
    final s = widget.stats;
    final played = s.handCount[i] > 0;
    final t = played ? s.handNetBb[i] / maxAbs : 0.0;
    final fill = played ? cc.diverging(t) : const Color(0x00000000);
    final darkFill = played && fill.computeLuminance() < 0.3;
    return MouseRegion(
      onEnter: (_) => setState(() {
        _hover = i;
        _at = anchor;
      }),
      onExit: (_) => setState(() => _hover = null),
      child: Container(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _hover == i ? p.label : (played ? const Color(0x00000000) : cc.grid),
            width: _hover == i ? 1.5 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: cell >= 22
            ? Text(
                startingHandName(i).replaceAll('o', ''),
                style: TextStyle(
                  fontFamily: Typo.family,
                  fontSize: cell * 0.32,
                  fontWeight: FontWeight.w600,
                  color: played ? (darkFill ? const Color(0xFFFFFFFF) : p.label) : p.tertiaryLabel,
                ),
              )
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------- style map

/// Tight/loose vs passive/aggressive quadrant with the player's position.
class StyleMap extends StatelessWidget {
  const StyleMap({super.key, required this.looseness, required this.aggression, this.size = 260});
  final double looseness, aggression, size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final cc = ChartColors.of(context);
    Widget corner(String text, Alignment a) => Align(
          alignment: a,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Text(text, style: Typo.caption(p.secondaryLabel).copyWith(fontWeight: FontWeight.w600)),
          ),
        );
    final x = 0.04 + looseness.clamp(0.0, 1.0) * 0.92;
    final y = 0.04 + (1 - aggression.clamp(0.0, 1.0)) * 0.92;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotatedBox(
              quarterTurns: 3,
              child: SizedBox(
                width: size,
                child: Row(children: [
                  Text('Passive', style: Typo.caption(p.tertiaryLabel)),
                  const Spacer(),
                  Text('Aggressive', style: Typo.caption(p.tertiaryLabel)),
                ]),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox.square(
              dimension: size,
              child: Container(
                decoration: BoxDecoration(
                  color: p.isDark ? const Color(0x0DFFFFFF) : const Color(0x08000000),
                  borderRadius: BorderRadius.circular(Radii.m),
                  border: Border.all(color: cc.grid),
                ),
                child: Stack(
                  children: [
                    Center(child: Container(width: 1, color: cc.grid)),
                    Center(child: Container(height: 1, color: cc.grid)),
                    corner('SHARK', Alignment.topLeft),
                    corner('MAVERICK', Alignment.topRight),
                    corner('ROCK', Alignment.bottomLeft),
                    corner('STATION', Alignment.bottomRight),
                    Positioned(
                      left: x * size - 9,
                      top: y * size - 9,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Motion.slow,
                        curve: Motion.snappy,
                        builder: (context, t, child) => Transform.scale(scale: t, child: child),
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: p.accent,
                            border: Border.all(color: cc.surface, width: 3),
                            boxShadow: [BoxShadow(color: p.accent.withValues(alpha: 0.4), blurRadius: 10)],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: (x * size + 12).clamp(0, size - 40),
                      top: (y * size - 8).clamp(0, size - 20),
                      child: Text('You', style: Typo.caption(p.label).copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 22),
          child: SizedBox(
            width: size,
            child: Row(children: [
              Text('Tight', style: Typo.caption(p.tertiaryLabel)),
              const Spacer(),
              Text('Loose', style: Typo.caption(p.tertiaryLabel)),
            ]),
          ),
        ),
      ],
    );
  }
}
