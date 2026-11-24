import 'dart:math';

import '../card.dart';
import '../equity.dart';
import '../game_state.dart';
import '../range_model.dart';
import '../coach/advisor.dart' show ShoveCall;
import '../coach/pushfold.dart';
import 'bot.dart';
import 'personality.dart';
import 'preflop_chart.dart';

/// A rules-of-thumb bot: preflop ranges by position, postflop Monte Carlo
/// equity against estimated ranges vs pot odds, shaped by a [Personality].
class HeuristicBot implements Bot {
  const HeuristicBot(this.personality, this.difficulty);

  final Personality personality;
  final Difficulty difficulty;

  @override
  PlayerAction decide(BotContext ctx, Random rng) =>
      ctx.street == Street.preflop ? _preflop(ctx, rng) : _postflop(ctx, rng);

  PlayerAction get _checkOrFold => const PlayerAction(ActionType.fold);

  PlayerAction _passive(BotContext ctx) =>
      ctx.legal.canCheck ? const PlayerAction.check() : _checkOrFold;

  PlayerAction _preflop(BotContext ctx, Random rng) {
    final shortStack = _pushFold(ctx, rng);
    if (shortStack != null) return shortStack;
    final p = personality;
    final l = ctx.legal;
    final bb = ctx.bigBlind;
    // Lower is stronger: 0.02 ≈ top 2% of hands.
    var pct = preflopPercentile(ctx.hole[0], ctx.hole[1]);
    pct += (rng.nextDouble() - 0.5) * difficulty.noise;

    // Later position (fewer players behind) plays wider.
    final behind = ctx.playersAfter;
    final lateness = 1 - (behind / max(1, ctx.opponents)).clamp(0.0, 1.0);
    // Fewer live opponents means wider ranges: steals, and heads-up play.
    final range = p.looseness * (0.65 + 0.7 * lateness) * switch (ctx.opponents) { 1 => 2.3, 2 => 1.6, _ => 1.0 };
    final stackBbs = (ctx.stack + l.streetBet) / bb;
    final costFrac = l.callAmount / max(1, ctx.stack);

    if (ctx.preflopRaises == 0) {
      final openRange = range * (0.45 + 0.55 * p.aggression);
      if (pct <= openRange || rng.nextDouble() < p.bluffing * 0.15) {
        final size = bb * (2.3 + 0.4 * (1 - lateness) + ctx.limpers) ;
        if (stackBbs < 12) return raiseOrShove(ctx, l.maxRaiseTo);
        return raiseOrShove(ctx, size.round());
      }
      if (pct <= range) {
        if (l.canCheck) return const PlayerAction.check();
        return const PlayerAction.call(); // limp / complete
      }
      return _passive(ctx);
    }

    // Thinking players defend wider against someone who raises too often.
    final loose = p.adapts && difficulty != Difficulty.casual
        ? ctx.aggressorPfrRatio.clamp(0.6, 3.0)
        : 1.0;

    if (ctx.preflopRaises == 1) {
      final threeBet = max(0.025, range * 0.22 * (0.4 + p.aggression)) * pow(loose, 0.8);
      final callRange = range * (0.5 + 0.5 * p.stickiness) * (costFrac > 0.25 ? 0.4 : 1) * sqrt(loose);
      if (pct <= threeBet || (pct < 0.35 && rng.nextDouble() < p.bluffing * 0.25)) {
        final to = (l.currentBet * (behind == 0 ? 3.0 : 3.6)).round();
        return raiseOrShove(ctx, to);
      }
      if (pct <= callRange) return l.canCheck ? const PlayerAction.check() : const PlayerAction.call();
      return _passive(ctx);
    }

    // Facing a 3-bet or more.
    if (pct <= (0.025 + 0.01 * p.aggression) * loose) {
      return raiseOrShove(ctx, (l.currentBet * 2.3).round());
    }
    if (pct <= (0.05 + 0.08 * p.stickiness) * loose && costFrac < 0.5) {
      return const PlayerAction.call();
    }
    return _passive(ctx);
  }

