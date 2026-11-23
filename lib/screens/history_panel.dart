import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';

import '../app/history_store.dart';
import '../app/theme.dart';
import '../widgets/review_panel.dart';

/// Converts a stored event log into readable lines.
List<String> describeHistory(HandHistory h) {
  final names = <int, String>{};
  final lines = <String>[];
  for (final e in h.events) {
    switch (e['e']) {
      case 'start':
        for (final s in (e['seats'] as List).cast<Map>()) {
          names[s['index'] as int] = s['name'] as String;
        }
        lines.add('Blinds ${e['sb']}/${e['bb']} · ${names[e['button']]} has the button');
      case 'blind':
        lines.add('${names[e['seat']]} posts ${e['big'] == true ? 'big' : 'small'} blind ${e['amount']}');
      case 'deal':
        final hole = h.heroHole;
        if (hole != null && hole.length == 2) lines.add('Dealt to you: ${cardsToString(hole)}');
      case 'act':
        final who = names[e['seat']];
        final type = e['type'];
        final to = e['to'];
        final suffix = e['allIn'] == true ? ' (all-in)' : '';
        lines.add(switch (type) {
          'fold' => '$who folds',
          'check' => '$who checks',
          'call' => '$who calls ${e['added']}$suffix',
          'bet' => '$who bets $to$suffix',
          _ => '$who raises to $to$suffix',
        });
      case 'street':
        final street = (e['street'] as String);
        lines.add('${street[0].toUpperCase()}${street.substring(1)}: ${cardsToString((e['cards'] as List).cast<int>())}');
      case 'uncalled':
        lines.add('Uncalled ${e['amount']} returned to ${names[e['seat']]}');
      case 'showdown':
        for (final entry in (e['hands'] as Map).entries) {
          final v = entry.value as Map;
          lines.add('${names[int.parse(entry.key as String)]} shows '
              '${cardsToString((v['hole'] as List).cast<int>())} — ${describeHand(v['value'] as int)}');
        }
      case 'award':
        for (final entry in (e['shares'] as Map).entries) {
          lines.add('${names[int.parse(entry.key as String)]} wins ${entry.value}');
        }
    }
  }
  return lines;
}

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
        CupertinoListSection.insetGrouped(
          children: [
            for (final h in hands)
              CupertinoListTile(
                onTap: () => setState(() => _open = _open == h.handNumber ? null : h.handNumber),
                title: Text('Hand #${h.handNumber}'),
                subtitle: _open == h.handNumber
                    ? Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final l in describeHistory(h))
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 1.5),
                                child: Text(l, style: Typo.callout(p.secondaryLabel)),
                              ),
                            if (h.reviews.isNotEmpty) ...[
                              const SizedBox(height: Space.m),
                              Text('COACH', style: Typo.caption(p.secondaryLabel).copyWith(letterSpacing: 0.8)),
                              const SizedBox(height: Space.s),
                              HandReviewList(reviews: h.reviews),
                            ],
                          ],
                        ),
                      )
                    : Text(h.reviews.isEmpty ? h.summary : '${reviewSummary(h.reviews)} · ${h.summary}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text(
                  h.heroNet == 0 ? '—' : '${h.heroNet > 0 ? '+' : ''}${formatChips(h.heroNet)}',
                  style: Typo.number(h.heroNet > 0 ? p.positive : (h.heroNet < 0 ? p.destructive : p.tertiaryLabel),
                      size: 14),
                ),
              ),
          ],
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
