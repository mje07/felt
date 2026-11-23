import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';

import '../app/bankroll.dart';
import '../app/controller.dart';
import '../app/history_store.dart';
import '../app/settings.dart';
import '../app/sounds.dart';
import '../app/theme.dart';
import '../widgets/action_bar.dart';
import '../widgets/common.dart';
import '../widgets/table_view.dart';
import 'history_panel.dart';
import 'panel_route.dart';
import 'settings_panel.dart';
import 'stats_screen.dart';

class TableScreen extends StatefulWidget {
  const TableScreen({
    super.key,
    required this.config,
    required this.history,
    this.useIsolates = true,
    this.onController,
  });
  final TableConfig config;
  final HistoryStore history;
  final bool useIsolates;

  /// Exposes the controller (tests, screenshots).
  final ValueChanged<GameController>? onController;

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  GameController? _controller;
  final _bar = GlobalKey<ActionBarState>();
  final _focus = FocusNode(debugLabel: 'table');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= GameController(
      config: widget.config,
      settings: SettingsScope.of(context),
      history: widget.history,
      useIsolates: widget.useIsolates,
      sounds: SoundsScope.of(context),
    )..start();
    widget.onController?.call(_controller!);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final c = _controller!;
    final bar = _bar.currentState;
    final k = e.logicalKey;
    if (c.heroLegal != null && bar != null) {
      if (k == LogicalKeyboardKey.keyF) return _done(bar.fold);
      if (k == LogicalKeyboardKey.keyC || k == LogicalKeyboardKey.keyK) return _done(bar.checkOrCall);
      if (k == LogicalKeyboardKey.keyR || k == LogicalKeyboardKey.keyB) return _done(bar.raise);
      if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowRight) return _done(() => bar.nudge(1));
      if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowLeft) return _done(() => bar.nudge(-1));
    }
    if (c.handOver && (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.enter)) {
      return _done(c.dealNext);
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _done(VoidCallback f) {
    f();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = _controller!;
    return CupertinoPageScaffold(
      backgroundColor: p.background,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.1),
                    radius: 1.2,
                    colors: p.isDark
                        ? const [Color(0xFF1C1C1E), Color(0xFF000000)]
                        : const [Color(0xFFFFFFFF), Color(0xFFE8E8ED)],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              top: 80,
              bottom: 144,
              child: PokerTable(controller: c),
            ),
            Positioned(top: 0, left: 0, right: 0, child: _TopBar(controller: c, history: widget.history)),
            Positioned(
              left: 0,
              right: 0,
              bottom: Space.l,
              child: Center(child: ActionBar(key: _bar, controller: c)),
            ),
            ListenableBuilder(
              listenable: c,
              builder: (context, _) => c.outcome != null
                  ? _ResultsOverlay(controller: c, history: widget.history)
                  : (c.heroBusted ? _BustOverlay(controller: c) : const SizedBox.shrink()),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, required this.history});
  final GameController controller;
  final HistoryStore history;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final cfg = controller.config;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
      child: Row(
        children: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onPressed: () => leaveTable(context, controller),
            child: Row(children: [
              Icon(CupertinoIcons.chevron_left, size: 18, color: p.accent),
              const SizedBox(width: 2),
              Text('Lobby', style: Typo.body(p.accent)),
            ]),
          ),
          const Spacer(),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Column(
              children: [
                Text(
                  controller.tournament != null
                      ? controller.tournamentTitle
                      : "No-Limit Hold'em · ${cfg.smallBlind}/${cfg.bigBlind}",
                  style: Typo.headline(p.label),
                ),
                Text(
                  controller.tournament != null
                      ? controller.tournamentStatus
                      : (controller.view.handNumber > 0 ? 'Hand #${controller.view.handNumber}' : 'Shuffling…'),
                  style: Typo.caption(p.secondaryLabel),
                ),
              ],
            ),
          ),
          const Spacer(),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final net = controller.sessionNet;
              final acc = controller.sessionAccuracy;
              Widget readout(String label, Widget value) => Padding(
                    padding: const EdgeInsets.only(right: Space.l),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(label, style: Typo.caption(p.secondaryLabel).copyWith(letterSpacing: 0.8)),
                        value,
                      ],
                    ),
                  );
              return Row(children: [
                if (acc != null && SettingsScope.of(context).showCoachAtTable)
                  readout('ACCURACY', Text('${acc.round()}%', style: Typo.number(p.label, size: 15))),
                if (controller.tournament != null)
                  readout('PRIZE POOL', Text(formatChips(controller.tournament!.prizePool), style: Typo.number(p.label, size: 15)))
                else
                readout(
                  'SESSION',
                  AnimatedCount(
                    value: net,
                    prefix: net > 0 ? '+' : '',
                    style: Typo.number(net > 0 ? p.positive : (net < 0 ? p.destructive : p.label), size: 15),
                  ),
                ),
              ]);
            },
          ),
          IconPill(
            icon: CupertinoIcons.chart_bar_alt_fill,
            tooltip: 'Statistics',
            onPressed: () => Navigator.of(context)
                .push(CupertinoPageRoute<void>(builder: (_) => StatsScreen(history: history))),
          ),
          const SizedBox(width: Space.s),
          IconPill(
            icon: CupertinoIcons.clock,
            tooltip: 'Hand history',
            onPressed: () => showPanel(context,
                title: 'History', width: 520, builder: (_) => HistoryPanel(store: history)),
          ),
          const SizedBox(width: Space.s),
          IconPill(
            icon: CupertinoIcons.gear_alt,
            tooltip: 'Settings',
            onPressed: () => showPanel(context, title: 'Settings', width: 540, builder: (_) => SettingsPanel(history: history)),
          ),
        ],
      ),
    );
  }
}

