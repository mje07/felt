import 'dart:isolate';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:poker_engine/poker_engine.dart';

import '../app/theme.dart';
import '../widgets/common.dart';
import '../widgets/controls.dart';
import '../widgets/playing_card.dart';
import '../widgets/review_panel.dart';

/// One frame of a replay: the table after an event.
class ReplayFrame {
  ReplayFrame({
    required this.stacks,
    required this.bets,
    required this.folded,
    required this.lastAction,
    required this.board,
    required this.pot,
    required this.caption,
    required this.street,
    this.actor,
    this.review,
    this.revealed = const {},
    this.winners = const {},
  });
  final List<int> stacks, bets;
  final Set<int> folded;
  final Map<int, String> lastAction;
  final List<int> board;
  final int pot;
  final String caption;
  final Street street;
  final int? actor;
  final DecisionReview? review;
  final Map<int, List<int>> revealed;
  final Map<int, int> winners;
}

/// Turns a hand's event log into frames.
List<ReplayFrame> buildReplay(HandHistory h) {
  final start = h.events.firstWhere((e) => e['e'] == 'start');
  final seats = [for (final s in start['seats'] as List) (s as Map).cast<String, Object?>()];
  final names = [for (final s in seats) s['name'] as String];
  final hero = h.heroSeat;
  String who(int seat) => seat == hero ? 'You' : names[seat];
  final stacks = [for (final s in seats) s['stack'] as int];
  final bets = List<int>.filled(seats.length, 0);
  final folded = <int>{};
  final last = <int, String>{};
  final board = <int>[];
  var pot = 0;
  var street = Street.preflop;
  final revealed = <int, List<int>>{};
  final winners = <int, int>{};
  final frames = <ReplayFrame>[];
  var reviewIndex = 0;
  void frame(String caption, {int? actor, DecisionReview? review}) => frames.add(ReplayFrame(
        stacks: List.of(stacks),
        bets: List.of(bets),
        folded: {...folded},
        lastAction: {...last},
        board: List.of(board),
        pot: pot,
        caption: caption,
        street: street,
        actor: actor,
        review: review,
        revealed: {...revealed},
        winners: {...winners},
      ));

  frame('${names.length} players · blinds ${start['sb']}/${start['bb']}');
  for (final e in h.events) {
    final seat = e['seat'] as int?;
    switch (e['e']) {
      case 'ante':
        final a = e['amount'] as int;
        stacks[seat!] -= a;
        pot += a;
      case 'blind':
        final a = e['amount'] as int;
        stacks[seat!] -= a;
        bets[seat] += a;
        pot += a;
        last[seat] = e['big'] == true ? 'Big blind' : 'Small blind';
        frame('${who(seat)} ${e['big'] == true ? 'post the big blind' : 'post the small blind'}'
            .replaceFirst('${names[seat]} post', '${names[seat]} posts'));
      case 'street':
        street = Street.values.byName(e['street'] as String);
        board.addAll([for (final c in e['cards'] as List) c as int]);
        bets.fillRange(0, bets.length, 0);
        last.removeWhere((k, v) => !v.startsWith('All-in') && v != 'Fold');
        frame('${street.name[0].toUpperCase()}${street.name.substring(1)}: ${cardsToString(board)}');
      case 'act':
        final added = e['added'] as int, to = e['to'] as int;
        stacks[seat!] -= added;
        bets[seat] = to;
        pot += added;
        final type = e['type'] as String;
        if (type == 'fold') folded.add(seat);
        final label = switch (type) {
          'fold' => 'Fold',
          'check' => 'Check',
          'call' => 'Call $added',
          'bet' => 'Bet $to',
          _ => 'Raise to $to',
        };
        last[seat] = e['allIn'] == true ? 'All-in $to' : label;
        DecisionReview? review;
        if (seat == hero && reviewIndex < h.reviews.length && h.reviews[reviewIndex].street.name == e['street']) {
          review = h.reviews[reviewIndex++];
        }
        frame('${who(seat)} ${label.toLowerCase()}${e['allIn'] == true ? ' (all-in)' : ''}', actor: seat, review: review);
      case 'uncalled':
        final a = e['amount'] as int;
        stacks[seat!] += a;
        bets[seat] -= a;
        pot -= a;
      case 'showdown':
        final hands = (e['hands'] as Map).cast<String, Object?>();
        for (final entry in hands.entries) {
          revealed[int.parse(entry.key)] = [for (final c in ((entry.value as Map)['hole'] as List)) c as int];
        }
        frame('Showdown');
      case 'award':
        final shares = (e['shares'] as Map).cast<String, Object?>();
        for (final entry in shares.entries) {
          final s = int.parse(entry.key), a = entry.value as int;
          stacks[s] += a;
          winners[s] = (winners[s] ?? 0) + a;
        }
        pot = 0;
        bets.fillRange(0, bets.length, 0);
        frame(h.summary.isEmpty ? 'Hand over' : h.summary);
    }
  }
  return frames;
}

