import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';

import '../app/controller.dart';
import '../app/history_store.dart';
import '../app/settings.dart';
import '../app/theme.dart';
import '../widgets/common.dart';
import '../widgets/playing_card.dart';
import 'history_panel.dart';
import 'panel_route.dart';
import 'settings_panel.dart';
import 'range_screen.dart';
import 'stats_screen.dart';
import 'training_screen.dart';
import 'table_screen.dart';

const _stakes = [(1, 2), (5, 10), (25, 50), (100, 200)];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.history});
  final HistoryStore history;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _seats = 6;
  int _stake = 1;
  String _style = 'mixed';
  Difficulty _difficulty = Difficulty.standard;
  late final TextEditingController _name;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _nameInit();
  }

  bool _inited = false;
  void _nameInit() {
    if (_inited) return;
    _inited = true;
    _name = TextEditingController(text: SettingsScope.of(context).playerName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _sitDown() {
    final settings = SettingsScope.of(context);
    final name = _name.text.trim().isEmpty ? 'You' : _name.text.trim();
    settings.update((s) => s.playerName = name);
    final (sb, bb) = _stakes[_stake];
    Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: Motion.slow,
      reverseTransitionDuration: Motion.medium,
      pageBuilder: (_, _, _) => TableScreen(
        config: TableConfig(seats: _seats, smallBlind: sb, bigBlind: bb, style: _style, difficulty: _difficulty),
        history: widget.history,
      ),
      transitionsBuilder: (_, a, _, child) {
        final c = CurvedAnimation(parent: a, curve: Motion.spring);
        return FadeTransition(
          opacity: c,
          child: ScaleTransition(scale: Tween(begin: 1.04, end: 1.0).animate(c), child: child),
        );
      },
    )).then((_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final hands = widget.history.hands;
    final net = hands.fold(0, (a, h) => a + h.heroNet);
    return CupertinoPageScaffold(
      backgroundColor: p.background,
      child: Stack(
        children: [
          Positioned(
            top: Space.l,
            right: Space.l,
            child: Row(children: [
              IconPill(
                icon: CupertinoIcons.chart_bar_alt_fill,
                tooltip: 'Statistics',
                onPressed: () => Navigator.of(context)
                    .push(CupertinoPageRoute<void>(builder: (_) => StatsScreen(history: widget.history)))
                    .then((_) => setState(() {})),
              ),
              const SizedBox(width: Space.s),
              IconPill(
                icon: CupertinoIcons.clock,
                tooltip: 'Hand history',
                onPressed: () => showPanel(context,
                    title: 'History', width: 520, builder: (_) => HistoryPanel(store: widget.history)),
              ),
              const SizedBox(width: Space.s),
              IconPill(
                icon: CupertinoIcons.gear_alt,
                tooltip: 'Settings',
                onPressed: () => showPanel(context, title: 'Settings', width: 540, builder: (_) => SettingsPanel(history: widget.history)).then((_) => setState(() {})),
              ),
            ]),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: Space.xxl),
              child: SizedBox(
                width: 600,
                child: Column(
                  children: [
                    const _HeroCards(),
                    const SizedBox(height: Space.xl),
                    Text('Felt', style: Typo.largeTitle(p.label).copyWith(fontSize: 44)),
                    const SizedBox(height: Space.xs),
                    Text("No-Limit Texas Hold'em", style: Typo.body(p.secondaryLabel)),
                    if (hands.isNotEmpty) ...[
                      const SizedBox(height: Space.s),
                      Text(
                        '${formatChips(hands.length)} hands played · '
                        '${net >= 0 ? '+' : ''}${formatChips(net)} chips',
                        style: Typo.callout(p.tertiaryLabel),
                      ),
                    ],
                    const SizedBox(height: Space.xl),
                    CupertinoListSection.insetGrouped(
                      margin: EdgeInsets.zero,
                      children: [
                        CupertinoListTile(
                          title: const Text('Your name'),
                          trailing: SizedBox(
                            width: 180,
                            child: CupertinoTextField(
                              controller: _name,
                              textAlign: TextAlign.end,
                              maxLength: 16,
                              decoration: null,
                              placeholder: 'You',
                            ),
                          ),
                        ),
                        CupertinoListTile(
                          title: const Text('Players'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('$_seats', style: Typo.number(p.label, size: 15)),
                            const SizedBox(width: Space.m),
                            _Stepper(
                              onMinus: _seats > 2 ? () => setState(() => _seats--) : null,
                              onPlus: _seats < 9 ? () => setState(() => _seats++) : null,
                            ),
                          ]),
                        ),
                        _Field(
                          label: 'Stakes',
                          child: CupertinoSlidingSegmentedControl<int>(
                            groupValue: _stake,
                            children: {
                              for (var i = 0; i < _stakes.length; i++)
                                i: Text('${_stakes[i].$1}/${_stakes[i].$2}'),
                            },
                            onValueChanged: (v) => setState(() => _stake = v ?? 1),
                          ),
                        ),
                        _Field(
                          label: 'Opponents',
                          child: CupertinoSlidingSegmentedControl<String>(
                            groupValue: _style,
                            children: {
                              'mixed': const Text('Mixed'),
                              for (final s in Personality.all) s.id: Text(s.label),
                            },
                            onValueChanged: (v) => setState(() => _style = v ?? 'mixed'),
                          ),
                        ),
                        _Field(
                          label: 'Skill',
                          child: CupertinoSlidingSegmentedControl<Difficulty>(
                            groupValue: _difficulty,
                            children: const {
                              Difficulty.casual: Text('Casual'),
                              Difficulty.standard: Text('Standard'),
                              Difficulty.expert: Text('Expert'),
                            },
                            onValueChanged: (v) => setState(() => _difficulty = v ?? Difficulty.standard),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.s),
                    Text(
                      'Buy-in ${formatChips(_stakes[_stake].$2 * 100)} · 100 big blinds',
                      style: Typo.callout(p.secondaryLabel),
                    ),
                    const SizedBox(height: Space.xl),
                    PillButton(
                      label: 'Sit Down',
                      style: PillStyle.filled,
                      minWidth: 240,
                      height: 52,
                      onPressed: _sitDown,
                    ),
                    const SizedBox(height: Space.m),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      PillButton(
                        label: 'Training',
                        style: PillStyle.plain,
                        minWidth: 0,
                        onPressed: () => Navigator.of(context)
                            .push(CupertinoPageRoute<void>(builder: (_) => TrainingScreen(history: widget.history))),
                      ),
                      PillButton(
                        label: 'Range Charts',
                        style: PillStyle.plain,
                        minWidth: 0,
                        onPressed: () => Navigator.of(context)
                            .push(CupertinoPageRoute<void>(builder: (_) => RangeScreen(history: widget.history))),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A grouped-list row with the label above a full-width control.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Typo.body(p.label)),
          const SizedBox(height: Space.s),
          child,
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.onMinus, required this.onPlus});
  final VoidCallback? onMinus, onPlus;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget btn(IconData i, VoidCallback? f) => CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          minimumSize: const Size(36, 28),
          onPressed: f,
          child: Icon(i, size: 16, color: f == null ? p.tertiaryLabel : p.label),
        );
    return Container(
      decoration: BoxDecoration(
        color: p.isDark ? const Color(0x33FFFFFF) : const Color(0x14000000),
        borderRadius: BorderRadius.circular(Radii.s),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(CupertinoIcons.minus, onMinus),
        Container(width: 0.5, height: 18, color: p.separator),
        btn(CupertinoIcons.plus, onPlus),
      ]),
    );
  }
}

/// Two fanned cards as the app's hero image.
class _HeroCards extends StatelessWidget {
  const _HeroCards();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      height: 130,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.translate(
            offset: const Offset(-26, 4),
            child: Transform.rotate(
              angle: -0.18,
              child: DealIn(child: PlayingCard(card: parseCard('As'), width: 80)),
            ),
          ),
          Transform.translate(
            offset: const Offset(26, 4),
            child: Transform.rotate(
              angle: 0.18,
              child: DealIn(from: const Offset(0.3, -0.4), child: PlayingCard(card: parseCard('Kh'), width: 80)),
            ),
          ),
        ],
      ),
    );
  }
}
