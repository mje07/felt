import 'dart:math';

import '../bots/bot.dart';
import '../card.dart';
import '../coach/advisor.dart';
import '../coach/review.dart';
import '../evaluator.dart';
import '../game_state.dart';
import '../history.dart';
import '../rules.dart';

/// Result of importing hand-history text.
class ImportResult {
  ImportResult(this.hands, this.skipped, this.site);

  /// Hands that replayed cleanly, oldest first.
  final List<HandHistory> hands;

  /// Why other hands were left out (one entry per hand).
  final List<String> skipped;

  /// 'PokerStars', 'GGPoker' or null if nothing was recognised.
  final String? site;
}

/// Imports No-Limit Hold'em hands from PokerStars or GGPoker hand-history
/// text. Each hand is replayed through Felt's rules engine to check it and
/// to rebuild every decision; results (including rake and mucked hands)
/// come from the hand history's own "collected" lines.
///
/// With [review], each of the player's decisions is graded by the coach
/// (slower). [onProgress] reports hands done out of the total.
ImportResult importHandHistories(String text,
    {bool review = false, int samples = 600, void Function(int done, int total)? onProgress, Random? rng}) {
  final blocks = splitHands(text);
  final hands = <HandHistory>[];
  final skipped = <String>[];
  String? site;
  for (var i = 0; i < blocks.length; i++) {
    try {
      final parsed = _parse(blocks[i]);
      site ??= parsed.site;
      hands.add(_replay(parsed, review: review, samples: samples, rng: rng ?? Random(i)));
    } on _Skip catch (e) {
      skipped.add(e.reason);
    } catch (e) {
      skipped.add('Could not read hand ${i + 1} ($e)');
    }
    onProgress?.call(i + 1, blocks.length);
  }
  // Oldest first; hands with the same time keep their order in the file.
  final order = {for (var i = 0; i < hands.length; i++) hands[i]: i};
  hands.sort((a, b) {
    final c = a.playedAt.compareTo(b.playedAt);
    return c != 0 ? c : order[a]!.compareTo(order[b]!);
  });
  return ImportResult(hands, skipped, site);
}

final _header = RegExp(r'^(PokerStars (Zoom )?(Hand|Game) #|Poker Hand #)', multiLine: true);

/// Splits a file into one text block per hand.
List<String> splitHands(String text) {
  final t = text.replaceAll('\r\n', '\n').replaceAll('﻿', '');
  final starts = [for (final m in _header.allMatches(t)) m.start];
  return [
    for (var i = 0; i < starts.length; i++) t.substring(starts[i], i + 1 < starts.length ? starts[i + 1] : t.length).trim(),
  ];
}

class _Skip implements Exception {
  _Skip(this.reason);
  final String reason;
}

class _Action {
  _Action(this.name, this.type, this.amount, this.street);
  final String name;
  final ActionType type;

  /// Calls: chips added. Bets: the bet. Raises: the street total raised to.
  final int amount;
  final Street street;
}

class _Parsed {
  String site = 'PokerStars';
  String id = '';
  DateTime? at;
  bool tournament = false;
  int scale = 1;
  int sb = 0, bb = 0, ante = 0;
  int buttonSeat = -1;
  final seats = <int, (String, int)>{}; // seat number -> (name, stack)
  final sittingOut = <String>{};
  String? hero;
  List<int>? heroCards;
  final shown = <String, List<int>>{};
  final board = <int>[];
  final actions = <_Action>[];
  final posts = <String, int>{}; // blind posts: name -> amount
  final antes = <String, int>{};
  String? sbName, bbName;
  final collected = <String, int>{};
  final uncalled = <String, int>{};
}

final _money = RegExp(r'[$€£]?([\d,]+(?:\.\d+)?)');

int _amount(String s, int scale) {
  final m = _money.firstMatch(s);
  if (m == null) throw _Skip('Unreadable amount "$s"');
  return (double.parse(m.group(1)!.replaceAll(',', '')) * scale).round();
}

List<int> _cards(String s) => [for (final c in s.trim().split(RegExp(r'\s+'))) if (c.isNotEmpty) parseCard(c)];

