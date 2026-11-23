import 'dart:math';

import '../bots/bot.dart';
import '../bots/preflop_chart.dart';
import '../equity.dart';
import '../evaluator.dart';
import '../game_state.dart';
import 'outs.dart';
import 'ranges.dart';

/// One candidate action with its estimated value.
class OptionEv {
  const OptionEv(this.action, this.ev);
  final PlayerAction action;

  /// Chips, relative to folding now.
  final double ev;
}

/// The coach's view of a decision: equities, pot odds and an EV estimate for
/// each option. Plain data so it can be computed in an isolate.
class DecisionAnalysis {
  DecisionAnalysis._({
    required this.street,
    required this.legal,
    required this.pot,
    required this.bigBlind,
    required this.stack,
    required this.opponents,
    required this.handIndex,
    required this.opponentNote,
    this.equity,
    this.calledEquities = const [],
    this.outs = 0,
    this.position,
    this.scenario,
    this.preflop,
  });

  final Street street;
  final LegalActions legal;
  final int pot, bigBlind, stack, opponents, handIndex;

  /// e.g. "Ava's likely range (top 22%)".
  final String opponentNote;

  /// Postflop: share of the pot won vs the modelled ranges.
  final double? equity;

  /// Equity against the part of each range that continues versus a bet, for
  /// the continue fractions in [calledFractions] (strongest hands on this
  /// board continue).
  final List<double> calledEquities;
  final int outs;

  /// Equity when a bet of [ratio] × pot gets called. Bigger bets are called
  /// by a stronger, board-aware slice of the range.
  double calledEquity(double ratio) {
    final e = equity ?? 0;
    if (calledEquities.length != calledFractions.length) return e;
    // Anchor points: ratio 0 -> full range, then ⅓ pot, pot, 2x pot.
    const anchors = [0.0, 0.33, 1.0, 2.0];
    final values = [e, ...calledEquities];
    if (ratio >= anchors.last) return values.last;
    for (var i = 1; i < anchors.length; i++) {
      if (ratio <= anchors[i]) {
        final t = (ratio - anchors[i - 1]) / (anchors[i] - anchors[i - 1]);
        return values[i - 1] + (values[i] - values[i - 1]) * t;
      }
    }
    return values.last;
  }

  /// Preflop.
  final String? position;
  final PreflopScenario? scenario;
  final PreflopAdvice? preflop;

  bool get isPreflop => street == Street.preflop;

  /// Equity needed to call: call / (pot + call).
  double get requiredEquity => legal.callAmount == 0 ? 0 : legal.callAmount / (pot + legal.callAmount);

  double get _realization => switch (street) { Street.flop => 0.9, Street.turn => 0.95, _ => 1.0 };

  /// Estimated chip EV of [a] relative to folding. Postflop only.
  double evOf(PlayerAction a) {
    final e = equity ?? 0;
    final r = _realization;
    final l = legal;
    switch (a.type) {
      case ActionType.fold:
        return 0;
      case ActionType.check:
        return e * pot * r;
      case ActionType.call:
        final call = l.callAmount;
        final allIn = call >= stack;
        return e * (pot + call) * (allIn ? 1 : r) - call;
      case ActionType.bet:
      case ActionType.raise:
        final to = a.amount.clamp(l.minRaiseTo, l.maxRaiseTo);
        final risk = to - l.streetBet;
        final oppCall = to - l.currentBet;
        final ratio = oppCall / max(1, pot);
        // Fold probability per opponent grows with size (≈ minimum-defence
        // frequency: a pot-size bet gets folded about half the time).
        var single = 0.22 + 0.28 * min(ratio, 1.0) + (ratio > 1 ? 0.18 * log(ratio) : 0);
        single = single.clamp(0.22, 0.9);
        if (l.currentBet > 0) single *= 0.85; // raises get called more than bets
        final f = pow(single, opponents).toDouble();
        final allIn = to >= l.maxRaiseTo;
        final called = calledEquity(ratio);
        return f * pot + (1 - f) * (called * (pot + risk + oppCall) * (allIn ? 1 : r) - risk);
    }
  }

  /// Candidate actions the coach compares: fold/check/call and bets of ½, ¾,
  /// pot and all-in.
  List<OptionEv> get options {
    final l = legal;
    final acts = <PlayerAction>[
      if (l.canFold) const PlayerAction.fold(),
      if (l.canCheck) const PlayerAction.check(),
      if (l.canCall) const PlayerAction.call(),
    ];
    if (l.canRaise) {
      final type = l.isBet ? ActionType.bet : ActionType.raise;
      final sizes = <int>{};
      for (final f in [0.5, 0.75, 1.0]) {
        final to = (l.currentBet + f * (pot + l.toCall)).round().clamp(l.minRaiseTo, l.maxRaiseTo);
        sizes.add(to);
      }
      // All-in is a candidate only when it's a sane size (≤ 2.5x pot); huge
      // overbet shoves are judged by evOf() if the player chooses them.
      if (l.maxRaiseTo - l.currentBet <= 2.5 * (pot + l.toCall)) sizes.add(l.maxRaiseTo);
      for (final to in sizes) {
        acts.add(PlayerAction(type, to));
      }
    }
    return [for (final a in acts) OptionEv(a, evOf(a))];
  }

  OptionEv get best => options.reduce((a, b) => b.ev > a.ev ? b : a);

