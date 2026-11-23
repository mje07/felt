// Renders the app icon to PNGs at every size Windows uses.
// Run: flutter test tool/icon/render_icon_test.dart
// Then: dart tool/icon/make_ico.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:felt/app/theme.dart';
import 'package:felt/widgets/playing_card.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const sizes = [16, 24, 32, 48, 64, 128, 256];

class _IconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rect = Offset.zero & size;
    // Small sizes get less padding so the shape stays legible.
    final inset = s <= 24 ? 0.0 : s * 0.04;
    final body = RRect.fromRectAndRadius(rect.deflate(inset), Radius.circular(s * 0.22));
    canvas.drawRRect(
      body,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(s * 0.5, s * 0.38),
          s * 0.75,
          [Palette.light.feltCenter, Palette.light.feltEdge],
        ),
    );
    // Thin inner highlight, like the table rail.
    if (s >= 48) {
      canvas.drawRRect(
        body.deflate(s * 0.012),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.012
          ..color = const Color(0x33FFFFFF),
      );
    }
    final glyph = s * (s <= 24 ? 0.66 : 0.54);
    canvas.save();
    canvas.translate((s - glyph) / 2, (s - glyph) / 2 + s * 0.01);
    canvas.drawPath(suitPath(3, glyph), Paint()..color = const Color(0xFFFFFFFF));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) => false;
}

void main() {
  for (final size in sizes) {
    testWidgets('icon $size', (tester) async {
      tester.view.physicalSize = Size(size.toDouble(), size.toDouble());
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('icon'),
        child: CustomPaint(size: Size.square(size.toDouble()), painter: _IconPainter()),
      ));
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('icon')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('build/icon/icon_$size.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });
  }
}
