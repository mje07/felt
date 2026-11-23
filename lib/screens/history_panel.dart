import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';

import '../app/history_store.dart';
import '../app/theme.dart';
import '../widgets/playing_card.dart';
import '../widgets/review_panel.dart';

/// Converts a stored event log into readable lines. The hero is "You", with
/// second-person verbs ("You raise to 30").
List<String> describeHistory(HandHistory h) {
  final names = <int, String>{};
  final lines = <String>[];
  bool me(Object? seat) => seat == h.heroSeat;
  String who(Object? seat) => me(seat) ? 'You' : (names[seat] ?? 'Seat $seat');
  // Third-person verb for opponents, base form for you.
  String act(Object? seat, String verb) => '${who(seat)} ${me(seat) ? verb : _third(verb)}';

  for (final e in h.events) {
    switch (e['e']) {
      case 'start':
        for (final s in (e['seats'] as List).cast<Map>()) {
          names[s['index'] as int] = s['name'] as String;
        }
        lines.add('Blinds ${e['sb']}/${e['bb']} · ${me(e['button']) ? 'You have' : '${who(e['button'])} has'} the button');
      case 'blind':
        lines.add('${act(e['seat'], 'post')} ${e['big'] == true ? 'big' : 'small'} blind ${e['amount']}');
      case 'deal':
        final hole = h.heroHole;
        if (hole != null && hole.length == 2) lines.add('Dealt to you: ${cardsToString(hole)}');
      case 'act':
        final seat = e['seat'];
        final to = e['to'];
        final suffix = e['allIn'] == true ? ' (all-in)' : '';
        lines.add(switch (e['type']) {
          'fold' => act(seat, 'fold'),
          'check' => act(seat, 'check'),
          'call' => '${act(seat, 'call')} ${e['added']}$suffix',
          'bet' => '${act(seat, 'bet')} $to$suffix',
          _ => '${act(seat, 'raise')} to $to$suffix',
        });
      case 'street':
        final street = (e['street'] as String);
        lines.add('${street[0].toUpperCase()}${street.substring(1)}: ${cardsToString((e['cards'] as List).cast<int>())}');
      case 'uncalled':
        lines.add('Uncalled ${e['amount']} returned to ${me(e['seat']) ? 'you' : who(e['seat'])}');
      case 'showdown':
        for (final entry in (e['hands'] as Map).entries) {
          final v = entry.value as Map;
          lines.add('${act(int.parse(entry.key as String), 'show')} '
              '${cardsToString((v['hole'] as List).cast<int>())} — ${describeHand(v['value'] as int)}');
        }
      case 'award':
        for (final entry in (e['shares'] as Map).entries) {
          lines.add('${act(int.parse(entry.key as String), 'win')} ${entry.value}');
        }
    }
  }
  return lines;
}

String _third(String verb) => verb.endsWith('sh') || verb.endsWith('ch') ? '${verb}es' : '${verb}s';

class HistoryPanel extends StatefulWidget {
  const HistoryPanel({super.key, required this.store});
  final HistoryStore store;

  @override
  State<HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<HistoryPanel> {
  int? _open;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final hands = widget.store.hands.reversed.take(100).toList();
    final total = widget.store.hands.fold(0, (a, h) => a + h.heroNet);
    final won = widget.store.hands.where((h) => h.heroNet > 0).length;
    if (hands.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Text('Hands you play will appear here.', style: Typo.body(p.secondaryLabel)),
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: Space.l),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.s),
          child: Row(
            children: [
              _Stat('Hands', formatChips(widget.store.hands.length)),
              _Stat('Won', formatChips(won)),
              _Stat('Net', '${total >= 0 ? '+' : ''}${formatChips(total)}',
                  color: total >= 0 ? p.positive : p.destructive),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          child: Container(
            decoration: BoxDecoration(
              color: p.isDark ? const Color(0xFF242426) : const Color(0xFFF7F7F9),
              borderRadius: BorderRadius.circular(Radii.l),
              border: Border.all(color: p.separator, width: 0.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, h) in hands.indexed) ...[
                  if (i > 0) Container(height: 0.5, color: p.separator, margin: const EdgeInsets.only(left: Space.l)),
                  _HandRow(
                    hand: h,
                    open: _open == h.handNumber,
                    onTap: () => setState(() => _open = _open == h.handNumber ? null : h.handNumber),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.color});
  final String label, value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: Typo.caption(p.secondaryLabel).copyWith(letterSpacing: 0.8)),
          const SizedBox(height: 2),
          Text(value, style: Typo.number(color ?? p.label, size: 22, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _HandRow extends StatefulWidget {
  const _HandRow({required this.hand, required this.open, required this.onTap});
  final HandHistory hand;
  final bool open;
  final VoidCallback onTap;

  @override
  State<_HandRow> createState() => _HandRowState();
}

class _HandRowState extends State<_HandRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final h = widget.hand;
    final net = h.heroNet;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          color: _hover && !widget.open ? (p.isDark ? const Color(0x0DFFFFFF) : const Color(0x08000000)) : const Color(0x00000000),
          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                if (h.heroHole != null && h.heroHole!.length == 2) ...[
                  for (final c in h.heroHole!)
                    Padding(padding: const EdgeInsets.only(right: 3), child: PlayingCard(card: c, width: 22)),
                  const SizedBox(width: Space.s),
                ],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Hand #${h.handNumber}', style: Typo.body(p.label).copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 1),
                    Text(
                      // Older records said "You wins".
                      (h.reviews.isEmpty ? h.summary : '${reviewSummary(h.reviews)} · ${h.summary}')
                          .replaceAll('You wins', 'You win'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Typo.caption(p.secondaryLabel).copyWith(fontSize: 12),
                    ),
                  ]),
                ),
                const SizedBox(width: Space.m),
                Text(
                  net == 0 ? '—' : '${net > 0 ? '+' : '−'}${formatChips(net.abs())}',
                  style: Typo.number(net > 0 ? p.positive : (net < 0 ? p.destructive : p.tertiaryLabel), size: 14),
                ),
                const SizedBox(width: Space.s),
                AnimatedRotation(
                  turns: widget.open ? 0.25 : 0,
                  duration: Motion.fast,
                  child: Icon(CupertinoIcons.chevron_right, size: 13, color: p.tertiaryLabel),
                ),
              ]),
              AnimatedSize(
                duration: Motion.medium,
                curve: Motion.spring,
                alignment: Alignment.topCenter,
                child: !widget.open
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: Space.m),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          for (final l in describeHistory(h))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1.5),
                              child: Text(l, style: Typo.callout(p.secondaryLabel)),
                            ),
                          if (h.reviews.isNotEmpty) ...[
                            const SizedBox(height: Space.l),
                            Row(children: [
                              Icon(CupertinoIcons.lightbulb_fill, size: 14, color: p.accent),
                              const SizedBox(width: 6),
                              Text('Coach', style: Typo.headline(p.label)),
                            ]),
                            const SizedBox(height: Space.s),
                            HandReviewList(reviews: h.reviews),
                          ],
                        ]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