/// The player's equity at the start of each street they reached, against
/// the hands shown at showdown or, failing that, any two cards.
Future<List<(Street, double)>> equityTimeline(HandHistory h) {
  final hole = h.heroHole;
  if (hole == null) return Future.value(const []);
  final shown = <List<int>>[];
  for (final e in h.events) {
    if (e['e'] != 'showdown') continue;
    for (final entry in (e['hands'] as Map).entries) {
      if (int.parse(entry.key as String) != h.heroSeat) {
        shown.add([for (final c in ((entry.value as Map)['hole'] as List)) c as int]);
      }
    }
  }
  final boards = <(Street, List<int>)>[(Street.preflop, const [])];
  final running = <int>[];
  for (final e in h.events) {
    if (e['e'] == 'street') {
      running.addAll([for (final c in e['cards'] as List) c as int]);
      boards.add((Street.values.byName(e['street'] as String), List.of(running)));
    }
  }
  return _equities(hole, shown, boards);
}

Future<List<(Street, double)>> _equities(List<int> hole, List<List<int>> shown, List<(Street, List<int>)> boards) =>
    Isolate.run(() {
      WeightedRange one(List<int> c) => WeightedRange()..[comboIndex(c[0], c[1])] = 1;
      final villains = shown.isEmpty ? [WeightedRange.full()] : [for (final s in shown.take(3)) one(s)];
      return [
        for (final (street, board) in boards)
          (street, rangeVsRange([one(hole), ...villains], board, samples: 20000).equity.first),
      ];
    });

class ReplayerScreen extends StatefulWidget {
  const ReplayerScreen({super.key, required this.hand});
  final HandHistory hand;

  @override
  State<ReplayerScreen> createState() => _ReplayerScreenState();
}

class _ReplayerScreenState extends State<ReplayerScreen> {
  late final List<ReplayFrame> _frames = buildReplay(widget.hand);
  late final Future<List<(Street, double)>> _equity = equityTimeline(widget.hand);
  int _i = 0;

