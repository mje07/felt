import 'package:cupertino_ui/cupertino_ui.dart';

import '../app/bankroll.dart';
import '../app/drill_progress.dart';
import '../app/history_store.dart';
import '../app/settings.dart';
import '../app/sounds.dart';
import '../app/theme.dart';
import '../app/tournament_store.dart';
import '../app/updater.dart';
import '../app/version.dart';
import '../widgets/common.dart';
import '../widgets/controls.dart';
import '../widgets/playing_card.dart';
import 'panel_route.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key, this.history});

  /// Needed for the Data section (resetting hand history).
  final HistoryStore? history;

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final p = Palette.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsCard(
            title: 'Appearance',
            icon: CupertinoIcons.circle_lefthalf_fill,
            children: [
              ThemeSwatches(value: s.appearance, onChanged: (v) => s.update((s) => s.appearance = v)),
              SettingRow(
                label: 'Four-colour deck',
                detail: 'Blue diamonds and green clubs, so suits never blur together.',
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  // Suits shown on a card face, as they appear in play.
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                    decoration: BoxDecoration(
                      color: p.cardFace,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: p.separator, width: 0.5),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      for (var suit = 0; suit < 4; suit++)
                        Padding(
                          padding: EdgeInsets.only(right: suit == 3 ? 0 : 3),
                          child: SuitIcon(suit: suit, size: 12, color: suitColor(p, suit, s.fourColorDeck)),
                        ),
                    ]),
                  ),
                  const SizedBox(width: Space.m),
                  FeltToggle(
                    label: 'Four-colour deck',
                    value: s.fourColorDeck,
                    onChanged: (v) => s.update((s) => s.fourColorDeck = v),
                  ),
                ]),
              ),
            ],
          ),
          const SizedBox(height: Space.l),
          SettingsCard(
            title: 'Sound',
            icon: CupertinoIcons.speaker_2_fill,
            children: [
              SettingRow(
                label: 'Sound effects',
                trailing: FeltToggle(
                  label: 'Sound effects',
                  value: s.soundEnabled,
                  onChanged: (v) {
                    s.update((s) => s.soundEnabled = v);
                    if (v) SoundsScope.of(context).play(Sfx.chip);
                  },
                ),
              ),
              SettingRow(
                label: 'Volume',
                enabled: s.soundEnabled,
                trailing: SizedBox(
                  width: 200,
                  child: Row(children: [
                    Icon(CupertinoIcons.speaker_fill, size: 13, color: p.tertiaryLabel),
                    Expanded(
                      child: CupertinoSlider(
                        value: s.volume,
                        activeColor: p.accent,
                        onChanged: s.soundEnabled ? (v) => s.update((s) => s.volume = v) : null,
                        onChangeEnd: (_) => SoundsScope.of(context).play(Sfx.chip),
                      ),
                    ),
                    Icon(CupertinoIcons.speaker_3_fill, size: 13, color: p.tertiaryLabel),
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.l),
          SettingsCard(
            title: 'Gameplay',
            icon: CupertinoIcons.suit_spade_fill,
            children: [
              SettingRow(
                label: 'Speed',
                detail: 'How quickly cards, chips and opponents move.',
                trailing: ChoiceChips<GameSpeed>(
                  value: s.speed,
                  options: {for (final g in GameSpeed.values) g: g.label},
                  onChanged: (v) => s.update((s) => s.speed = v),
                ),
              ),
              SettingRow(
                label: 'Deal next hand automatically',
                trailing: FeltToggle(
                  label: 'Deal next hand automatically',
                  value: s.autoDeal,
                  onChanged: (v) => s.update((s) => s.autoDeal = v),
                ),
              ),
              SettingRow(
                label: 'Reduce motion',
                detail: 'Shorter, simpler animations.',
                trailing: FeltToggle(
                  label: 'Reduce motion',
                  value: s.reduceMotion,
                  onChanged: (v) => s.update((s) => s.reduceMotion = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.l),
          SettingsCard(
            title: 'Coach',
            icon: CupertinoIcons.lightbulb_fill,
            children: [
              SettingRow(
                label: 'Show coach at the table',
                detail: 'Accuracy and hand reviews. Your stats are recorded either way.',
                trailing: FeltToggle(
                  label: 'Show coach at the table',
                  value: s.showCoachAtTable,
                  onChanged: (v) => s.update((s) => s.showCoachAtTable = v),
                ),
              ),
              SettingRow(
                label: 'Grade each action live',
                detail: 'A grade badge on every decision as you make it.',
                enabled: s.showCoachAtTable,
                trailing: FeltToggle(
                  label: 'Grade each action live',
                  value: s.showGradesLive,
                  onChanged: s.showCoachAtTable ? (v) => s.update((s) => s.showGradesLive = v) : null,
                ),
              ),
            ],
          ),
          if (history != null) ...[
            const SizedBox(height: Space.l),
            _DataCard(history: history!),
          ],
          const SizedBox(height: Space.l),
          _UpdatesCard(settings: s),
          const SizedBox(height: Space.l),
          const SettingsCard(
            title: 'Keyboard',
            icon: CupertinoIcons.keyboard,
            children: [_Shortcuts()],
          ),
        ],
      ),
    );
  }
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts();

  static const _keys = [
    ('Fold', ['F']),
    ('Check / call', ['C']),
    ('Bet / raise', ['R']),
    ('Change bet size', ['↑', '↓']),
    ('Deal next hand', ['Space']),
    ('Answer a drill', ['1', '…', '5']),
  ];

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - Space.l) / 2;
      return Wrap(
        spacing: Space.l,
        runSpacing: Space.m,
        children: [
          for (final (label, keys) in _keys)
            SizedBox(
              width: w,
              child: Row(children: [
                Expanded(child: Text(label, style: Typo.callout(p.secondaryLabel))),
                for (final k in keys) ...[
                  const SizedBox(width: 4),
                  k == '…' ? Text('–', style: Typo.callout(p.tertiaryLabel)) : KeyCap(k),
                ],
              ]),
            ),
        ],
      );
    });
  }
}

