import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';

import '../app/controller.dart';
import '../app/settings.dart';
import '../app/theme.dart';
import 'common.dart';

/// Bet sizing presets as fractions of the pot (after calling).
const sizingPresets = <(String, double)>[('½ Pot', 0.5), ('¾ Pot', 0.75), ('Pot', 1.0)];

/// Raise-to amount for a pot fraction, clamped to the legal window.
int presetRaiseTo(LegalActions l, int potWithBets, double fraction, int step) {
  final raw = l.currentBet + fraction * (potWithBets + l.toCall);
  final rounded = (raw / step).round() * step;
  return rounded.clamp(l.minRaiseTo, l.maxRaiseTo);
}

class ActionBar extends StatefulWidget {
  const ActionBar({super.key, required this.controller});
  final GameController controller;

  @override
  State<ActionBar> createState() => ActionBarState();
}

class ActionBarState extends State<ActionBar> {
  int _raiseTo = 0;
  LegalActions? _for;

  GameController get c => widget.controller;
  int get _step => c.config.smallBlind;

  void _sync(LegalActions l) {
    if (!identical(_for, l)) {
      _for = l;
      _raiseTo = l.minRaiseTo;
    }
  }

  // Keyboard entry points (called by the table screen).
  void fold() {
    final l = c.heroLegal;
    if (l == null) return;
    if (l.canFold) c.act(const PlayerAction.fold());
  }

  void checkOrCall() {
    final l = c.heroLegal;
    if (l == null) return;
    c.act(l.canCheck ? const PlayerAction.check() : const PlayerAction.call());
  }

  void raise() {
    final l = c.heroLegal;
    if (l == null || !l.canRaise) return;
    c.act(PlayerAction(l.isBet ? ActionType.bet : ActionType.raise, _raiseTo.clamp(l.minRaiseTo, l.maxRaiseTo)));
  }

  void nudge(int steps) {
    final l = c.heroLegal;
    if (l == null || !l.canRaise) return;
    setState(() => _raiseTo = (_raiseTo + steps * c.config.bigBlind).clamp(l.minRaiseTo, l.maxRaiseTo));
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final l = c.heroLegal;
        Widget child;
        if (l != null) {
          _sync(l);
          child = _decision(context, l);
        } else if (c.handOver && !c.heroBusted) {
          child = _nextHand(context);
        } else {
          child = const SizedBox(key: ValueKey('idle'), height: 0);
        }
        return AnimatedSwitcher(
          duration: settings.scaled(Motion.medium),
          switchInCurve: Motion.spring,
          transitionBuilder: (w, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a), child: w),
          ),
          child: child,
        );
      },
    );
  }

  Widget _nextHand(BuildContext context) {
    return GlassPanel(
      key: const ValueKey('next'),
      radius: Radii.pill,
      padding: const EdgeInsets.all(6),
      child: PillButton(
        label: 'Deal Next Hand',
        shortcut: 'Space',
        style: PillStyle.filled,
        minWidth: 220,
        onPressed: c.dealNext,
      ),
    );
  }

  Widget _decision(BuildContext context, LegalActions l) {
    final p = Palette.of(context);
    final pot = c.potWithBets;
    final allIn = _raiseTo >= l.maxRaiseTo;
    final raiseLabel = l.isBet ? 'Bet' : 'Raise to';
    return GlassPanel(
      key: const ValueKey('decide'),
      radius: Radii.xl,
      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.l),
      child: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (l.canRaise && l.maxRaiseTo > l.minRaiseTo) ...[
              Row(
                children: [
                  for (final (label, f) in sizingPresets)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _Chip(
                        label: label,
                        selected: _raiseTo == presetRaiseTo(l, pot, f, _step),
                        onTap: () => setState(() => _raiseTo = presetRaiseTo(l, pot, f, _step)),
                      ),
                    ),
                  _Chip(
                    label: 'All-in',
                    selected: allIn,
                    onTap: () => setState(() => _raiseTo = l.maxRaiseTo),
                  ),
                  Expanded(
                    child: CupertinoSlider(
                      value: _raiseTo.toDouble().clamp(l.minRaiseTo.toDouble(), l.maxRaiseTo.toDouble()),
                      min: l.minRaiseTo.toDouble(),
                      max: l.maxRaiseTo.toDouble(),
                      activeColor: p.accent,
                      onChanged: (v) {
                        final stepped = ((v / _step).round() * _step).clamp(l.minRaiseTo, l.maxRaiseTo);
                        setState(() => _raiseTo = v >= l.maxRaiseTo ? l.maxRaiseTo : stepped);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.s),
            ],
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: 'Fold',
                    shortcut: 'F',
                    style: PillStyle.destructive,
                    expand: true,
                    onPressed: l.canFold ? fold : null,
                  ),
                ),
                const SizedBox(width: Space.s),
                Expanded(
                  child: PillButton(
                    label: l.canCheck ? 'Check' : (l.callAmount < l.toCall ? 'Call All-in' : 'Call'),
                    sublabel: l.canCheck ? null : formatChips(l.callAmount),
                    shortcut: 'C',
                    expand: true,
                    onPressed: checkOrCall,
                  ),
                ),
                const SizedBox(width: Space.s),
                Expanded(
                  child: PillButton(
                    label: allIn ? 'All-in' : raiseLabel,
                    sublabel: l.canRaise ? formatChips(_raiseTo) : null,
                    shortcut: 'R',
                    style: PillStyle.filled,
                    expand: true,
                    onPressed: l.canRaise ? raise : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? p.accent.withValues(alpha: 0.16) : (p.isDark ? const Color(0x1FFFFFFF) : const Color(0x0F000000)),
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(color: selected ? p.accent.withValues(alpha: 0.6) : const Color(0x00000000), width: 1),
          ),
          child: Text(label, style: Typo.callout(selected ? p.accent : p.label)),
        ),
      ),
    );
  }
}
