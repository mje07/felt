import 'dart:ui' show ImageFilter;

import 'package:cupertino_ui/cupertino_ui.dart';

import '../app/theme.dart';

/// Presents [child] as a centred floating sheet over a blurred backdrop.
Future<T?> showPanel<T>(BuildContext context, {required String title, required WidgetBuilder builder, double width = 460}) {
  return Navigator.of(context).push<T>(PageRouteBuilder<T>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: const Color(0x33000000),
    transitionDuration: Motion.medium,
    reverseTransitionDuration: Motion.fast,
    pageBuilder: (context, _, _) => _Panel(title: title, width: width, builder: builder),
    transitionsBuilder: (context, a, _, child) {
      final curved = CurvedAnimation(parent: a, curve: Motion.spring, reverseCurve: Curves.easeIn);
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8 * a.value, sigmaY: 8 * a.value),
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(curved), child: child),
        ),
      );
    },
  ));
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.width, required this.builder});
  final String title;
  final double width;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final h = MediaQuery.sizeOf(context).height;
    return Center(
      child: Container(
        width: width,
        constraints: BoxConstraints(maxHeight: h * 0.86),
        decoration: BoxDecoration(
          color: p.isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(Radii.xl),
          border: Border.all(color: p.separator, width: 0.5),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 50, offset: Offset(0, 24))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.m, Space.xs),
              child: Row(
                children: [
                  Expanded(child: Text(title, style: Typo.title(p.label))),
                  CupertinoButton(
                    padding: const EdgeInsets.all(6),
                    minimumSize: const Size(32, 32),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Icon(CupertinoIcons.xmark_circle_fill, color: p.tertiaryLabel, size: 26),
                  ),
                ],
              ),
            ),
            Flexible(child: builder(context)),
          ],
        ),
      ),
    );
  }
}
