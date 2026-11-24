import 'package:cupertino_ui/cupertino_ui.dart';

/// Design tokens. Quiet neutrals, one accent, felt as the only large colour.
@immutable
class Palette {
  const Palette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.glass,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.separator,
    required this.accent,
    required this.destructive,
    required this.positive,
    required this.feltCenter,
    required this.feltEdge,
    required this.rail,
    required this.cardFace,
    required this.cardInk,
    required this.cardRed,
    required this.cardBlue,
    required this.cardGreen,
    required this.cardBackA,
    required this.cardBackB,
  });

  final Brightness brightness;
  final Color background, surface, surfaceRaised, glass;
  final Color label, secondaryLabel, tertiaryLabel, separator;
  final Color accent, destructive, positive;
  final Color feltCenter, feltEdge, rail;
  final Color cardFace, cardInk, cardRed, cardBlue, cardGreen, cardBackA, cardBackB;

  bool get isDark => brightness == Brightness.dark;

  static const light = Palette(
    brightness: Brightness.light,
    background: Color(0xFFF5F5F7),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    glass: Color(0xE0FFFFFF),
    label: Color(0xFF1D1D1F),
    secondaryLabel: Color(0xFF6E6E73),
    tertiaryLabel: Color(0xFFAEAEB2),
    separator: Color(0x1F000000),
    accent: Color(0xFF007AFF),
    destructive: Color(0xFFFF3B30),
    positive: Color(0xFF34C759),
    feltCenter: Color(0xFF2F7356),
    feltEdge: Color(0xFF1B4A37),
    rail: Color(0xFFE5E5EA),
    cardFace: Color(0xFFFFFFFF),
    cardInk: Color(0xFF1D1D1F),
    cardRed: Color(0xFFE0262F),
    cardBlue: Color(0xFF1366E8),
    cardGreen: Color(0xFF1E8C4E),
    cardBackA: Color(0xFF3A3A3C),
    cardBackB: Color(0xFF1C1C1E),
  );

  static const dark = Palette(
    brightness: Brightness.dark,
    background: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    surfaceRaised: Color(0xFF2C2C2E),
    glass: Color(0x9E1C1C1E),
    label: Color(0xFFF5F5F7),
    secondaryLabel: Color(0xFF98989D),
    tertiaryLabel: Color(0xFF5A5A5E),
    separator: Color(0x29FFFFFF),
    accent: Color(0xFF0A84FF),
    destructive: Color(0xFFFF453A),
    positive: Color(0xFF30D158),
    feltCenter: Color(0xFF1F5440),
    feltEdge: Color(0xFF0F2C21),
    rail: Color(0xFF2C2C2E),
    cardFace: Color(0xFFF7F7F9),
    cardInk: Color(0xFF1D1D1F),
    cardRed: Color(0xFFE0262F),
    cardBlue: Color(0xFF1366E8),
    cardGreen: Color(0xFF1E8C4E),
    cardBackA: Color(0xFF48484A),
    cardBackB: Color(0xFF242426),
  );

  static Palette of(BuildContext context) =>
      CupertinoTheme.brightnessOf(context) == Brightness.dark ? dark : light;
}

/// Spacing / radius scale (8pt grid).
abstract final class Space {
  static const xs = 4.0, s = 8.0, m = 12.0, l = 16.0, xl = 24.0, xxl = 32.0;
}

abstract final class Radii {
  static const s = 8.0, m = 12.0, l = 18.0, xl = 28.0, pill = 999.0;
}

/// Type scale. Tabular figures keep chip counts from jittering.
abstract final class Typo {
  static const family = 'Inter';
  static const display = 'InterDisplay';
  static const _tab = [FontFeature.tabularFigures()];

  static TextStyle largeTitle(Color c) => TextStyle(
      fontFamily: display, fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: c);
  static TextStyle title(Color c) => TextStyle(
      fontFamily: display, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: c);
  static TextStyle headline(Color c) => TextStyle(
      fontFamily: family, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: c);
  static TextStyle body(Color c) => TextStyle(
      fontFamily: family, fontSize: 15, fontWeight: FontWeight.w400, letterSpacing: -0.2, color: c);
  static TextStyle callout(Color c) => TextStyle(
      fontFamily: family, fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: -0.1, color: c);
  static TextStyle caption(Color c) => TextStyle(
      fontFamily: family, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.1, color: c);
  static TextStyle number(Color c, {double size = 13, FontWeight weight = FontWeight.w600}) =>
      TextStyle(
          fontFamily: family,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: -0.1,
          color: c,
          fontFeatures: _tab);
}

/// Standard motion curves/durations (scaled by the user's speed setting).
abstract final class Motion {
  static const spring = Cubic(0.2, 0.9, 0.25, 1.0); // gentle overshoot-free spring
  static const snappy = Cubic(0.3, 1.25, 0.4, 1.0); // slight overshoot
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 520);
}

String formatChips(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return n < 0 ? '−$b' : b.toString();
}

/// Short chip amounts for tight spaces: 2,500 → 2.5K, 1,000,000 → 1M.
String formatChipsShort(int n) {
  String trim(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  final a = n.abs();
  final s = a >= 1000000 ? '${trim(a / 1000000)}M' : (a >= 1000 ? '${trim(a / 1000)}K' : '$a');
  return n < 0 ? '−$s' : s;
}
