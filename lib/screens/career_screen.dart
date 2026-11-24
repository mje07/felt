import 'package:cupertino_ui/cupertino_ui.dart';

import '../app/bankroll.dart';
import '../app/career.dart';
import '../app/controller.dart';
import '../app/events.dart';
import '../app/history_store.dart';
import '../app/skills.dart';
import '../app/theme.dart';
import '../widgets/common.dart';
import '../widgets/controls.dart';
import 'lesson_screen.dart';
import 'panel_route.dart';
import 'table_screen.dart';

const _careerStakes = [(1, 2), (5, 10), (25, 50), (100, 200)];

/// Career mode: a separate bankroll that climbs from micro stakes to The
/// Big One. Promotion needs chips and skill.
class CareerScreen extends StatelessWidget {
  const CareerScreen({super.key, this.history});

  /// Hand history to save career hands to (defaults to a fresh in-memory
  /// store in tests).
  final HistoryStore? history;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final career = Career.current;
    final bank = Bankroll.career;
    return CupertinoPageScaffold(
      backgroundColor: p.isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      child: SafeArea(
        child: Column(
          children: [
            backRow(context),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([career, bank, SkillRatings.current]),
                builder: (context, _) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(Space.xxl, Space.s, Space.xxl, Space.xxl),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: career.started ? _career(context, p, career, bank) : _intro(context, p, career),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _intro(BuildContext context, Palette p, Career career) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Career mode', style: Typo.largeTitle(p.label)),
      const SizedBox(height: Space.s),
      Text(
        'Start at micro stakes with ${formatChips(Career.startingBankroll)} chips in a bankroll of its own. '
        'Win to grow it, train to raise your skill ratings, and get promoted through ${careerStages.length} stages '
        'until you can sit down in The Big One.',
        style: Typo.body(p.secondaryLabel).copyWith(fontSize: 17, height: 1.5),
      ),
      const SizedBox(height: Space.xl),
      _Ladder(stage: -1),
      const SizedBox(height: Space.xl),
      PillButton(label: 'Start my career', style: PillStyle.filled, onPressed: career.start),
    ],
  );

  Widget _career(BuildContext context, Palette p, Career career, Bankroll bank) {
    final stage = career.stageInfo;
    final missing = career.missingFor(bankroll: bank, ratings: SkillRatings.current);
    final store = history ?? HistoryStore.memory();
    void play(TableConfig config) => Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => TableScreen(config: config, history: store, bankroll: Bankroll.career),
      ),
    );
    final events = [
      for (final e in tournamentEvents)
        if (career.allowsEvent(e.name)) e,
    ];
    final sngs = [
      for (final b in sngBuyIns)
        if (career.allowsSng(b)) b,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CAREER · STAGE ${career.stage + 1} OF ${careerStages.length}',
                    style: Typo.caption(p.secondaryLabel).copyWith(letterSpacing: 1),
                  ),
                  Text(stage.name, style: Typo.largeTitle(p.label)),
                  Text(stage.blurb, style: Typo.body(p.secondaryLabel)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('CAREER BANKROLL', style: Typo.caption(p.secondaryLabel).copyWith(letterSpacing: 1)),
                Text(formatChips(bank.balance), style: Typo.number(p.label, size: 28, weight: FontWeight.w700)),
              ],
            ),
          ],
        ),
        const SizedBox(height: Space.l),
        _Ladder(stage: career.stage),
        const SizedBox(height: Space.l),
        SettingsCard(
          title: career.next == null
              ? (career.champion ? 'Champion' : 'The final goal')
              : 'Promotion to ${career.next!.name}',
          icon: CupertinoIcons.arrow_up_circle_fill,
          color: p.surface,
          children: [
            if (missing == null)
              Text(
                career.champion ? 'You won The Big One. Hall of fame.' : 'Win The Big One to complete your career.',
                style: Typo.body(p.label),
              )
            else ...[
              _Requirement(
                label: 'Bankroll',
                value: '${formatChips(bank.balance)} of ${formatChips(stage.promoteAt!)}',
                progress: bank.balance / stage.promoteAt!,
              ),
              _Requirement(
                label: 'Average skill',
                value: '${SkillRatings.current.average.round()} of ${stage.minRating.round()}',
                progress:
                    (SkillRatings.current.average - SkillRatings.startRating) /
                    (stage.minRating - SkillRatings.startRating),
              ),
              if (missing.isEmpty)
                PillButton(label: 'Get promoted', style: PillStyle.filled, onPressed: career.promote)
              else
                Text('Still needed: ${missing.join(' and ')}.', style: Typo.callout(p.secondaryLabel)),
            ],
          ],
        ),
        const SizedBox(height: Space.l),
        SettingsCard(
          title: 'Play',
          icon: CupertinoIcons.suit_spade_fill,
          color: p.surface,
          children: [
            SettingRow(
              label: 'Cash games',
              detail: 'Stakes open at your stage',
              below: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < _careerStakes.length; i++)
                    if (career.allowsStake(i))
                      PillButton(
                        label: '${_careerStakes[i].$1}/${_careerStakes[i].$2}',
                        sublabel: 'Buy-in ${formatChips(_careerStakes[i].$2 * 100)}',
                        style: PillStyle.tinted,
                        minWidth: 0,
                        onPressed: bank.canAfford(_careerStakes[i].$2 * 100)
                            ? () => play(TableConfig(smallBlind: _careerStakes[i].$1, bigBlind: _careerStakes[i].$2))
                            : null,
                      ),
                ],
              ),
            ),
            SettingRow(
              label: 'Sit & Go',
              detail: '6 players, turbo',
              below: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final b in sngs)
                    PillButton(
                      label: formatChips(b),
                      style: PillStyle.tinted,
                      minWidth: 0,
                      onPressed: bank.canAfford(b)
                          ? () => play(TableConfig(mode: GameMode.sitAndGo, sngBuyIn: b))
                          : null,
                    ),
                ],
              ),
            ),
            SettingRow(
              label: 'Tournaments',
              below: Column(
                children: [
                  for (final e in events)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: SettingRow(
                        label: e.name,
                        detail: '${e.field} players · pool ${formatChips(e.prizePool)}',
                        trailing: PillButton(
                          label: e.isFreeroll ? 'Free' : formatChips(e.buyIn),
                          style: PillStyle.tinted,
                          minWidth: 0,
                          height: 32,
                          onPressed: bank.canAfford(e.buyIn)
                              ? () => play(
                                  TableConfig(
                                    mode: GameMode.mtt,
                                    mttField: e.field,
                                    mttBuyIn: e.buyIn,
                                    mttGuarantee: e.guarantee,
                                    eventName: e.name,
                                    speed: e.speed,
                                    startingStack: e.stack,
                                    style: 'random',
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (bank.balance < 200)
              Text(
                'Your career bankroll is almost empty. Try the freeroll, or restart your career.',
                style: Typo.callout(p.destructive),
              ),
          ],
        ),
        const SizedBox(height: Space.l),
        PillButton(
          label: 'Restart career',
          style: PillStyle.plain,
          onPressed: () async {
            final ok = await confirmAction(
              context,
              title: 'Restart your career?',
              message:
                  'You go back to Rookie with ${formatChips(Career.startingBankroll)} chips. Achievements and '
                  'skill ratings are kept.',
              action: 'Restart',
            );
            if (ok) career.restart(Bankroll.career);
          },
        ),
      ],
    );
  }
}

class _Requirement extends StatelessWidget {
  const _Requirement({required this.label, required this.value, required this.progress});
  final String label, value;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final done = progress >= 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: Typo.callout(p.label))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: p.separator)),
                    FractionallySizedBox(
                      heightFactor: 1,
                      widthFactor: progress.clamp(0.02, 1.0),
                      child: ColoredBox(color: done ? p.positive : p.accent),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 170,
            child: Text(value, textAlign: TextAlign.right, style: Typo.number(p.secondaryLabel, size: 12)),
          ),
        ],
      ),
    );
  }
}

/// The six stages, with the current one highlighted.
class _Ladder extends StatelessWidget {
  const _Ladder({required this.stage});
  final int stage;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(
      children: [
        for (final (i, s) in careerStages.indexed) ...[
          if (i > 0) Expanded(child: Container(height: 2, color: i <= stage ? p.accent : p.separator)),
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < stage ? p.accent : (i == stage ? p.accent.withValues(alpha: 0.18) : p.surface),
                  border: Border.all(color: i <= stage ? p.accent : p.separator, width: 2),
                ),
                child: i < stage
                    ? const Icon(CupertinoIcons.checkmark, size: 14, color: Color(0xFFFFFFFF))
                    : Center(child: Text('${i + 1}', style: Typo.caption(i == stage ? p.accent : p.secondaryLabel))),
              ),
              const SizedBox(height: 4),
              Text(s.name, style: Typo.caption(i == stage ? p.label : p.secondaryLabel)),
            ],
          ),
        ],
      ],
    );
  }
}