  PlayerAction _postflop(BotContext ctx, Random rng) {
    final p = personality;
    final l = ctx.legal;
    final eqResult = monteCarloEquity(
      hole: ctx.hole,
      board: ctx.board,
      opponents: ctx.opponents,
      iterations: difficulty.samples,
      rng: rng,
      opponentRanges: difficulty.rangeReading ? ctx.opponentRanges : null,
      opponentCombos: difficulty.rangeReading && ctx.opponentCombos.isNotEmpty ? ctx.opponentCombos : null,
    );
    // Normalize multiway equity to "fair share" scale so thresholds hold.
    final fair = 1 / (ctx.opponents + 1);
    var eq = eqResult.equity;
    eq += (rng.nextDouble() - 0.5) * 2 * difficulty.noise;
    eq = eq.clamp(0.0, 1.0);
    // Heads-up-equivalent strength: fair share maps to 0.5, the nuts to 1.0.
    final s = eq <= fair ? 0.5 * eq / fair : 0.5 + 0.5 * (eq - fair) / (1 - fair);
    final pot = ctx.pot;
    final river = ctx.street == Street.river;
    final wet = _isWet(ctx.board);
    final outs = drawOuts(ctx.hole[0], ctx.hole[1], ctx.board);

    // Thinking players read the table: bluff the folders, value-bet the
    // callers. Fixed archetypes (Rock, Station, Wildcard) don't adjust.
    final adapts = p.adapts && difficulty != Difficulty.casual;
    final foldR = adapts && ctx.opponentFoldRatio.isNotEmpty
        ? ctx.opponentFoldRatio.reduce(min).clamp(0.3, 1.8)
        : 1.0;

    if (l.toCall == 0) {
      // Bet thinner against players who call too much.
      final valueLine = 0.64 - 0.10 * p.aggression - (adapts ? 0.10 * (1 - foldR).clamp(0.0, 0.6) : 0);
      if (s > valueLine) {
        // Trap now and then: slowplay the near-nuts on dry boards, or check
        // to check-raise out of position.
        if (!river && s > 0.9 && !wet && rng.nextDouble() < 0.3 * (1 - p.aggression)) {
          return const PlayerAction.check();
        }
        if (!river && !ctx.inPosition && ctx.opponents == 1 && rng.nextDouble() < 0.25 * p.aggression) {
          return const PlayerAction.check();
        }
        var frac = wet ? 0.7 : 0.5;
        if (s > 0.85) frac += 0.1;
        if (adapts && foldR < 0.8) frac += 0.15; // they call: charge them
        return raiseOrShove(ctx, (pot * frac).round());
      }
      if (s > 0.5 && !river && rng.nextDouble() < p.aggression * (ctx.inPosition ? 0.5 : 0.3)) {
        return raiseOrShove(ctx, (pot * (wet ? 0.5 : 0.33)).round());
      }
      var bluffChance = p.bluffing *
          (ctx.opponents == 1 ? 1.4 : 0.5) *
          (ctx.isPreflopAggressor && ctx.street == Street.flop ? 1.6 : 1.0) *
          (ctx.aggressorLastStreet ? 1.4 : 1.0) *
          (ctx.inPosition ? 1.25 : 0.8) *
          (outs >= 8 ? 1.8 : outs > 0 ? 1.3 : 1.0);
      if (adapts) bluffChance *= foldR * foldR;
      if (rng.nextDouble() < bluffChance) {
        return raiseOrShove(ctx, (pot * (wet ? 0.66 : 0.4)).round());
      }
      return const PlayerAction.check();
    }

    final potOdds = l.callAmount / (pot + l.callAmount);
    final raiseLine = 0.80 - 0.08 * p.aggression + 0.04 * ctx.streetRaises;
    if (s > raiseLine && l.canRaise) {
      final to = l.currentBet + max<int>(l.minRaiseTo - l.currentBet, ((pot + l.callAmount) * 0.75).round());
      return raiseOrShove(ctx, to);
    }
    // Earlier streets need a margin: more betting is still to come.
    final streetMargin = switch (ctx.street) { Street.flop => 0.09, Street.turn => 0.05, _ => 0.01 };
    final callNeed = potOdds - 0.12 * p.stickiness + streetMargin + 0.02 * ctx.streetRaises;
    if (eq >= callNeed) {
      return const PlayerAction.call();
    }
    var raiseBluff = p.bluffing * 0.3 * (outs >= 8 ? 1.8 : 1.0);
    if (adapts) raiseBluff *= foldR * foldR;
    if (l.canRaise && ctx.opponents == 1 && !river && rng.nextDouble() < raiseBluff) {
      return raiseOrShove(ctx, l.currentBet * 3);
    }
    return const PlayerAction(ActionType.fold);
  }

