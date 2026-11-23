import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';

import '../app/settings.dart';
import '../app/theme.dart';

/// Card proportions: poker size 63.5 x 88.9 mm.
const cardAspect = 63.5 / 88.9;

/// A playing card that flips when [faceUp] changes and can be dimmed/lifted
/// for showdown highlighting.
class PlayingCard extends StatelessWidget {
  const PlayingCard({
    super.key,
    required this.card,
    required this.width,
    this.faceUp = true,
    this.dimmed = false,
    this.lifted = false,
  });

  final int? card;
  final double width;
  final bool faceUp, dimmed, lifted;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final height = width / cardAspect;
    return AnimatedSlide(
      offset: Offset(0, lifted ? -0.12 : 0),
      duration: settings.scaled(Motion.medium),
      curve: Motion.snappy,
      child: AnimatedOpacity(
        opacity: dimmed ? 0.38 : 1,
        duration: settings.scaled(Motion.medium),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: faceUp && card != null ? 1 : 0),
          duration: settings.scaled(Motion.slow),
          curve: Curves.easeInOutCubic,
          builder: (context, t, _) {
            final showFace = t >= 0.5;
            final angle = (1 - t) * math.pi;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY(showFace ? angle : angle - math.pi),
              child: SizedBox(
                width: width,
                height: height,
                child: showFace && card != null
                    ? _CardFace(card: card!, fourColor: settings.fourColorDeck)
                    : const _CardBack(),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Fades/scales a card in from a direction the first time it is built.
class DealIn extends StatelessWidget {
  const DealIn({super.key, required this.child, this.from = const Offset(0, -0.6)});
  final Widget child;
  final Offset from;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: settings.scaled(Motion.medium),
      curve: Motion.spring,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: FractionalTranslation(
          translation: Offset(from.dx * (1 - t), from.dy * (1 - t)),
          child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
        ),
      ),
      child: child,
    );
  }
}

Color suitColor(Palette p, int suit, bool fourColor) => switch (suit) {
      0 => fourColor ? p.cardGreen : p.cardInk, // clubs
      1 => fourColor ? p.cardBlue : p.cardRed, // diamonds
      2 => p.cardRed, // hearts
      _ => p.cardInk, // spades
    };

class _CardFace extends StatelessWidget {
  const _CardFace({required this.card, required this.fourColor});
  final int card;
  final bool fourColor;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final suit = cardSuit(card);
    final color = suitColor(p, suit, fourColor);
    final rank = rankChars[cardRank(card)] == 'T' ? '10' : rankChars[cardRank(card)];
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: p.cardFace,
          borderRadius: BorderRadius.circular(w * 0.11),
          border: Border.all(color: const Color(0x14000000), width: 0.5),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
            BoxShadow(color: Color(0x1A000000), blurRadius: 1, offset: Offset(0, 0.5)),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(w * 0.09),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      rank,
                      style: TextStyle(
                        fontFamily: Typo.display,
                        fontSize: w * 0.34,
                        height: 1.0,
                        fontWeight: FontWeight.w600,
                        letterSpacing: rank.length > 1 ? -w * 0.03 : 0,
                        color: color,
                      ),
                    ),
                    SizedBox(height: w * 0.03),
                    SuitIcon(suit: suit, size: w * 0.2, color: color),
                  ],
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: SuitIcon(suit: suit, size: w * 0.46, color: color),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(w * 0.11),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [p.cardBackA, p.cardBackB],
          ),
          border: Border.all(color: const Color(0x33FFFFFF), width: 0.75),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: CustomPaint(painter: _BackPattern(w)),
      );
    });
  }
}

class _BackPattern extends CustomPainter {
  _BackPattern(this.w);
  final double w;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.6, w * 0.012)
      ..color = const Color(0x24FFFFFF);
    for (var i = 1; i <= 3; i++) {
      final inset = w * 0.09 * i;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2),
        Radius.circular(w * 0.08),
      );
      canvas.drawRRect(r, paint);
    }
    // Small spade mark in the centre.
    final s = w * 0.22;
    canvas.save();
    canvas.translate(size.width / 2 - s / 2, size.height / 2 - s / 2);
    canvas.drawPath(suitPath(3, s), Paint()..color = const Color(0x38FFFFFF));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BackPattern old) => old.w != w;
}

