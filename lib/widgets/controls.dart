import 'package:cupertino_ui/cupertino_ui.dart';

import '../app/settings.dart';
import '../app/theme.dart';

/// Felt's on/off control: a slim accent track with a soft knob.
class FeltToggle extends StatelessWidget {
  const FeltToggle({super.key, required this.value, required this.onChanged, this.label});
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Accessibility label.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = onChanged != null;
    return Semantics(
      label: label,
      toggled: value,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: enabled ? () => onChanged!(!value) : null,
          child: AnimatedOpacity(
            duration: Motion.fast,
            opacity: enabled ? 1 : 0.4,
            child: AnimatedContainer(
              duration: Motion.fast,
              curve: Curves.easeOut,
              width: 40,
              height: 24,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value ? p.accent : (p.isDark ? const Color(0x33FFFFFF) : const Color(0x1F000000)),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: AnimatedAlign(
                duration: Motion.medium,
                curve: Motion.snappy,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFFFFFFF),
                    boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of pill chips for picking one option (same style as the table's
/// bet-size chips).
class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final e in options.entries)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onChanged(e.key),
              child: AnimatedContainer(
                duration: Motion.fast,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: e.key == value
                      ? p.accent.withValues(alpha: 0.14)
                      : (p.isDark ? const Color(0x1AFFFFFF) : const Color(0x0D000000)),
                  borderRadius: BorderRadius.circular(Radii.pill),
                  border: Border.all(
                      color: e.key == value ? p.accent.withValues(alpha: 0.55) : const Color(0x00000000)),
                ),
                child: Text(e.value,
                    style: Typo.callout(e.key == value ? p.accent : p.label)
                        .copyWith(fontWeight: e.key == value ? FontWeight.w600 : FontWeight.w500)),
              ),
            ),
          ),
      ],
    );
  }
}

/// A titled group of settings, styled like the app's other cards.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final rows = <Widget>[];
    for (final (i, c) in children.indexed) {
      if (i > 0) rows.add(Container(height: 0.5, color: p.separator, margin: const EdgeInsets.symmetric(vertical: 12)));
      rows.add(c);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.l),
      decoration: BoxDecoration(
        color: p.isDark ? const Color(0xFF242426) : const Color(0xFFF7F7F9),
        borderRadius: BorderRadius.circular(Radii.l),
        border: Border.all(color: p.separator, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: p.accent),
            const SizedBox(width: Space.s),
            Text(title, style: Typo.headline(p.label)),
          ]),
          const SizedBox(height: Space.m),
          ...rows,
        ],
      ),
    );
  }
}

/// Label (+ optional detail) on the left, control on the right. Pass
/// [below] for a control that needs the full width.
class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.label, this.detail, this.trailing, this.below, this.enabled = true});
  final String label;
  final String? detail;
  final Widget? trailing, below;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return AnimatedOpacity(
      duration: Motion.fast,
      opacity: enabled ? 1 : 0.45,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: Typo.body(p.label)),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(detail!, style: Typo.caption(p.secondaryLabel).copyWith(fontSize: 12, height: 1.35)),
                ],
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: Space.l), trailing!],
          ]),
          if (below != null) ...[const SizedBox(height: Space.m), below!],
        ],
      ),
    );
  }
}

/// A keyboard key, for shortcut hints.
class KeyCap extends StatelessWidget {
  const KeyCap(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.separator),
        boxShadow: [BoxShadow(color: p.separator, offset: const Offset(0, 1.5))],
      ),
      alignment: Alignment.center,
      child: Text(text, style: Typo.number(p.label, size: 12, weight: FontWeight.w600)),
    );
  }
}

/// Theme picker: three small previews of the table in each appearance.
class ThemeSwatches extends StatelessWidget {
  const ThemeSwatches({super.key, required this.value, required this.onChanged});
  final Appearance value;
  final ValueChanged<Appearance> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (final (a, label) in const [(Appearance.system, 'Auto'), (Appearance.light, 'Light'), (Appearance.dark, 'Dark')])
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: a == Appearance.dark ? 0 : Space.s),
            child: _Swatch(appearance: a, label: label, selected: value == a, onTap: () => onChanged(a)),
          ),
        ),
    ]);
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.appearance, required this.label, required this.selected, required this.onTap});
  final Appearance appearance;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget preview(Palette t) => Container(
          color: t.background,
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(width: 18, height: 4, decoration: BoxDecoration(color: t.tertiaryLabel, borderRadius: BorderRadius.circular(2))),
              const Spacer(),
              Container(width: 8, height: 8, decoration: BoxDecoration(color: t.surface, shape: BoxShape.circle)),
            ]),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: t.rail,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                padding: const EdgeInsets.all(2.5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    gradient: RadialGradient(colors: [t.feltCenter, t.feltEdge]),
                  ),
                ),
              ),
            ),
          ]),
        );
    final content = switch (appearance) {
      Appearance.light => preview(Palette.light),
      Appearance.dark => preview(Palette.dark),
      Appearance.system => Stack(fit: StackFit.expand, children: [
          preview(Palette.light),
          ClipRect(clipper: const _RightHalf(), child: preview(Palette.dark)),
        ]),
    };
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Column(children: [
          AnimatedContainer(
            duration: Motion.fast,
            height: 64,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.m + 2),
              border: Border.all(color: selected ? p.accent : p.separator, width: selected ? 2 : 1),
            ),
            child: ClipRRect(borderRadius: BorderRadius.circular(Radii.m - 1), child: content),
          ),
          const SizedBox(height: 6),
          Text(label, style: Typo.callout(selected ? p.accent : p.secondaryLabel)
              .copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
        ]),
      ),
    );
  }
}

class _RightHalf extends CustomClipper<Rect> {
  const _RightHalf();
  @override
  Rect getClip(Size size) => Rect.fromLTWH(size.width / 2, 0, size.width / 2, size.height);
  @override
  bool shouldReclip(_RightHalf oldClipper) => false;
}
