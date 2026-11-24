import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';

import '../app/achievements.dart';
import '../app/theme.dart';
import 'common.dart';

/// Slides in at the top of the window when an achievement unlocks.
class AchievementToast extends StatefulWidget {
  const AchievementToast({super.key});

  @override
  State<AchievementToast> createState() => _AchievementToastState();
}

class _AchievementToastState extends State<AchievementToast> {
  Achievement? _showing;
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    Achievements.current.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    Achievements.current.removeListener(_check);
    _timer?.cancel();
    super.dispose();
  }

  void _check() {
    if (!mounted || _showing != null) return;
    final next = Achievements.current.takeFresh();
    if (next == null) return;
    setState(() {
      _showing = next;
      _visible = true;
    });
    _timer = Timer(const Duration(milliseconds: 3600), () {
      if (!mounted) return;
      setState(() => _visible = false);
      _timer = Timer(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        setState(() => _showing = null);
        _check();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = _showing;
    if (a == null) return const SizedBox.shrink();
    final p = Palette.of(context);
    return Positioned(
      top: Space.l,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: AnimatedSlide(
            duration: Motion.medium,
            curve: Motion.spring,
            offset: _visible ? Offset.zero : const Offset(0, -1.6),
            child: AnimatedOpacity(
              duration: Motion.medium,
              opacity: _visible ? 1 : 0,
              child: GlassPanel(
                padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(colors: [p.feltCenter, p.feltEdge]),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(a.icon, size: 18, color: const Color(0xFFFFD60A)),
                  ),
                  const SizedBox(width: Space.m),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('ACHIEVEMENT UNLOCKED',
                        style: Typo.caption(p.secondaryLabel).copyWith(letterSpacing: 1, fontWeight: FontWeight.w600)),
                    Text(a.title, style: Typo.headline(p.label)),
                    Text(a.description, style: Typo.caption(p.secondaryLabel)),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