  /// Readable label for an action in this spot, e.g. "Bet 60 (¾ pot)".
  String describe(PlayerAction a) {
    final l = legal;
    switch (a.type) {
      case ActionType.fold:
        return 'Fold';
      case ActionType.check:
        return 'Check';
      case ActionType.call:
        return l.callAmount >= stack ? 'Call all-in' : 'Call ${l.callAmount}';
      case ActionType.bet:
      case ActionType.raise:
        final to = a.amount;
        if (to >= l.maxRaiseTo) return 'All-in ($to)';
        final verb = l.isBet ? 'Bet' : 'Raise to';
        if (isPreflop) return '$verb $to';
        final frac = (to - l.currentBet) / max(1, pot + l.toCall);
        final name = frac < 0.4
            ? '⅓ pot'
            : frac < 0.62
                ? '½ pot'
                : frac < 0.87
                    ? '¾ pot'
                    : frac < 1.2
                        ? 'pot'
                        : 'overbet';
        return '$verb $to ($name)';
    }
  }
}

/// Analyses the decision described by [ctx] (from `buildBotContext`).
DecisionAnalysis analyzeDecision(BotContext ctx, {int samples = 2500, Random? rng}) {
  final handIndex = startingHandIndex(ctx.hole[0], ctx.hole[1]);
  final note = _opponentNote(ctx);
  if (ctx.street == Street.preflop) {
    final scenario = scenarioFor(
        position: ctx.position, raisesBefore: ctx.preflopRaises, openerPosition: ctx.openerPosition);
    // Charts assume deep stacks; short-stack spots are push/fold territory.
    final advice = ctx.effectiveStackBb >= 20 ? adviseFor(ctx.position, scenario, handIndex) : null;
    return DecisionAnalysis._(
      street: ctx.street,
      legal: ctx.legal,
      pot: ctx.pot,
      bigBlind: ctx.bigBlind,
      stack: ctx.stack,
      opponents: ctx.opponents,
      handIndex: handIndex,
      opponentNote: note,
      position: ctx.position,
      scenario: scenario,
      preflop: advice,
    );
  }
  final r = rng ?? Random();
  final e = monteCarloEquity(
    hole: ctx.hole,
    board: ctx.board,
    opponents: ctx.opponents,
    iterations: samples,
    rng: r,
    opponentRanges: ctx.opponentRanges,
  ).equity;
  final called = [
    for (final q in calledFractions)
      _continuingEquity(ctx.hole, ctx.board, ctx.opponentRanges, q, samples ~/ 2, r),
  ];
  return DecisionAnalysis._(
    street: ctx.street,
    legal: ctx.legal,
    pot: ctx.pot,
    bigBlind: ctx.bigBlind,
    stack: ctx.stack,
    opponents: ctx.opponents,
    handIndex: handIndex,
    opponentNote: note,
    equity: e,
    calledEquities: called,
    outs: outsToStraightOrBetter(ctx.hole, ctx.board).length,
    position: ctx.position,
  );
}

/// Share of each opponent's range assumed to continue vs a bet of ⅓ pot,
/// pot and 2x pot respectively.
const calledFractions = [0.55, 0.3, 0.12];

/// Our equity against opponents holding only the strongest [q] of their
/// range *on this board* (made-hand strength now), which is what tends to
/// continue against a bet.
double _continuingEquity(List<int> hole, List<int> board, List<double> ranges, double q, int iterations, Random rng) {
  final n = ranges.length;
  if (n == 0) return 1;
  final dead = {...hole, ...board};
  int draw(Set<int> used) {
    while (true) {
      final c = rng.nextInt(52);
      if (!used.contains(c)) return c;
    }
  }

  // Sample a hand from an opponent's (preflop-shaped) range.
  (int, int) sampleFromRange(double range, Set<int> used) {
    var a = 0, b = 0;
    for (var t = 0; t < 30; t++) {
      a = draw(used);
      b = draw({...used, a});
      if (range >= 1.0 || preflopPercentile(a, b) <= range) break;
    }
    return (a, b);
  }

  // Per-opponent strength threshold: the (1 − q) quantile of current hand
  // values across their range.
  final thresholds = <int>[];
  for (final range in ranges) {
    final values = <int>[];
    for (var i = 0; i < 200; i++) {
      final (a, b) = sampleFromRange(range, dead);
      values.add(evaluate([a, b, ...board]));
    }
    values.sort();
    thresholds.add(values[((1 - q) * (values.length - 1)).floor()]);
  }

  final need = 5 - board.length;
  var share = 0.0;
  for (var it = 0; it < iterations; it++) {
    final used = {...dead};
    final opp = <List<int>>[];
    for (var o = 0; o < n; o++) {
      var hand = sampleFromRange(ranges[o], used);
      for (var t = 0; t < 40 && evaluate([hand.$1, hand.$2, ...board]) < thresholds[o]; t++) {
        hand = sampleFromRange(ranges[o], used);
      }
      used
        ..add(hand.$1)
        ..add(hand.$2);
      opp.add([hand.$1, hand.$2]);
    }
    final full = [...board];
    for (var i = 0; i < need; i++) {
      final c = draw(used);
      used.add(c);
      full.add(c);
    }
    final mine = evaluate([...hole, ...full]);
    var best = 0, ties = 0;
    for (final h in opp) {
      final v = evaluate([...h, ...full]);
      if (v > best) {
        best = v;
        ties = 0;
      }
      if (v == mine) ties++;
    }
    if (mine > best) {
      share += 1;
    } else if (mine == best) {
      share += 1 / (ties + 1);
    }
  }
  return share / iterations;
}

String _opponentNote(BotContext ctx) {
  if (ctx.opponents == 0) return 'the field';
  if (ctx.opponents > 1) return "your ${ctx.opponents} opponents' likely ranges";
  final width = ctx.opponentRanges.isEmpty ? 1.0 : ctx.opponentRanges.first;
  final name = ctx.opponentNames.isEmpty ? 'your opponent' : "${ctx.opponentNames.first}'s";
  return width >= 0.99 ? '$name range (any two cards)' : '$name likely range (top ${(width * 100).round()}%)';
}