_Parsed _parse(String block) {
  final p = _Parsed();
  final lines = block.split('\n').map((l) => l.trimRight()).where((l) => l.isNotEmpty).toList();
  final head = lines.first;
  p.site = head.startsWith('Poker Hand #') ? 'GGPoker' : 'PokerStars';
  p.id = RegExp(r'#\s*([A-Za-z0-9-]+)').firstMatch(head)?.group(1) ?? '';
  if (!head.contains("Hold'em No Limit")) throw _Skip('Hand ${p.id}: not No-Limit Hold\'em');
  p.tournament = head.contains('Tournament #');
  // Cash amounts have decimals (dollars): count in cents.
  // Tournament amounts are chips even though the buy-in is in dollars.
  p.scale = !p.tournament && RegExp(r'[$€£]\d|\d\.\d\d').hasMatch(block) ? 100 : 1;
  final stakes = RegExp(r'\(([^()]*?)/([^()]*?)\)').allMatches(head).toList();
  if (stakes.isEmpty) throw _Skip('Hand ${p.id}: no stakes');
  final st = stakes.last;
  p.sb = _amount(st.group(1)!, p.scale);
  p.bb = _amount(st.group(2)!, p.scale);
  final date = RegExp(r'(\d{4})/(\d{1,2})/(\d{1,2}) (\d{1,2}):(\d{2}):(\d{2})').firstMatch(head);
  if (date != null) {
    final g = [for (var i = 1; i <= 6; i++) int.parse(date.group(i)!)];
    p.at = DateTime(g[0], g[1], g[2], g[3], g[4], g[5]);
  }

  var street = Street.preflop;
  var inSummary = false;
  final seatLine = RegExp(r'^Seat (\d+): (.+?) \(([^)]*?) in chips(?:,[^)]*)?\)(.*)$');
  final actLine = RegExp(r'^(.+?): (folds|checks|calls|bets|raises)(?: (\S+))?(?: to (\S+))?');
  for (final line in lines.skip(1)) {
    if (line.startsWith('*** SUMMARY')) inSummary = true;
    if (inSummary) continue;
    if (line.contains('FIRST FLOP') || line.contains('FIRST BOARD') || line.contains('run it twice')) {
      throw _Skip('Hand ${p.id}: run it twice');
    }
    final button = RegExp(r'Seat #(\d+) is the button').firstMatch(line);
    if (button != null) {
      p.buttonSeat = int.parse(button.group(1)!);
      continue;
    }
    final seat = seatLine.firstMatch(line);
    if (seat != null && street == Street.preflop && p.actions.isEmpty) {
      final name = seat.group(2)!;
      p.seats[int.parse(seat.group(1)!)] = (name, _amount(seat.group(3)!, p.scale));
      if (seat.group(4)!.contains('sitting out') || seat.group(4)!.contains('out of hand')) p.sittingOut.add(name);
      continue;
    }
    if (line.startsWith('*** FLOP ***')) {
      street = Street.flop;
      p.board.addAll(_cards(RegExp(r'\[([^\]]+)\]').firstMatch(line)!.group(1)!));
      continue;
    }
    if (line.startsWith('*** TURN ***') || line.startsWith('*** RIVER ***')) {
      street = line.startsWith('*** TURN') ? Street.turn : Street.river;
      final groups = RegExp(r'\[([^\]]+)\]').allMatches(line).toList();
      p.board.addAll(_cards(groups.last.group(1)!));
      continue;
    }
    final dealt = RegExp(r'^Dealt to (.+?) \[([^\]]+)\]').firstMatch(line);
    if (dealt != null) {
      p.hero = dealt.group(1);
      p.heroCards = _cards(dealt.group(2)!);
      continue;
    }
    final post = RegExp(r'^(.+?): posts (small blind|big blind|the ante|small & big blinds|straddle|missed blind) (\S+)')
        .firstMatch(line);
    if (post != null) {
      final name = post.group(1)!, what = post.group(2)!;
      final amt = _amount(post.group(3)!, p.scale);
      switch (what) {
        case 'small blind':
          p.sbName = name;
          p.posts[name] = amt;
        case 'big blind':
          p.bbName = name;
          p.posts[name] = amt;
        case 'the ante':
          p.antes[name] = amt;
        default:
          throw _Skip('Hand ${p.id}: ${what == 'straddle' ? 'straddle' : 'dead or missed blinds'}');
      }
      continue;
    }
    final act = actLine.firstMatch(line);
    if (act != null && !line.contains(' collected ')) {
      final name = act.group(1)!;
      final verb = act.group(2)!;
      final type = switch (verb) {
        'folds' => ActionType.fold,
        'checks' => ActionType.check,
        'calls' => ActionType.call,
        'bets' => ActionType.bet,
        _ => ActionType.raise,
      };
      var amount = 0;
      if (type == ActionType.raise) {
        amount = _amount(act.group(4) ?? act.group(3)!, p.scale);
      } else if (type == ActionType.bet || type == ActionType.call) {
        amount = _amount(act.group(3)!, p.scale);
      }
      p.actions.add(_Action(name, type, amount, street));
      continue;
    }
    final back = RegExp(r'^Uncalled bet \((\S+)\) returned to (.+)$').firstMatch(line);
    if (back != null) {
      p.uncalled[back.group(2)!] = (p.uncalled[back.group(2)!] ?? 0) + _amount(back.group(1)!, p.scale);
      continue;
    }
    final won = RegExp(r'^(.+?) collected (\S+) from').firstMatch(line);
    if (won != null) {
      p.collected[won.group(1)!] = (p.collected[won.group(1)!] ?? 0) + _amount(won.group(2)!, p.scale);
      continue;
    }
    final shows = RegExp(r'^(.+?): shows \[([^\]]+)\]').firstMatch(line);
    if (shows != null) {
      final cards = _cards(shows.group(2)!);
      if (cards.length == 2) p.shown[shows.group(1)!] = cards;
      continue;
    }
  }
  if (p.hero == null || p.heroCards == null || p.heroCards!.length != 2) {
    throw _Skip('Hand ${p.id}: no hole cards for the player');
  }
  if (p.buttonSeat < 0) throw _Skip('Hand ${p.id}: no button');
  final anteValues = p.antes.values.toSet();
  if (anteValues.length > 1) throw _Skip('Hand ${p.id}: uneven antes');
  p.ante = anteValues.isEmpty ? 0 : anteValues.first;
  return p;
}

