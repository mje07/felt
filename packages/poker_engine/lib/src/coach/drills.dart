import 'dart:math';

import '../bots/preflop_chart.dart';
import '../card.dart';
import '../evaluator.dart';
import 'notation.dart';
import 'outs.dart';
import 'ranges.dart';

enum DrillKind {
  preflop('Preflop decisions', 'Raise, call or fold from every seat, checked against the baseline charts.'),
  potOdds('Pot odds', 'How much equity do you need to call this bet?'),
  outs('Counting outs', 'How many cards complete your draw?'),
  equity('Equity sense', 'Estimate your share of the pot against a known hand.'),
  showdown('Read the showdown', 'Who wins at the river, and with what?');

  const DrillKind(this.title, this.description);
  final String title, description;
}

/// One multiple-choice question. Exactly one choice is correct.
class Question {
  const Question({
    required this.kind,
    required this.prompt,
    required this.choices,
    required this.answer,
    required this.explanation,
    this.situation,
    this.hole = const [],
    this.board = const [],
    this.villain,
    this.pot,
    this.bet,
  });

  final DrillKind kind;
  final String prompt;

  /// Short scene-setting line, e.g. "UTG raises to 2.5 bb. You're on the BTN."
  final String? situation;
  final List<int> hole, board;
  final List<int>? villain;
  final int? pot, bet;
  final List<String> choices;
  final int answer;
  final String explanation;
}

Question generateQuestion(DrillKind kind, Random rng) => switch (kind) {
      DrillKind.preflop => _preflop(rng),
      DrillKind.potOdds => _potOdds(rng),
      DrillKind.outs => _outs(rng),
      DrillKind.equity => _equity(rng),
      DrillKind.showdown => _showdown(rng),
    };

String _pct(double v) => '${(v * 100).round()}%';

List<int> _deal(Random rng, int n, [Set<int> used = const {}]) {
  final out = <int>[];
  final taken = {...used};
  while (out.length < n) {
    final c = rng.nextInt(52);
    if (taken.add(c)) out.add(c);
  }
  return out;
}

/// Two concrete cards for a grid index (random suits).
List<int> _cardsFor(int index, Random rng) {
  final row = index ~/ 13, col = index % 13;
  if (row == col) {
    final s = [0, 1, 2, 3]..shuffle(rng);
    return [makeCard(row, s[0]), makeCard(row, s[1])];
  }
  final suited = row > col;
  final hi = suited ? row : col, lo = suited ? col : row;
  final s1 = rng.nextInt(4);
  var s2 = suited ? s1 : rng.nextInt(4);
  while (!suited && s2 == s1) {
    s2 = rng.nextInt(4);
  }
  return [makeCard(hi, s1), makeCard(lo, s2)];
}

// ---------------------------------------------------------------- preflop