/// Vector suit glyph (so we don't rely on font coverage).
class SuitIcon extends StatelessWidget {
  const SuitIcon({super.key, required this.suit, required this.size, required this.color});
  final int suit;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _SuitPainter(suit, color),
      );
}

class _SuitPainter extends CustomPainter {
  _SuitPainter(this.suit, this.color);
  final int suit;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(suitPath(suit, size.width), Paint()..color = color..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_SuitPainter old) => old.suit != suit || old.color != color;
}

Path _heart(double s) => Path()
  ..moveTo(0.5 * s, 0.94 * s)
  ..cubicTo(0.16 * s, 0.68 * s, 0.0, 0.5 * s, 0.0, 0.3 * s)
  ..cubicTo(0.0, 0.13 * s, 0.13 * s, 0.03 * s, 0.27 * s, 0.03 * s)
  ..cubicTo(0.38 * s, 0.03 * s, 0.46 * s, 0.1 * s, 0.5 * s, 0.19 * s)
  ..cubicTo(0.54 * s, 0.1 * s, 0.62 * s, 0.03 * s, 0.73 * s, 0.03 * s)
  ..cubicTo(0.87 * s, 0.03 * s, 1.0 * s, 0.13 * s, 1.0 * s, 0.3 * s)
  ..cubicTo(1.0 * s, 0.5 * s, 0.84 * s, 0.68 * s, 0.5 * s, 0.94 * s)
  ..close();

/// Suit outline in an s x s box. 0 clubs, 1 diamonds, 2 hearts, 3 spades.
Path suitPath(int suit, double s) {
  switch (suit) {
    case 0:
      final p = Path()
        ..addOval(Rect.fromCircle(center: Offset(0.5 * s, 0.27 * s), radius: 0.21 * s))
        ..addOval(Rect.fromCircle(center: Offset(0.26 * s, 0.56 * s), radius: 0.21 * s))
        ..addOval(Rect.fromCircle(center: Offset(0.74 * s, 0.56 * s), radius: 0.21 * s))
        ..addOval(Rect.fromCircle(center: Offset(0.5 * s, 0.5 * s), radius: 0.14 * s));
      final stem = Path()
        ..moveTo(0.5 * s, 0.5 * s)
        ..quadraticBezierTo(0.52 * s, 0.82 * s, 0.66 * s, 0.98 * s)
        ..lineTo(0.34 * s, 0.98 * s)
        ..quadraticBezierTo(0.48 * s, 0.82 * s, 0.5 * s, 0.5 * s)
        ..close();
      return Path.combine(PathOperation.union, p, stem);
    case 1:
      return Path()
        ..moveTo(0.5 * s, 0.02 * s)
        ..quadraticBezierTo(0.68 * s, 0.3 * s, 0.9 * s, 0.5 * s)
        ..quadraticBezierTo(0.68 * s, 0.7 * s, 0.5 * s, 0.98 * s)
        ..quadraticBezierTo(0.32 * s, 0.7 * s, 0.1 * s, 0.5 * s)
        ..quadraticBezierTo(0.32 * s, 0.3 * s, 0.5 * s, 0.02 * s)
        ..close();
    case 2:
      return _heart(s);
    default:
      // Upside-down heart plus a flared stem.
      final m = Matrix4.identity()
        ..translateByDouble(0, 0.8 * s, 0, 1)
        ..scaleByDouble(1, -0.82, 1, 1);
      final body = _heart(s).transform(m.storage);
      final stem = Path()
        ..moveTo(0.5 * s, 0.5 * s)
        ..quadraticBezierTo(0.52 * s, 0.82 * s, 0.68 * s, 0.98 * s)
        ..lineTo(0.32 * s, 0.98 * s)
        ..quadraticBezierTo(0.48 * s, 0.82 * s, 0.5 * s, 0.5 * s)
        ..close();
      return Path.combine(PathOperation.union, body, stem);
  }
}