HandHistory _replay(_Parsed p, {required bool review, required int samples, required Random rng}) {
  // Engine seats: everyone dealt in, in seat order.
  final order = (p.seats.keys.toList()..sort()).where((k) => !p.sittingOut.contains(p.seats[k]!.$1)).toList();
  final names = [for (final k in order) p.seats[k]!.$1];
  final index = {for (var i = 0; i < names.length; i++) names[i]: i};
  final hero = index[p.hero];
  if (hero == null) throw _Skip('Hand ${p.id}: the player wasn\'t dealt in');
  final button = order.indexOf(p.buttonSeat);
  if (button < 0) throw _Skip('Hand ${p.id}: dead button');
  if (names.length < 2) throw _Skip('Hand ${p.id}: fewer than two players');

  // Stack the deck so the engine deals the known cards where they belong.
  final known = <int, List<int>>{hero: p.heroCards!};
  for (final e in p.shown.entries) {
    final i = index[e.key];
    if (i != null) known[i] = e.value;
  }
  final used = {for (final h in known.values) ...h, ...p.board};
  final filler = [for (var c = 0; c < 52; c++) if (!used.contains(c)) c]..shuffle(Random(p.id.hashCode));
  var f = 0;
  final n = names.length;
  final sbSeat = n == 2 ? button : (button + 1) % n;
  final dealOrder = [for (var k = 0; k < n; k++) (sbSeat + k) % n];
  final deck = <int>[];
  for (var round = 0; round < 2; round++) {
    for (final s in dealOrder) {
      deck.add(known[s]?[round] ?? filler[f++]);
    }
  }
  for (var street = 0; street < 3; street++) {
    deck.add(filler[f++]); // burn
    final count = street == 0 ? 3 : 1;
    final from = street == 0 ? 0 : street + 2;
    for (var k = 0; k < count; k++) {
      deck.add(from + k < p.board.length ? p.board[from + k] : filler[f++]);
    }
  }
  deck.addAll(filler.sublist(f));

  var s = startHand(
    players: [for (final k in order) SeatSetup(p.seats[k]!.$1, p.seats[k]!.$2)],
    button: button,
    smallBlind: p.sb,
    bigBlind: p.bb,
    ante: p.ante,
    anteFromEveryone: p.ante > 0,
    handNumber: p.id.hashCode & 0x7fffffff,
    deck: deck,
  );
  if (p.sbName != null && names[s.smallBlindSeat] != p.sbName && n > 2) {
    throw _Skip('Hand ${p.id}: unusual blinds');
  }
  if (p.bbName != null && names[s.bigBlindSeat] != p.bbName) throw _Skip('Hand ${p.id}: unusual blinds');

  final reviews = <DecisionReview>[];
  for (final a in p.actions) {
    if (s.isComplete) throw _Skip('Hand ${p.id}: more actions than the rules allow');
    final seat = index[a.name];
    if (seat == null || seat != s.toAct) throw _Skip('Hand ${p.id}: actions out of order');
    final legal = legalActions(s);
    final action = switch (a.type) {
      ActionType.fold => const PlayerAction(ActionType.fold),
      ActionType.check => const PlayerAction.check(),
      ActionType.call => const PlayerAction.call(),
      ActionType.bet => PlayerAction(ActionType.bet, legal.streetBet + a.amount),
      ActionType.raise => PlayerAction(ActionType.raise, a.amount),
    };
    if (review && seat == hero) {
      try {
        final analysis = analyzeDecision(buildBotContext(s), samples: samples, rng: rng);
        final r = gradeDecision(analysis, action);
        if (r != null) reviews.add(r);
      } catch (_) {
        // A decision the coach can't analyse is simply not graded.
      }
    }
    s = applyAction(s, action);
  }
  if (!s.isComplete) throw _Skip('Hand ${p.id}: the hand history stops early');

  // Results from the hand history (handles rake and unseen mucked hands).
  final events = <Map<String, Object?>>[];
  for (final e in s.log) {
    if (e is ShowdownRevealed || e is PotAwarded || e is HandEnded) break;
    events.add(e.toJson());
  }
  final invested = List<int>.filled(n, 0);
  for (final e in events) {
    final seat = e['seat'];
    if (seat is! int) continue;
    switch (e['e']) {
      case 'blind' || 'ante':
        invested[seat] += e['amount'] as int;
      case 'act':
        invested[seat] += e['added'] as int;
      case 'uncalled':
        invested[seat] -= e['amount'] as int;
    }
  }
  if (p.board.length == 5 && p.shown.isNotEmpty) {
    events.add({
      'e': 'showdown',
      'hands': {
        for (final e in p.shown.entries)
          if (index[e.key] != null)
            '${index[e.key]}': {'hole': e.value, 'value': evaluate([...e.value, ...p.board])},
      },
    });
  }
  final shares = {for (final e in p.collected.entries) if (index[e.key] != null) index[e.key]!: e.value};
  events.add({
    'e': 'award',
    'potIndex': 0,
    'amount': shares.values.fold<int>(0, (a, b) => a + b),
    'shares': {for (final e in shares.entries) '${e.key}': e.value},
    'handValue': null,
  });
  events.add({
    'e': 'end',
    'stacks': {for (var i = 0; i < n; i++) '$i': p.seats[order[i]]!.$2 - invested[i] + (shares[i] ?? 0)},
  });
  final net = (shares[hero] ?? 0) - invested[hero];
  String money(int v) => p.scale == 100 ? '\$${(v / 100).toStringAsFixed(2)}' : '$v';
  final summary = [
    for (final e in shares.entries)
      e.key == hero ? 'You win ${money(e.value)}' : '${names[e.key]} wins ${money(e.value)}',
  ].join(', ');
  return HandHistory(
    handNumber: p.id.hashCode & 0x7fffffff,
    playedAt: p.at ?? DateTime.now(),
    heroSeat: hero,
    heroNet: net,
    events: events,
    summary: summary,
    heroHole: p.heroCards,
    reviews: reviews,
    mode: p.tournament ? 'sng' : 'cash',
    source: p.site,
    sourceId: p.id,
  );
}