Question _preflop(Random rng) {
  final scenario = PreflopScenario.values[rng.nextInt(PreflopScenario.values.length)];
  final (String pos, String situation) = switch (scenario) {
    PreflopScenario.unopened => () {
        final p = ['UTG', 'MP', 'HJ', 'CO', 'BTN', 'SB'][rng.nextInt(6)];
        return (p, p == 'SB' ? 'It folds to you in the small blind.' : 'It folds to you on the $p.');
      }(),
    PreflopScenario.vsEarlyOpen => () {
        final p = ['CO', 'BTN', 'SB'][rng.nextInt(3)];
        return (p, 'UTG raises to 2.5 bb. You\'re on the $p.');
      }(),
    PreflopScenario.vsLateOpen => () {
        final p = ['BTN', 'SB'][rng.nextInt(2)];
        return (p, 'The ${p == 'BTN' ? 'CO' : 'BTN'} raises to 2.5 bb. You\'re on the $p.');
      }(),
    PreflopScenario.bbDefense => ('BB', 'The ${['HJ', 'CO', 'BTN'][rng.nextInt(3)]} raises to 2.5 bb. You\'re in the big blind.'),
    PreflopScenario.vs3bet => () {
        final p = ['HJ', 'CO', 'BTN'][rng.nextInt(3)];
        return (p, 'You open to 2.5 bb from the $p and the big blind 3-bets to 10 bb.');
      }(),
  };
  final chart = chartFor(pos, scenario);

  // Mostly ask about hands near the edge of the range — that's where the
  // decisions are hard.
  final played = chart.played;
  final edge = played.map(preflopPercentileOf).fold(0.0, max);
  int index;
  if (rng.nextDouble() < 0.65) {
    final near = [for (var i = 0; i < 169; i++) if ((preflopPercentileOf(i) - edge).abs() < 0.12) i];
    index = near[rng.nextInt(near.length)];
  } else {
    // Weighted by combos, like real dealing.
    var r = rng.nextInt(1326);
    index = 0;
    while (r >= combosAt(index)) {
      r -= combosAt(index);
      index++;
    }
  }
  final action = chart.actionFor(index);
  final unopened = scenario == PreflopScenario.unopened;
  final choices = ['Fold', unopened ? 'Limp' : 'Call', unopened ? 'Raise' : (scenario == PreflopScenario.vs3bet ? '4-bet' : '3-bet')];
  final answer = switch (action) { PreAction.fold || PreAction.check => 0, PreAction.call => 1, PreAction.raise => 2 };
  final hand = startingHandName(index);
  final raisePct = _pct(rangeFraction(chart.raise));
  final playPct = _pct(rangeFraction(played));
  final explanation = switch (action) {
    PreAction.raise => '$hand is in the raising range here (top $raisePct of hands).',
    PreAction.call => '$hand is strong enough to continue but not to raise: the chart calls with it '
        '(continuing range: top $playPct).',
    _ => unopened
        ? '$hand is outside the ${pos == 'SB' ? 'small blind' : pos} opening range (top $playPct). Fold.'
        : '$hand is too weak to continue in this spot (continuing range: top $playPct). Fold.',
  };
  return Question(
    kind: DrillKind.preflop,
    prompt: 'What\'s the best play?',
    situation: situation,
    hole: _cardsFor(index, rng),
    choices: choices,
    answer: answer,
    explanation: explanation + (unopened && action != PreAction.raise ? ' Limping is never the baseline play.' : ''),
  );
}

// ---------------------------------------------------------------- pot odds

Question _potOdds(Random rng) {
  final pot = (4 + rng.nextInt(77)) * 5; // 20..400
  const fracs = [0.25, 0.33, 0.5, 0.66, 0.75, 1.0, 1.25, 1.5, 2.0];
  final bet = max(5, (pot * fracs[rng.nextInt(fracs.length)] / 5).round() * 5);
  final req = bet / (pot + 2 * bet);
  final correct = (req * 100).round();
  final options = <int>{correct};
  for (final d in [(bet / (pot + bet) * 100).round(), (min(bet / pot, 0.95) * 100).round(), correct + 8, correct - 7, correct + 15]) {
    if (options.length >= 4) break;
    if (d > 0 && d < 100 && (d - correct).abs() >= 4 && options.every((o) => (o - d).abs() >= 4)) options.add(d);
  }
  var fill = 5;
  while (options.length < 4) {
    final d = correct + fill;
    if (d < 100 && options.every((o) => (o - d).abs() >= 4)) options.add(d);
    fill = fill > 0 ? -fill : -fill + 5;
  }
  final choices = options.toList()..shuffle(rng);
  return Question(
    kind: DrillKind.potOdds,
    prompt: 'How much equity do you need to call?',
    situation: 'The pot is $pot. Your opponent bets $bet.',
    pot: pot,
    bet: bet,
    choices: [for (final c in choices) '$c%'],
    answer: choices.indexOf(correct),
    explanation: 'You call $bet to win a final pot of ${pot + 2 * bet}. Required equity = $bet ÷ ${pot + 2 * bet} '
        '= ${(req * 100).toStringAsFixed(1)}%. If your hand wins more often than that, calling makes money.',
  );
}

// ---------------------------------------------------------------- outs

