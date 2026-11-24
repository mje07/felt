import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';

import '../app/settings.dart';
import '../app/theme.dart';
import 'playing_card.dart' show suitColor, suitPath;

/// One coloured slice of a grid cell (e.g. "bet 60%").
class GridSegment {
  const GridSegment(this.color, this.share);
  final Color color;

  /// Fraction of the cell's width, 0..1.
  final double share;
}

/// The 13×13 starting-hand grid: pairs on the diagonal, suited above,
/// offsuit below. Cells are filled left to right by [cells] (indexed by
/// [startingHandIndex]). Supports drag-painting ([onPaint]) and hover.
class RangeGrid extends StatefulWidget {
  const RangeGrid({
    super.key,
    required this.cells,
    this.onPaint,
    this.onHover,
    this.highlight = const {},
    this.maxSize = 520,
  });

  final List<List<GridSegment>> cells;

  /// Called with the cell under the pointer; [start] is true on press.
  final void Function(int cell, bool start)? onPaint;
  final ValueChanged<int?>? onHover;

  /// Cells to outline.
  final Set<int> highlight;
  final double maxSize;

  /// Grid index of the cell at [row], [col] (row 0 = aces).
  static int indexAt(int row, int col) => (12 - row) * 13 + (12 - col);

  @override
  State<RangeGrid> createState() => _RangeGridState();
}

class _RangeGridState extends State<RangeGrid> {
  int? _hover, _lastPainted;

  int? _cellAt(Offset local, double side) {
    final step = side / 13;
    final col = (local.dx / step).floor(), row = (local.dy / step).floor();
    if (col < 0 || col > 12 || row < 0 || row > 12) return null;
    return RangeGrid.indexAt(row, col);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return LayoutBuilder(builder: (context, c) {
      final side = math.min(c.maxWidth, widget.maxSize);
      void hover(int? i) {
        if (i == _hover) return;
        setState(() => _hover = i);
        widget.onHover?.call(i);
      }

      return MouseRegion(
        cursor: widget.onPaint != null ? SystemMouseCursors.click : MouseCursor.defer,
        onHover: (e) => hover(_cellAt(e.localPosition, side)),
        onExit: (_) => hover(null),
        child: Listener(
          onPointerDown: widget.onPaint == null
              ? null
              : (e) {
                  final i = _cellAt(e.localPosition, side);
                  if (i == null) return;
                  _lastPainted = i;
                  widget.onPaint!(i, true);
                },
          onPointerMove: widget.onPaint == null
              ? null
              : (e) {
                  final i = _cellAt(e.localPosition, side);
                  hover(i);
                  if (i == null || i == _lastPainted) return;
                  _lastPainted = i;
                  widget.onPaint!(i, false);
                },
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size.square(side),
              painter: _GridPainter(widget.cells, widget.highlight, _hover, p),
            ),
          ),
        ),
      );
    });
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.cells, this.highlight, this.hover, this.p);
  final List<List<GridSegment>> cells;
  final Set<int> highlight;
  final int? hover;
  final Palette p;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / 13;
    const gap = 2.0;
    final cell = step - gap;
    final empty = Paint()..color = p.isDark ? const Color(0x14FFFFFF) : const Color(0x0D000000);
    for (var row = 0; row < 13; row++) {
      for (var col = 0; col < 13; col++) {
        final i = RangeGrid.indexAt(row, col);
        final rect = Rect.fromLTWH(col * step, row * step, cell, cell);
        final rr = RRect.fromRectAndRadius(rect, const Radius.circular(4));
        canvas.drawRRect(rr, empty);
        var filled = 0.0;
        canvas.save();
        canvas.clipRRect(rr);
        var x = rect.left;
        for (final s in cells[i]) {
          if (s.share <= 0) continue;
          final w = cell * s.share.clamp(0.0, 1.0);
          canvas.drawRect(Rect.fromLTWH(x, rect.top, w, cell), Paint()..color = s.color);
          x += w;
          filled += s.share;
        }
        canvas.restore();
        if (highlight.contains(i) || hover == i) {
          canvas.drawRRect(
            rr.deflate(0.75),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = hover == i ? p.label : p.label.withValues(alpha: 0.75),
          );
        }
        final tp = TextPainter(
          text: TextSpan(
            text: startingHandName(i).replaceAll('o', ''),
            style: TextStyle(
              fontFamily: Typo.family,
              fontSize: cell * 0.3,
              fontWeight: FontWeight.w600,
              color: filled >= 0.5 ? const Color(0xFFFFFFFF) : p.tertiaryLabel,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.cells != cells || old.hover != hover || old.highlight != highlight || old.p != p;
}

/// Picks cards from a 4×13 deck layout. [selected] cards are highlighted;
/// [blocked] ones can't be picked.
class CardPicker extends StatelessWidget {
  const CardPicker({
    super.key,
    required this.selected,
    required this.onToggle,
    this.blocked = const {},
    this.tile = 30,
  });

  final List<int> selected;
  final Set<int> blocked;
  final ValueChanged<int> onToggle;
  final double tile;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fourColor = SettingsScope.of(context).fourColorDeck;
    Color suitColorOf(int s) => suitColor(p, s, fourColor);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final suit in const [3, 2, 1, 0])
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var rank = 12; rank >= 0; rank--)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: () {
                  final card = makeCard(rank, suit);
                  final on = selected.contains(card);
                  final off = blocked.contains(card) && !on;
                  return Semantics(
                    button: true,
                    selected: on,
                    label: cardToString(card),
                    child: GestureDetector(
                      key: ValueKey('pick-${cardToString(card)}'),
                      onTap: off ? null : () => onToggle(card),
                      child: MouseRegion(
                        cursor: off ? SystemMouseCursors.basic : SystemMouseCursors.click,
                        child: AnimatedContainer(
                          duration: Motion.fast,
                          width: tile,
                          height: tile * 1.3,
                          decoration: BoxDecoration(
                            color: on ? p.accent : p.cardFace,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: on ? p.accent : p.separator),
                          ),
                          child: Opacity(
                            opacity: off ? 0.25 : 1,
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text(rankChars[rank],
                                  style: TextStyle(
                                      fontFamily: Typo.family,
                                      fontSize: tile * 0.42,
                                      height: 1,
                                      fontWeight: FontWeight.w700,
                                      color: on ? const Color(0xFFFFFFFF) : suitColorOf(suit))),
                              const SizedBox(height: 2),
                              CustomPaint(
                                size: Size.square(tile * 0.32),
                                painter: SuitPainter(suit, on ? const Color(0xFFFFFFFF) : suitColorOf(suit)),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  );
                }(),
              ),
          ]),
        ),
    ]);
  }
}

/// Draws a suit symbol from the app's vector shapes (fonts may lack them).
class SuitPainter extends CustomPainter {
  const SuitPainter(this.suit, this.color);
  final int suit;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(suitPath(suit, size.width), Paint()..color = color);

  @override
  bool shouldRepaint(SuitPainter old) => old.suit != suit || old.color != color;
}