class _DataCard extends StatefulWidget {
  const _DataCard({required this.history});
  final HistoryStore history;

  @override
  State<_DataCard> createState() => _DataCardState();
}

class _DataCardState extends State<_DataCard> {
  String? _done;

  Future<void> _resetHistory() async {
    final n = widget.history.hands.length;
    final ok = await confirmAction(
      context,
      title: 'Reset hand history?',
      message: 'This permanently deletes ${formatChips(n)} saved hand${n == 1 ? '' : 's'}, along with your '
          'statistics, player profile, coach grades and charts. This can\'t be undone.',
      action: 'Reset',
    );
    if (!ok) return;
    await widget.history.clear();
    if (mounted) setState(() => _done = 'Hand history and statistics were reset.');
  }

  Future<void> _resetTournaments() async {
    final ok = await confirmAction(
      context,
      title: 'Reset tournament results?',
      message: "This deletes your Sit & Go finishes, ROI and winnings history. This can't be undone.",
      action: 'Reset',
    );
    if (!ok) return;
    await TournamentStore.current.clear();
    if (mounted) setState(() => _done = 'Tournament results were reset.');
  }

  Future<void> _resetBankroll() async {
    final ok = await confirmAction(
      context,
      title: 'Reset your bankroll?',
      message: 'Your balance goes back to ${formatChips(Bankroll.startingBalance)} chips and its history is cleared.',
      action: 'Reset',
    );
    if (!ok) return;
    Bankroll.current.reset();
    if (mounted) setState(() => _done = 'Bankroll was reset.');
  }

