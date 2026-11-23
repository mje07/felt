import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cupertino_ui/cupertino_ui.dart';

import '../app/settings.dart';
import '../app/theme.dart';

/// Frosted, hairline-bordered surface.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = Radii.l,
    this.padding = const EdgeInsets.all(Space.m),
    this.tint,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint ?? p.glass,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: p.separator, width: 0.5),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

enum PillStyle { filled, tinted, plain, destructive }

/// Rounded button with a gentle press-scale.
class PillButton extends StatefulWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = PillStyle.tinted,
    this.sublabel,
    this.shortcut,
    this.minWidth = 120,
    this.height = 48,
    this.expand = false,
  });

  final String label;
  final String? sublabel, shortcut;
  final VoidCallback? onPressed;
  final PillStyle style;
  final double minWidth, height;
  final bool expand;

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _down = false, _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = widget.onPressed != null;
    final (bg, fg) = switch (widget.style) {
      PillStyle.filled => (p.accent, const Color(0xFFFFFFFF)),
      PillStyle.tinted => (p.isDark ? const Color(0x33FFFFFF) : const Color(0x14000000), p.label),
      PillStyle.plain => (const Color(0x00000000), p.accent),
      PillStyle.destructive => (p.destructive.withValues(alpha: p.isDark ? 0.22 : 0.12), p.destructive),
    };
    final settings = SettingsScope.of(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.label, style: Typo.headline(fg), maxLines: 1),
        if (widget.sublabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(widget.sublabel!, style: Typo.number(fg.withValues(alpha: 0.75), size: 12, weight: FontWeight.w500)),
          ),
      ],
    );
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _down ? 0.96 : 1,
          duration: settings.scaled(Motion.fast),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.4,
            duration: Motion.fast,
            child: AnimatedContainer(
              duration: Motion.fast,
              constraints: BoxConstraints(minWidth: widget.minWidth, minHeight: widget.height),
              padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
              decoration: BoxDecoration(
                color: _hover && enabled ? Color.lerp(bg, fg, 0.08) : bg,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              alignment: widget.expand ? Alignment.center : null,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  content,
                  if (widget.shortcut != null && _hover)
                    Positioned(
                      right: -Space.s,
                      top: -2,
                      child: Text(widget.shortcut!, style: Typo.caption(fg.withValues(alpha: 0.5))),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round icon button used in toolbars.
class IconPill extends StatelessWidget {
  const IconPill({super.key, required this.icon, required this.onPressed, this.tooltip});
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      label: tooltip,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onPressed,
          child: GlassPanel(
            radius: Radii.pill,
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 18, color: p.label),
          ),
        ),
      ),
    );
  }
}

/// Initials avatar with a soft, deterministic tint.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.size = 44, this.ring});
  final String name;
  final double size;
  final Color? ring;

  static const _tints = [
    Color(0xFF5E5CE6), Color(0xFFFF9F0A), Color(0xFF30B0C7), Color(0xFFFF375F), //
    Color(0xFF64D2FF), Color(0xFFBF5AF2), Color(0xFFFFD60A), Color(0xFF32D74B),
  ];

  @override
  Widget build(BuildContext context) {
    final tint = _tints[name.codeUnits.fold(0, (a, b) => a + b) % _tints.length];
    final initials = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return AnimatedContainer(
      duration: Motion.medium,
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ring ?? const Color(0x00000000), width: 2.5),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(tint, const Color(0xFFFFFFFF), 0.25)!, tint],
          ),
        ),
        child: Center(
          child: Text(initials,
              style: TextStyle(
                  fontFamily: Typo.display,
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFFFFFFF))),
        ),
      ),
    );
  }
}

/// A single casino chip, flat and minimal.
class ChipDisc extends StatelessWidget {
  const ChipDisc({super.key, required this.amount, this.size = 18});
  final int amount;
  final double size;

  static Color colorFor(int amount) {
    if (amount >= 1000) return const Color(0xFF1C1C1E);
    if (amount >= 500) return const Color(0xFF8E44AD);
    if (amount >= 100) return const Color(0xFF1D7A46);
    if (amount >= 25) return const Color(0xFF0A60D0);
    if (amount >= 5) return const Color(0xFFD62F2F);
    return const Color(0xFFEDEDED);
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _ChipPainter(colorFor(amount)));
}

class _ChipPainter extends CustomPainter {
  _ChipPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c.translate(0, r * 0.12), r, Paint()..color = const Color(0x40000000));
    canvas.drawCircle(c, r, Paint()..color = color);
    final light = color.computeLuminance() > 0.6;
    final mark = Paint()..color = light ? const Color(0xFFB0B0B5) : const Color(0xE6FFFFFF);
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(a);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, -r * 0.8), width: r * 0.34, height: r * 0.3),
            Radius.circular(r * 0.06)),
        mark,
      );
      canvas.restore();
    }
    canvas.drawCircle(
        c,
        r * 0.56,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.08
          ..color = mark.color.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(_ChipPainter old) => old.color != color;
}

/// Chip + amount pill, used for bets and the pot.
class ChipAmount extends StatelessWidget {
  const ChipAmount({super.key, required this.amount, this.large = false});
  final int amount;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x59000000),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(4, 3, large ? 12 : 9, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChipDisc(amount: amount, size: large ? 20 : 16),
            const SizedBox(width: 6),
            AnimatedCount(
              value: amount,
              style: Typo.number(const Color(0xFFFFFFFF), size: large ? 15 : 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Number that counts smoothly to its new value.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({super.key, required this.value, required this.style, this.prefix = ''});
  final int value;
  final TextStyle style;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: settings.scaled(Motion.slow),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('$prefix${formatChips(v.round())}', style: style),
    );
  }
}
