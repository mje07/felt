import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';

import '../app/bankroll.dart';
import '../app/controller.dart';
import '../app/history_store.dart';
import '../app/settings.dart';
import '../app/theme.dart';
import '../app/updater.dart';
import '../widgets/common.dart';
import '../widgets/controls.dart';
import '../widgets/playing_card.dart';
import 'equity_lab_screen.dart';
import 'history_panel.dart';
import 'panel_route.dart';
import 'settings_panel.dart';
import 'range_screen.dart';
import 'stats_screen.dart';
import 'study_screen.dart';
import 'training_screen.dart';
import 'table_screen.dart';

const _stakes = [(1, 2), (5, 10), (25, 50), (100, 200)];
const _sngBuyIns = [100, 500, 2500, 10000];

const _styleBlurb = {
  'mixed': 'A table of different styles: the most realistic game.',
  'rock': 'Plays very few hands and rarely bluffs.',
  'tag': 'Tight and aggressive: selective, then hard to push around.',
  'lag': 'Plays lots of hands and keeps the pressure on.',
  'station': 'Calls far too much. Value bet them relentlessly.',
  'maniac': 'Bets and raises with almost anything.',
};

const _skillBlurb = {
  Difficulty.casual: 'Makes clear mistakes. Good for learning.',
  Difficulty.standard: 'Solid fundamentals with the odd error.',
  Difficulty.expert: 'Reads ranges carefully and rarely slips.',
};

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
  GameMode _mode = GameMode.cash;
  int _sngBuyIn = 1;
  BlindSpeed _speed = BlindSpeed.turbo;
  StartingStack _startStack = StartingStack.standard;
  PayoutStyle _payouts = PayoutStyle.standard;
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

  TableConfig get _config {
    final (sb, bb) = _stakes[_stake];
    return TableConfig(
      mode: _mode,
      seats: _seats,
      smallBlind: sb,
      bigBlind: bb,
      style: _style,
      difficulty: _difficulty,
      sngBuyIn: _sngBuyIns[_sngBuyIn],
      speed: _speed,
      startingStack: _startStack,
      payoutStyle: _payouts,
    );
  }

  void _sitDown() {
    final settings = SettingsScope.of(context);
    final name = _name.text.trim().isEmpty ? 'You' : _name.text.trim();
    settings.update((s) => s.playerName = name);
    Navigator.of(context).push(tableRoute(_config, widget.history)).then((_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final bankroll = Bankroll.current;
    return ListenableBuilder(
      listenable: bankroll,
      builder: (context, _) {
        final config = _config;
        final cost = config.entryCost;
        final affordable = bankroll.canAfford(cost);
        final tournament = _mode == GameMode.sitAndGo;
        final prizes = prizesFor(_payouts, _seats, _sngBuyIns[_sngBuyIn]);
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
                        title: 'History', width: 560, builder: (_) => HistoryPanel(store: widget.history)),
                  ),
                  const SizedBox(width: Space.s),
                  IconPill(
                    icon: CupertinoIcons.gear_alt,
                    tooltip: 'Settings',
                    onPressed: () => showPanel(context,
                            title: 'Settings', width: 540, builder: (_) => SettingsPanel(history: widget.history))
                        .then((_) => setState(() {})),
                  ),
                ]),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: Space.xxl),
                  child: SizedBox(
                    width: 620,
                    child: Column(
                      children: [
                        const _HeroCards(),
                        const SizedBox(height: Space.xl),
                        Text('Felt', style: Typo.largeTitle(p.label).copyWith(fontSize: 44)),
                        const SizedBox(height: Space.xs),
                        Text("No-Limit Texas Hold'em", style: Typo.body(p.secondaryLabel)),
                        const SizedBox(height: Space.m),
                        _BankrollLine(bankroll: bankroll),
                        const _UpdateBanner(),
                        const SizedBox(height: Space.xl),
                        SettingsCard(
                          title: 'New table',
                          icon: CupertinoIcons.suit_spade_fill,
                          color: p.surface,
                          children: [
                            ChoiceChips<GameMode>(
                              value: _mode,
                              options: const {GameMode.cash: 'Cash game', GameMode.sitAndGo: 'Sit & Go'},
                              onChanged: (v) => setState(() => _mode = v),
                            ),
                            SettingRow(
                              label: 'Your name',
                              trailing: FeltTextField(controller: _name, placeholder: 'You', maxLength: 16),
                            ),
                            SettingRow(
                              label: 'Players',
                              detail: _seats == 2 ? 'Heads-up against one opponent' : 'You and ${_seats - 1} opponents',
                              trailing: ChoiceChips<int>(
                                value: _seats,
                                options: {for (var n = 2; n <= 9; n++) n: '$n'},
                                onChanged: (v) => setState(() => _seats = v),
                              ),
                            ),
                            if (!tournament)
                              SettingRow(
                                label: 'Stakes',
                                detail: 'Buy-in ${formatChips(_stakes[_stake].$2 * 100)} · 100 big blinds',
                                trailing: ChoiceChips<int>(
                                  value: _stake,
                                  options: {
                                    for (var i = 0; i < _stakes.length; i++) i: '${_stakes[i].$1}/${_stakes[i].$2}'
                                  },
                                  onChanged: (v) => setState(() => _stake = v),
                                ),
                              )
                            else ...[
                              SettingRow(
                                label: 'Buy-in',
                                detail: 'Prize pool ${formatChips(_sngBuyIns[_sngBuyIn] * _seats)}',
                                trailing: ChoiceChips<int>(
                                  value: _sngBuyIn,
                                  options: {for (var i = 0; i < _sngBuyIns.length; i++) i: formatChips(_sngBuyIns[i])},
                                  onChanged: (v) => setState(() => _sngBuyIn = v),
                                ),
                              ),
                              SettingRow(
                                label: 'Payouts',
                                detail: [
                                  for (final (i, prize) in prizes.indexed) '${ordinal(i + 1)} ${formatChips(prize)}'
                                ].join(' · '),
                                trailing: ChoiceChips<PayoutStyle>(
                                  value: _payouts,
                                  options: {for (final s in PayoutStyle.values) s: s.label},
                                  onChanged: (v) => setState(() => _payouts = v),
                                ),
                              ),
                              SettingRow(
                                label: 'Starting stack',
                                detail: '${formatChips(_startStack.chips)} chips · blinds start at 10/20',
                                trailing: ChoiceChips<StartingStack>(
                                  value: _startStack,
                                  options: {for (final s in StartingStack.values) s: s.label},
                                  onChanged: (v) => setState(() => _startStack = v),
                                ),
                              ),
                              SettingRow(
                                label: 'Blind speed',
                                detail: 'Blinds go up every ${_speed.handsPerLevel} hands',
                                trailing: ChoiceChips<BlindSpeed>(
                                  value: _speed,
                                  options: {for (final s in BlindSpeed.values) s: s.label},
                                  onChanged: (v) => setState(() => _speed = v),
                                ),
                              ),
                            ],
                            SettingRow(
                              label: 'Opponents',
                              detail: _styleBlurb[_style],
                              below: ChoiceChips<String>(
                                value: _style,
                                options: {'mixed': 'Mixed', for (final s in Personality.all) s.id: s.label},
                                onChanged: (v) => setState(() => _style = v),
                              ),
                            ),
                            SettingRow(
                              label: 'Skill',
                              detail: _skillBlurb[_difficulty],
                              trailing: ChoiceChips<Difficulty>(
                                value: _difficulty,
                                options: const {
                                  Difficulty.casual: 'Casual',
                                  Difficulty.standard: 'Standard',
                                  Difficulty.expert: 'Expert',
                                },
                                onChanged: (v) => setState(() => _difficulty = v),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.xl),
                        PillButton(
                          label: tournament ? 'Register' : 'Sit Down',
                          sublabel: '${formatChips(cost)} from your bankroll',
                          style: PillStyle.filled,
                          minWidth: 260,
                          height: 56,
                          onPressed: affordable ? _sitDown : null,
                        ),
                        if (!affordable) ...[
                          const SizedBox(height: Space.s),
                          Text('Not enough chips in your bankroll for this table.',
                              style: Typo.callout(p.destructive)),
                        ],
                        const SizedBox(height: Space.m),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          PillButton(
                            label: 'Training',
                            style: PillStyle.plain,
                            minWidth: 0,
                            onPressed: () => Navigator.of(context).push(
                                CupertinoPageRoute<void>(builder: (_) => TrainingScreen(history: widget.history))),
                          ),
                          PillButton(
                            label: 'Range Charts',
                            style: PillStyle.plain,
                            minWidth: 0,
                            onPressed: () => Navigator.of(context)
                                .push(CupertinoPageRoute<void>(builder: (_) => RangeScreen(history: widget.history))),
                          ),
                          PillButton(
                            label: 'Equity Lab',
                            style: PillStyle.plain,
                            minWidth: 0,
                            onPressed: () => Navigator.of(context)
                                .push(CupertinoPageRoute<void>(builder: (_) => const EquityLabScreen())),
                          ),
                          PillButton(
                            label: 'Study',
                            style: PillStyle.plain,
                            minWidth: 0,
                            onPressed: () => Navigator.of(context)
                                .push(CupertinoPageRoute<void>(builder: (_) => const StudyScreen())),
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
      },
    );
  }
}

class _BankrollLine extends StatelessWidget {
  const _BankrollLine({required this.bankroll});
  final Bankroll bankroll;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final low = bankroll.balance < 1000;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const ChipDisc(amount: 1000, size: 16),
      const SizedBox(width: 6),
      Text('Bankroll ', style: Typo.callout(p.secondaryLabel)),
      AnimatedCount(value: bankroll.balance, style: Typo.number(p.label, size: 14)),
      if (low) ...[
        const SizedBox(width: Space.s),
        PillButton(
          label: 'Top up to ${formatChips(Bankroll.startingBalance)}',
          style: PillStyle.plain,
          minWidth: 0,
          height: 30,
          onPressed: bankroll.topUp,
        ),
      ],
    ]);
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

/// A quiet line under the bankroll when a new version is downloading, ready
/// to install, or available to download.
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner();

  @override
  Widget build(BuildContext context) {
    final u = Updater.current;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final p = Palette.of(context);
        final v = u.latestVersion;
        final (String text, Widget? action) = switch (u.status) {
          UpdateStatus.downloading => ('Downloading Felt $v… ${(u.progress * 100).round()}%', null),
          UpdateStatus.ready => (
              'Felt $v is ready',
              PillButton(
                label: 'Restart to update',
                style: PillStyle.filled,
                minWidth: 0,
                height: 30,
                onPressed: u.installNow,
              ),
            ),
          UpdateStatus.available => (
              'Felt $v is available',
              PillButton(
                label: 'Download',
                style: PillStyle.plain,
                minWidth: 0,
                height: 30,
                onPressed: () => openInBrowser(u.releasePageUrl),
              ),
            ),
          _ => ('', null),
        };
        if (text.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(CupertinoIcons.arrow_down_circle_fill, size: 16, color: p.accent),
            const SizedBox(width: 6),
            Text(text, style: Typo.callout(p.secondaryLabel)),
            if (action != null) ...[const SizedBox(width: Space.s), action],
          ]),
        );
      },
    );
  }
}