class _BustOverlay extends StatelessWidget {
  const _BustOverlay({required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x66000000),
        child: Center(
          child: GlassPanel(
            radius: Radii.xl,
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.circle_grid_hex, size: 36, color: p.secondaryLabel),
                const SizedBox(height: Space.m),
                Text("You're out of chips", style: Typo.title(p.label)),
                const SizedBox(height: Space.xs),
                Text('Buy back in to keep playing.', style: Typo.body(p.secondaryLabel)),
                const SizedBox(height: Space.xl),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PillButton(label: 'Leave Table', onPressed: () => Navigator.of(context).maybePop()),
                    const SizedBox(width: Space.s),
                    PillButton(
                      label: controller.canAffordRebuy ? 'Rebuy ${formatChips(controller.config.buyIn)}' : 'Top Up & Rebuy',
                      style: PillStyle.filled,
                      onPressed: () {
                        if (!controller.canAffordRebuy) Bankroll.current.topUp();
                        controller.rebuy();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Route that opens a table with [config] (lobby and "Play again").
PageRouteBuilder<void> tableRoute(TableConfig config, HistoryStore history) => PageRouteBuilder<void>(
      transitionDuration: Motion.slow,
      reverseTransitionDuration: Motion.medium,
      pageBuilder: (_, _, _) => TableScreen(config: config, history: history),
      transitionsBuilder: (_, a, _, child) {
        final c = CurvedAnimation(parent: a, curve: Motion.spring);
        return FadeTransition(
          opacity: c,
          child: ScaleTransition(scale: Tween(begin: 1.04, end: 1.0).animate(c), child: child),
        );
      },
    );

/// Leaves the table; leaving a running Sit & Go asks to confirm the forfeit.
Future<void> leaveTable(BuildContext context, GameController c) async {
  if (c.tournamentInProgress) {
    final ok = await confirmAction(
      context,
      title: 'Leave the Sit & Go?',
      message: 'You\'ll forfeit your ${formatChips(c.config.sngBuyIn)} buy-in. Your seat won\'t be kept.',
      action: 'Leave',
    );
    if (!ok || !context.mounted) return;
  }
  await Navigator.of(context).maybePop();
}

class _ResultsOverlay extends StatelessWidget {
  const _ResultsOverlay({required this.controller, required this.history});
  final GameController controller;
  final HistoryStore history;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final o = controller.outcome!;
    final net = o.prize - o.buyIn;
    final title = o.won ? 'You won the Sit & Go!' : 'You finished ${ordinal(o.place)} of ${o.players}';
    final subtitle = o.won
        ? 'Last one standing out of ${o.players}.'
        : o.inTheMoney
            ? 'In the money. ${o.winnerName} won the tournament.'
            : '${o.winnerName} went on to win the tournament.';
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x66000000),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.92, end: 1),
            duration: Motion.slow,
            curve: Motion.snappy,
            builder: (context, s, child) => Transform.scale(scale: s, child: child),
            child: GlassPanel(
              radius: Radii.xl,
              padding: const EdgeInsets.all(Space.xxl),
              child: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (o.inTheMoney ? const Color(0xFFFFB800) : p.secondaryLabel).withValues(alpha: 0.16),
                      ),
                      child: Icon(
                        o.won ? CupertinoIcons.rosette : (o.inTheMoney ? CupertinoIcons.star_fill : CupertinoIcons.flag_fill),
                        size: 32,
                        color: o.inTheMoney ? const Color(0xFFE0A000) : p.secondaryLabel,
                      ),
                    ),
                    const SizedBox(height: Space.l),
                    Text(title, textAlign: TextAlign.center, style: Typo.title(p.label)),
                    const SizedBox(height: Space.xs),
                    Text(subtitle, textAlign: TextAlign.center, style: Typo.body(p.secondaryLabel)),
                    const SizedBox(height: Space.xl),
                    Row(children: [
                      _Figure('PRIZE', formatChips(o.prize)),
                      _Figure('BUY-IN', formatChips(o.buyIn)),
                      _Figure('NET', '${net > 0 ? '+' : (net < 0 ? '−' : '')}${formatChips(net.abs())}',
                          color: net > 0 ? p.positive : (net < 0 ? p.destructive : null)),
                    ]),
                    const SizedBox(height: Space.xl),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      PillButton(label: 'Lobby', onPressed: () => Navigator.of(context).maybePop()),
                      const SizedBox(width: Space.s),
                      PillButton(
                        label: 'Play Again',
                        sublabel: formatChips(controller.config.sngBuyIn),
                        style: PillStyle.filled,
                        onPressed: Bankroll.current.canAfford(controller.config.sngBuyIn)
                            ? () => Navigator.of(context).pushReplacement(tableRoute(controller.config, history))
                            : null,
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, {this.color});
  final String label, value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Expanded(
      child: Column(children: [
        Text(label, style: Typo.caption(p.secondaryLabel).copyWith(letterSpacing: 0.8)),
        const SizedBox(height: 2),
        Text(value, style: Typo.number(color ?? p.label, size: 20)),
      ]),
    );
  }
}
