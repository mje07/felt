import '../card.dart';
import '../evaluator.dart';
import '../history.dart';

/// Writes a hand in PokerStars hand-history format, which tracking tools
/// (PokerTracker, Hold'em Manager, …) and Felt's own importer can read.
/// Amounts are written in chips.
String toPokerStarsText(HandHistory h, {String tableName = 'Felt'}) {
  final start = h.events.firstWhere((e) => e['e'] == 'start');
  final seats = [for (final s in start['seats'] as List) (s as Map).cast<String, Object?>()];
  String name(int seat) => seats[seat]['name'] as String;
  final sb = start['sb'] as int, bb = start['bb'] as int;
  final button = start['button'] as int;
  final t = h.playedAt;
  String two(int x) => x.toString().padLeft(2, '0');
  final id = h.sourceId != null && RegExp(r'^\d+$').hasMatch(h.sourceId!) ? h.sourceId! : '${h.handNumber}';
  final out = StringBuffer()
    ..writeln("PokerStars Hand #$id:  Hold'em No Limit ($sb/$bb) - "
        '${t.year}/${two(t.month)}/${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)} ET')
    ..writeln("Table '$tableName' ${seats.length}-max Seat #${button + 1} is the button");
  for (var i = 0; i < seats.length; i++) {
    out.writeln('Seat ${i + 1}: ${name(i)} (${seats[i]['stack']} in chips)');
  }

  final invested = List<int>.filled(seats.length, 0);
  final board = <int>[];
  var currentBet = 0;
  var holeWritten = false;
  void hole() {
    if (holeWritten) return;
    holeWritten = true;
    out.writeln('*** HOLE CARDS ***');
    final cards = h.heroHole;
    if (cards != null) out.writeln('Dealt to ${name(h.heroSeat)} [${cardsToString(cards)}]');
  }

  var collected = 0;
  for (final e in h.events) {
    final seat = e['seat'] as int?;
    switch (e['e']) {
      case 'ante':
        out.writeln('${name(seat!)}: posts the ante ${e['amount']}');
        invested[seat] += e['amount'] as int;
      case 'blind':
        final amount = e['amount'] as int;
        out.writeln('${name(seat!)}: posts ${e['big'] == true ? 'big' : 'small'} blind $amount');
        invested[seat] += amount;
        if (e['big'] == true) currentBet = bb;
      case 'deal':
        hole();
      case 'street':
        hole();
        final cards = [for (final c in e['cards'] as List) c as int];
        final before = List.of(board);
        board.addAll(cards);
        currentBet = 0;
        final label = switch (board.length) { 3 => 'FLOP', 4 => 'TURN', _ => 'RIVER' };
        out.writeln(before.isEmpty
            ? '*** $label *** [${cardsToString(board)}]'
            : '*** $label *** [${cardsToString(before)}] [${cardsToString(cards)}]');
      case 'act':
        hole();
        final added = e['added'] as int, to = e['to'] as int;
        final allIn = e['allIn'] == true ? ' and is all-in' : '';
        invested[seat!] += added;
        final line = switch (e['type']) {
          'fold' => 'folds',
          'check' => 'checks',
          'call' => 'calls $added$allIn',
          'bet' => 'bets $added$allIn',
          _ => 'raises ${to - currentBet} to $to$allIn',
        };
        if (e['type'] == 'bet' || e['type'] == 'raise') currentBet = to;
        out.writeln('${name(seat)}: $line');
      case 'uncalled':
        out.writeln('Uncalled bet (${e['amount']}) returned to ${name(seat!)}');
        invested[seat] -= e['amount'] as int;
      case 'showdown':
        out.writeln('*** SHOW DOWN ***');
        final hands = (e['hands'] as Map).cast<String, Object?>();
        for (final entry in hands.entries) {
          final m = (entry.value as Map).cast<String, Object?>();
          final cards = [for (final c in m['hole'] as List) c as int];
          out.writeln('${name(int.parse(entry.key))}: shows [${cardsToString(cards)}] '
              '(${describeHand(m['value'] as int).toLowerCase()})');
        }
      case 'award':
        final shares = (e['shares'] as Map).cast<String, Object?>();
        for (final entry in shares.entries) {
          final amount = entry.value as int;
          collected += amount;
          out.writeln('${name(int.parse(entry.key))} collected $amount from pot');
        }
    }
  }
  final pot = invested.fold<int>(0, (a, b) => a + b);
  out
    ..writeln('*** SUMMARY ***')
    ..writeln('Total pot $pot | Rake ${pot - collected}');
  if (board.isNotEmpty) out.writeln('Board [${cardsToString(board)}]');
  return out.toString();
}

/// Several hands, separated the way the sites separate them.
String exportPokerStars(Iterable<HandHistory> hands) => hands.map(toPokerStarsText).join('\n\n\n');
