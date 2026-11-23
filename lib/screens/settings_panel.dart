import 'package:cupertino_ui/cupertino_ui.dart';

import '../app/settings.dart';
import '../app/theme.dart';
import '../widgets/playing_card.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final p = Palette.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: Space.l),
      child: Column(
        children: [
          CupertinoListSection.insetGrouped(
            header: const Text('APPEARANCE'),
            children: [
              CupertinoListTile(
                title: const Text('Theme'),
                trailing: CupertinoSlidingSegmentedControl<Appearance>(
                  groupValue: s.appearance,
                  children: const {
                    Appearance.system: Text('Auto'),
                    Appearance.light: Text('Light'),
                    Appearance.dark: Text('Dark'),
                  },
                  onValueChanged: (v) => s.update((s) => s.appearance = v ?? Appearance.system),
                ),
              ),
              CupertinoListTile(
                title: const Text('Four-colour deck'),
                subtitle: Row(
                  children: [
                    for (var suit = 0; suit < 4; suit++)
                      Padding(
                        padding: const EdgeInsets.only(right: 4, top: 2),
                        child: SuitIcon(suit: suit, size: 12, color: suitColor(p, suit, s.fourColorDeck)),
                      ),
                  ],
                ),
                trailing: CupertinoSwitch(
                  value: s.fourColorDeck,
                  onChanged: (v) => s.update((s) => s.fourColorDeck = v),
                ),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            header: const Text('GAMEPLAY'),
            children: [
              CupertinoListTile(
                title: const Text('Speed'),
                trailing: CupertinoSlidingSegmentedControl<GameSpeed>(
                  groupValue: s.speed,
                  children: {for (final g in GameSpeed.values) g: Text(g.label)},
                  onValueChanged: (v) => s.update((s) => s.speed = v ?? GameSpeed.normal),
                ),
              ),
              CupertinoListTile(
                title: const Text('Deal next hand automatically'),
                trailing: CupertinoSwitch(
                  value: s.autoDeal,
                  onChanged: (v) => s.update((s) => s.autoDeal = v),
                ),
              ),
              CupertinoListTile(
                title: const Text('Reduce motion'),
                trailing: CupertinoSwitch(
                  value: s.reduceMotion,
                  onChanged: (v) => s.update((s) => s.reduceMotion = v),
                ),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            header: const Text('KEYBOARD'),
            children: const [
              _Key('Fold', 'F'),
              _Key('Check / Call', 'C'),
              _Key('Bet / Raise', 'R'),
              _Key('Adjust bet', '↑ ↓'),
              _Key('Deal next hand', 'Space'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key(this.label, this.key_);
  final String label, key_;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return CupertinoListTile(
      title: Text(label),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: p.separator),
        ),
        child: Text(key_, style: Typo.callout(p.secondaryLabel)),
      ),
    );
  }
}