Question _outs(Random rng) {
  while (true) {
    final boardLen = rng.nextDouble() < 0.65 ? 3 : 4;
    final cards = _deal(rng, 2 + boardLen);
    final hole = cards.sublist(0, 2), board = cards.sublist(2);
    final cat = categoryOf(evaluate(cards));
    if (cat.index > HandCategory.pair.index) continue;
    final outs = outsToStraightOrBetter(hole, board);
    const allowed = {4, 8, 9, 12, 15};
    if (!allowed.contains(outs.length)) continue;
    // The draw should use at least one hole card (board-only draws are confusing).
    if (boardLen == 4) {
      final onBoard = {...board, ...hole};
      final boardOnly = [
        for (var c = 0; c < 52; c++)
          if (!onBoard.contains(c) && categoryOf(evaluate([...board, c])).index >= HandCategory.straight.index) c
      ];
      if (boardOnly.isNotEmpty) continue;
    }
    final n = outs.length;
    final options = <int>{n};
    for (final d in [4, 8, 9, 12, 15, 6]..shuffle(rng)) {
      if (options.length < 4) options.add(d);
    }
    final choices = options.toList()..sort();
    final chance = hitChanceByRiver(n, boardLen);
    final rule = boardLen == 3 ? 4 : 2;
    return Question(
      kind: DrillKind.outs,
      prompt: 'How many outs do you have to make a straight or better?',
      situation: boardLen == 3 ? 'On the flop.' : 'On the turn.',
      hole: hole,
      board: board,
      choices: [for (final c in choices) '$c'],
      answer: choices.indexOf(n),
      explanation: '$n cards complete your hand (${outs.map(cardToString).take(6).join(' ')}'
          '${n > 6 ? ' …' : ''}). Rule of $rule: $n × $rule ≈ ${n * rule}% to hit by the river '
          '(exactly ${_pct(chance)}).',
    );
  }
}

// ---------------------------------------------------------------- equity

/// Exact equity of [a] vs [b] on [board] (3 or 4 cards), ties count half.
double exactEquity(List<int> a, List<int> b, List<int> board) {
  final used = {...a, ...b, ...board};
  final rest = [for (var c = 0; c < 52; c++) if (!used.contains(c)) c];
  var share = 0.0, n = 0;
  void score(List<int> full) {
    final x = evaluate([...a, ...full]), y = evaluate([...b, ...full]);
    share += x > y ? 1 : (x == y ? 0.5 : 0);
    n++;
  }

  if (board.length == 4) {
    for (final r in rest) {
      score([...board, r]);
    }
  } else {
    for (var i = 0; i < rest.length; i++) {
      for (var j = i + 1; j < rest.length; j++) {
        score([...board, rest[i], rest[j]]);
      }
    }
  }
  return share / n;
}

Question _equity(Random rng) {
  const buckets = ['0–20%', '20–40%', '40–60%', '60–80%', '80–100%'];
  while (true) {
    final boardLen = rng.nextDouble() < 0.6 ? 3 : 4;
    final cards = _deal(rng, 4 + boardLen);
    final hole = cards.sublist(0, 2), villain = cards.sublist(2, 4), board = cards.sublist(4);
    final eq = exactEquity(hole, villain, board);
    final pos = eq * 5;
    if ((pos - pos.round()).abs() < 0.1 && pos > 0.1 && pos < 4.9) continue; // too close to a boundary
    final answer = min(4, (eq * 5).floor());
    final mine = describeHand(evaluate([...hole, ...board]));
    final theirs = describeHand(evaluate([...villain, ...board]));
    return Question(
      kind: DrillKind.equity,
      prompt: 'What\'s your equity?',
      situation: 'Your opponent shows their hand ${boardLen == 3 ? 'on the flop' : 'on the turn'}.',
      hole: hole,
      board: board,
      villain: villain,
      choices: buckets,
      answer: answer,
      explanation: 'Exactly ${(eq * 100).toStringAsFixed(1)}%. Right now you have ${mine.toLowerCase()} against '
          '${theirs.toLowerCase()}, with ${boardLen == 3 ? 'two cards' : 'one card'} to come.',
    );
  }
}

// ---------------------------------------------------------------- showdown

Question _showdown(Random rng) {
  final cards = _deal(rng, 9);
  final hole = cards.sublist(0, 2), villain = cards.sublist(2, 4), board = cards.sublist(4);
  final a = evaluate([...hole, ...board]), b = evaluate([...villain, ...board]);
  final answer = a > b ? 0 : (a < b ? 1 : 2);
  return Question(
    kind: DrillKind.showdown,
    prompt: 'Who wins the pot?',
    situation: 'Both players reach the river.',
    hole: hole,
    board: board,
    villain: villain,
    choices: const ['You', 'Opponent', 'Split pot'],
    answer: answer,
    explanation: 'You have ${describeHand(a)}; your opponent has ${describeHand(b)}.'
        '${a == b ? ' The best five cards are equal, so the pot is split.' : ''}',
  );
}
