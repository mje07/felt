import 'dart:ui' show ImageFilter;

import 'package:cupertino_ui/cupertino_ui.dart';

import '../app/theme.dart';
import '../widgets/common.dart';

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
          color: p.surface,
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
                  Semantics(
                    label: 'Close',
                    button: true,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: p.isDark ? const Color(0x1FFFFFFF) : const Color(0x0F000000),
                          ),
                          child: Icon(CupertinoIcons.xmark, size: 14, color: p.secondaryLabel),
                        ),
                      ),
                    ),
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

/// Asks the user to confirm a destructive action. Resolves to true only if
/// they press [action].
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final result = await Navigator.of(context).push<bool>(PageRouteBuilder<bool>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: const Color(0x40000000),
    transitionDuration: Motion.fast,
    reverseTransitionDuration: Motion.fast,
    pageBuilder: (context, _, _) {
      final p = Palette.of(context);
      return Center(
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(Space.xl),
          decoration: BoxDecoration(
            color: p.isDark ? p.surfaceRaised : p.surface,
            borderRadius: BorderRadius.circular(Radii.xl),
            border: Border.all(color: p.separator, width: 0.5),
            boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 40, offset: Offset(0, 18))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.destructive.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Radii.m),
                ),
                child: Icon(CupertinoIcons.trash, color: p.destructive, size: 20),
              ),
              const SizedBox(height: Space.m),
              Text(title, style: Typo.title(p.label).copyWith(fontSize: 19)),
              const SizedBox(height: Space.s),
              Text(message, style: Typo.body(p.secondaryLabel).copyWith(height: 1.4)),
              const SizedBox(height: Space.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PillButton(
                    label: 'Cancel',
                    minWidth: 100,
                    height: 40,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: Space.s),
                  PillButton(
                    label: action,
                    style: PillStyle.destructive,
                    minWidth: 100,
                    height: 40,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
    transitionsBuilder: (context, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: child),
    ),
  ));
  return result ?? false;
}