  /// Two or more of a suit, or three ranks within a five-rank window.
  static bool _isWet(List<int> board) {
    final suits = List<int>.filled(4, 0);
    var mask = 0;
    for (final c in board) {
      suits[cardSuit(c)]++;
      mask |= 1 << cardRank(c);
    }
    if (suits.reduce(max) >= (board.length == 3 ? 2 : 3)) return true;
    final m = mask << 1 | ((mask >> 12) & 1);
    for (var lo = 0; lo <= 9; lo++) {
      var count = 0;
      for (var i = 0; i < 5; i++) {
        if ((m >> (lo + i)) & 1 == 1) count++;
      }
      if (count >= 3) return true;
    }
    return false;
  }

  /// Short-stacked tournament play (≤15bb): open-shove or fold, and call
  /// all-ins, from the push/fold charts the coach grades against. Each
  /// personality shifts the charts (a Rock tightens, a Wildcard widens), and
  /// expert bots check bubble calls with ICM. Null when not applicable.
  PlayerAction? _pushFold(BotContext ctx, Random rng) {
    final t = ctx.tournament;
    if (t == null || ctx.effectiveStackBb > 15) return null;
    final l = ctx.legal;
    final headsUp = ctx.stacksBefore.where((b) => b > 0).length == 2;
    final bucket = stackBucket(ctx.effectiveStackBb);
    final hand = startingHandIndex(ctx.hole[0], ctx.hole[1]);
    // Personality and skill: style widens or tightens the chart; noise blurs it.
    final style = sqrt((personality.looseness / 0.25).clamp(0.5, 2.2));
    double scaled(double w) => (w * style * (1 + (rng.nextDouble() - 0.5) * 2 * difficulty.noise * 2)).clamp(0.01, 1.0);

    if (ctx.preflopRaises == 0 && ctx.limpers == 0) {
      if (l.canCheck) return null; // big blind, walked or limped: normal play
      final width = scaled(shoveWidth(ctx.position, bucket, headsUp: headsUp));
      if (shoveRange(width).contains(hand) && l.canRaise) {
        return PlayerAction(l.isBet ? ActionType.bet : ActionType.raise, l.maxRaiseTo);
      }
      return const PlayerAction(ActionType.fold);
    }

    if (ctx.preflopRaises == 1 && ctx.allInAggressor != null) {
      final width = scaled(callWidth(ctx.openerPosition, ctx.position, bucket, headsUp: headsUp));
      var call = topFraction(width).contains(hand);
      // Expert bots near the money weigh the call in prize equity.
      if (difficulty == Difficulty.expert && t.playersLeft <= t.prizes.length + 2) {
        final shoverBb = ctx.stacksBefore[ctx.allInAggressor!] / ctx.bigBlind;
        final shoveW = shoveWidth(ctx.openerPosition ?? 'UTG', stackBucket(min(shoverBb, 15)), headsUp: headsUp);
        final e = monteCarloEquity(
          hole: ctx.hole,
          board: const [],
          opponents: 1,
          iterations: 500,
          rng: rng,
          opponentRanges: [shoveW],
        ).equity;
        call = ShoveCall.compute(ctx, e, shoveW).callIsBetter;
      }
      return call ? const PlayerAction.call() : const PlayerAction(ActionType.fold);
    }

    if (ctx.preflopRaises == 1 && l.canRaise) {
      // Facing a normal raise while short: re-shove a strong range or fold.
      final width = scaled(callWidth(ctx.openerPosition, ctx.position, bucket, headsUp: headsUp) * 0.8);
      if (topFraction(width).contains(hand)) return PlayerAction(ActionType.raise, l.maxRaiseTo);
      return const PlayerAction(ActionType.fold);
    }
    return null;
  }
}