  Future<void> _resetTraining() async {
    final ok = await confirmAction(
      context,
      title: 'Reset training progress?',
      message: 'This clears your drill accuracy and best streaks. This can\'t be undone.',
      action: 'Reset',
    );
    if (!ok) return;
    DrillProgress.current.reset();
    if (mounted) setState(() => _done = 'Training progress was reset.');
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final n = widget.history.hands.length;
    final answered = DrillProgress.current.records.values.fold(0, (a, r) => a + r.answered);
    Widget reset(VoidCallback? onTap) => PillButton(
          label: 'Reset…',
          style: PillStyle.destructive,
          minWidth: 0,
          height: 34,
          onPressed: onTap,
        );
    return SettingsCard(
      title: 'Data',
      icon: CupertinoIcons.tray_full_fill,
      children: [
        SettingRow(
          label: 'Hand history & stats',
          detail: n == 0 ? 'No hands saved' : '${formatChips(n)} hand${n == 1 ? '' : 's'} saved',
          trailing: reset(n > 0 ? _resetHistory : null),
        ),
        SettingRow(
          label: 'Training progress',
          detail: answered == 0 ? 'No drills answered yet' : '${formatChips(answered)} drill answers saved',
          trailing: reset(answered > 0 ? _resetTraining : null),
        ),
        SettingRow(
          label: 'Tournament results',
          detail: TournamentStore.current.results.isEmpty
              ? 'No Sit & Gos played yet'
              : '${TournamentStore.current.results.length} Sit & Go${TournamentStore.current.results.length == 1 ? '' : 's'} saved',
          trailing: reset(TournamentStore.current.results.isEmpty ? null : _resetTournaments),
        ),
        SettingRow(
          label: 'Bankroll',
          detail: '${formatChips(Bankroll.current.balance)} chips · resets to ${formatChips(Bankroll.startingBalance)}',
          trailing: reset(_resetBankroll),
        ),
        if (_done != null)
          Row(children: [
            Icon(CupertinoIcons.checkmark_alt, size: 14, color: p.positive),
            const SizedBox(width: 6),
            Text(_done!, style: Typo.callout(p.secondaryLabel)),
          ]),
      ],
    );
  }
}

/// Version, automatic updates and a manual check.
class _UpdatesCard extends StatelessWidget {
  const _UpdatesCard({required this.settings});
  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final u = Updater.current;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final v = u.latestVersion;
        final status = switch (u.status) {
          UpdateStatus.idle => 'You have Felt $appVersion.',
          UpdateStatus.checking => 'Checking for updates…',
          UpdateStatus.upToDate => "You're up to date.",
          UpdateStatus.downloading => 'Downloading Felt $v… ${(u.progress * 100).round()}%',
          UpdateStatus.ready => 'Felt $v is downloaded and installs when you restart.',
          UpdateStatus.available => Updater.canSelfUpdate
              ? 'Felt $v is available to download.'
              : 'Felt $v is available. This copy wasn\'t installed with Setup, so update it yourself.',
          UpdateStatus.failed => "Couldn't check for updates. Are you online?",
        };
        final Widget action = switch (u.status) {
          UpdateStatus.ready => PillButton(
              label: 'Restart to update', style: PillStyle.filled, minWidth: 0, height: 34, onPressed: u.installNow),
          UpdateStatus.available => PillButton(
              label: 'Download',
              style: PillStyle.tinted,
              minWidth: 0,
              height: 34,
              onPressed: () => openInBrowser(u.releasePageUrl)),
          _ => PillButton(
              label: 'Check now',
              style: PillStyle.tinted,
              minWidth: 0,
              height: 34,
              onPressed: u.enabled && u.status != UpdateStatus.checking && u.status != UpdateStatus.downloading
                  ? u.check
                  : null),
        };
        return SettingsCard(
          title: 'Updates',
          icon: CupertinoIcons.arrow_down_circle_fill,
          children: [
            SettingRow(
              label: 'Update automatically',
              detail: 'Checks GitHub for new versions and installs them when Felt starts. '
                  'Nothing about you or your games is sent.',
              trailing: FeltToggle(
                label: 'Update automatically',
                value: settings.autoUpdate,
                onChanged: (on) {
                  settings.update((s) => s.autoUpdate = on);
                  if (on) u.check();
                },
              ),
            ),
            SettingRow(label: 'Felt $appVersion', detail: status, trailing: action),
          ],
        );
      },
    );
  }
}