  void _go(int i) => setState(() => _i = i.clamp(0, _frames.length - 1));

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final h = widget.hand;
    final f = _frames[_i];
    final start = h.events.firstWhere((e) => e['e'] == 'start');
    final names = [for (final s in start['seats'] as List) (s as Map)['name'] as String];
    final button = start['button'] as int;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(_i + 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(_i - 1),
        const SingleActivator(LogicalKeyboardKey.home): () => _go(0),
        const SingleActivator(LogicalKeyboardKey.end): () => _go(_frames.length - 1),
      },
      child: Focus(
        autofocus: true,
        child: CupertinoPageScaffold(
          backgroundColor: p.isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
          child: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.xl, 0),
                child: Row(children: [
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Row(children: [
                      Icon(CupertinoIcons.chevron_left, size: 18, color: p.accent),
                      const SizedBox(width: 2),
                      Text('Back', style: Typo.body(p.accent)),
                    ]),
                  ),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(Space.xxl, Space.s, Space.xxl, Space.xxl),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('Hand replay', style: Typo.largeTitle(p.label)),
                        const SizedBox(height: Space.xs),
                        Text(
                          '${h.isImported ? '${h.source} #${h.sourceId}' : 'Hand #${h.handNumber}'} · '
                          '${h.playedAt.toLocal().toString().substring(0, 16)}',
                          style: Typo.body(p.secondaryLabel),
                        ),
                        const SizedBox(height: Space.l),
                        _Table(frame: f, names: names, hero: h.heroSeat, heroHole: h.heroHole, button: button),
                        const SizedBox(height: Space.m),
                        Row(children: [
                          IconPill(icon: CupertinoIcons.backward_end_fill, tooltip: 'Start', onPressed: _i > 0 ? () => _go(0) : null),
                          const SizedBox(width: Space.s),
                          IconPill(icon: CupertinoIcons.chevron_left, tooltip: 'Back one step (←)', onPressed: _i > 0 ? () => _go(_i - 1) : null),
                          const SizedBox(width: Space.s),
                          IconPill(
                              icon: CupertinoIcons.chevron_right,
                              tooltip: 'Next step (→)',
                              onPressed: _i < _frames.length - 1 ? () => _go(_i + 1) : null),
                          const SizedBox(width: Space.s),
                          IconPill(
                              icon: CupertinoIcons.forward_end_fill,
                              tooltip: 'End',
                              onPressed: _i < _frames.length - 1 ? () => _go(_frames.length - 1) : null),
                          const SizedBox(width: Space.l),
                          Expanded(child: Text(f.caption, style: Typo.headline(p.label))),
                          Text('${_i + 1} / ${_frames.length}', style: Typo.number(p.secondaryLabel, size: 13)),
                        ]),
                        const SizedBox(height: Space.m),
                        if (f.review != null) ...[
                          GlassPanel(
                            padding: const EdgeInsets.all(Space.l),
                            child: HandReviewList(reviews: [f.review!], hole: h.heroHole),
                          ),
                          const SizedBox(height: Space.m),
                        ],
                        FutureBuilder<List<(Street, double)>>(
                          future: _equity,
                          builder: (context, snap) {
                            final data = snap.data;
                            if (data == null || data.isEmpty) return const SizedBox.shrink();
                            return SettingsCard(
                              title: 'Your equity by street',
                              icon: CupertinoIcons.chart_bar_fill,
                              color: p.surface,
                              children: [
                                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  for (final (street, eq) in data)
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 6),
                                        child: Column(children: [
                                          Text('${(eq * 100).round()}%', style: Typo.number(p.label, size: 14)),
                                          const SizedBox(height: 4),
                                          Container(
                                            height: 90 * eq + 2,
                                            decoration: BoxDecoration(
                                              color: street == f.street ? p.accent : p.accent.withValues(alpha: 0.35),
                                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(street.name[0].toUpperCase() + street.name.substring(1),
                                              style: Typo.caption(p.secondaryLabel)),
                                        ]),
                                      ),
                                    ),
                                ]),
                                Text(
                                  h.events.any((e) => e['e'] == 'showdown')
                                      ? 'Against the hands shown at showdown.'
                                      : 'Against a random hand (nobody showed their cards).',
                                  style: Typo.caption(p.tertiaryLabel),
                                ),
                              ],
                            );
                          },
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.frame, required this.names, required this.hero, required this.heroHole, required this.button});
  final ReplayFrame frame;
  final List<String> names;
  final int hero, button;
  final List<int>? heroHole;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final f = frame;
    Widget seat(int i) {
      final out = f.folded.contains(i);
      final cards = i == hero ? heroHole : f.revealed[i];
      final acting = f.actor == i;
      return AnimatedOpacity(
        duration: Motion.fast,
        opacity: out ? 0.45 : 1,
        child: Container(
          width: 150,
          padding: const EdgeInsets.all(Space.s),
          decoration: BoxDecoration(
            color: const Color(0x33000000),
            borderRadius: BorderRadius.circular(Radii.m),
            border: Border.all(color: acting ? const Color(0xFFFFFFFF) : const Color(0x26FFFFFF), width: acting ? 1.5 : 1),
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var k = 0; k < 2; k++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: PlayingCard(card: cards?[k], width: 30, faceUp: cards != null),
                ),
            ]),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (i == button)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(6)),
                  child: Text('D', style: Typo.caption(const Color(0xFF1D1D1F)).copyWith(fontWeight: FontWeight.w700)),
                ),
              Flexible(
                child: Text(i == hero ? 'You' : names[i],
                    overflow: TextOverflow.ellipsis, style: Typo.callout(const Color(0xFFFFFFFF))),
              ),
            ]),
            Text(formatChips(f.stacks[i]), style: Typo.number(const Color(0xCCFFFFFF), size: 12)),
            const SizedBox(height: 2),
            Text(
              f.winners.containsKey(i)
                  ? 'Wins ${formatChips(f.winners[i]!)}'
                  : (f.lastAction[i] ?? (f.bets[i] > 0 ? 'Bet ${f.bets[i]}' : '')),
              style: Typo.caption(f.winners.containsKey(i) ? const Color(0xFFFFD60A) : const Color(0xB3FFFFFF)),
            ),
          ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xl),
        gradient: RadialGradient(colors: [p.feltCenter, p.feltEdge], radius: 1.2),
      ),
      child: Column(children: [
        Wrap(alignment: WrapAlignment.center, spacing: Space.s, runSpacing: Space.s, children: [
          for (var i = 0; i < names.length; i++) if (i != hero) seat(i),
        ]),
        const SizedBox(height: Space.l),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var k = 0; k < 5; k++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: k < f.board.length
                  ? PlayingCard(card: f.board[k], width: 50)
                  : Container(
                      width: 50,
                      height: 70,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0x33FFFFFF)),
                      ),
                    ),
            ),
        ]),
        const SizedBox(height: 6),
        Text('POT ${formatChips(f.pot)}',
            style: Typo.caption(const Color(0xCCFFFFFF)).copyWith(letterSpacing: 1, fontWeight: FontWeight.w600)),
        const SizedBox(height: Space.l),
        seat(hero),
      ]),
    );
  }
}
