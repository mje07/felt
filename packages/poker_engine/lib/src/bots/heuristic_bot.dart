import 'dart:math';

import '../equity.dart';
import '../game_state.dart';
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
    final p = personality;
    final l = ctx.legal;
    final bb = ctx.bigBlind;
    // Lower is stronger: 0.02 ≈ top 2% of hands.
    var pct = preflopPercentile(ctx.hole[0], ctx.hole[1]);
    pct += (rng.nextDouble() - 0.5) * difficulty.noise;

    // Later position (fewer players behind) plays wider.
    final behind = ctx.playersAfter;
    final lateness = 1 - (behind / max(1, ctx.opponents)).clamp(0.0, 1.0);
    final range = p.looseness * (0.65 + 0.7 * lateness) * (ctx.opponents <= 2 ? 1.6 : 1.0);
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

    if (ctx.preflopRaises == 1) {
      final threeBet = max(0.025, range * 0.22 * (0.4 + p.aggression));
      final callRange = range * (0.5 + 0.5 * p.stickiness) * (costFrac > 0.25 ? 0.4 : 1);
      if (pct <= threeBet || (pct < 0.35 && rng.nextDouble() < p.bluffing * 0.25)) {
        final to = (l.currentBet * (behind == 0 ? 3.0 : 3.6)).round();
        return raiseOrShove(ctx, to);
      }
      if (pct <= callRange) return l.canCheck ? const PlayerAction.check() : const PlayerAction.call();
      return _passive(ctx);
    }

    // Facing a 3-bet or more.
    if (pct <= 0.025 + 0.01 * p.aggression) {
      return raiseOrShove(ctx, (l.currentBet * 2.3).round());
    }
    if (pct <= 0.05 + 0.08 * p.stickiness && costFrac < 0.5) {
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

    if (l.toCall == 0) {
      final valueLine = 0.64 - 0.10 * p.aggression;
      if (s > valueLine) {
        final frac = s > 0.82 ? 0.75 : 0.55;
        return raiseOrShove(ctx, (pot * frac).round());
      }
      if (s > 0.5 && rng.nextDouble() < p.aggression * 0.45 && !river) {
        return raiseOrShove(ctx, (pot * 0.4).round());
      }
      final bluffChance = p.bluffing *
          (ctx.opponents == 1 ? 1.4 : 0.5) *
          (ctx.isPreflopAggressor ? 1.6 : 1.0);
      if (rng.nextDouble() < bluffChance) {
        return raiseOrShove(ctx, (pot * 0.5).round());
      }
      return const PlayerAction.check();
    }

    final potOdds = l.callAmount / (pot + l.callAmount);
    final raiseLine = 0.80 - 0.08 * p.aggression + 0.04 * ctx.streetRaises;
    if (s > raiseLine && l.canRaise) {
      final to = l.currentBet + max<int>(l.minRaiseTo - l.currentBet, ((pot + l.callAmount) * 0.75).round());
      return raiseOrShove(ctx, to);
    }
    final callNeed = potOdds - 0.12 * p.stickiness + 0.03;
    if (eq >= callNeed || s >= potOdds + 0.05) {
      return const PlayerAction.call();
    }
    if (l.canRaise && ctx.opponents == 1 && !river && rng.nextDouble() < p.bluffing * 0.3) {
      return raiseOrShove(ctx, l.currentBet * 3);
    }
    return const PlayerAction(ActionType.fold);
  }
}
