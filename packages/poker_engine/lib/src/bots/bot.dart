import 'dart:math';

import '../game_state.dart';
import '../rules.dart';

/// Everything a bot may know when deciding. Plain data (isolate-safe):
/// it never exposes other players' hole cards.
class BotContext {
  const BotContext({
    required this.seat,
    required this.hole,
    required this.board,
    required this.street,
    required this.legal,
    required this.pot,
    required this.bigBlind,
    required this.stack,
    required this.opponents,
    required this.playersAfter,
    required this.preflopRaises,
    required this.limpers,
    required this.isPreflopAggressor,
    required this.opponentRanges,
    required this.streetRaises,
  });

  final int seat;
  final List<int> hole, board;
  final Street street;
  final LegalActions legal;

  /// Total chips in the middle, including current street bets.
  final int pot;
  final int bigBlind, stack;

  /// Live opponents still in the hand.
  final int opponents;

  /// Live players who act after this seat on this street (position).
  final int playersAfter;
  final int preflopRaises, limpers, streetRaises;
  final bool isPreflopAggressor;

  /// Assumed range width (0..1) per live opponent.
  final List<double> opponentRanges;
}

abstract interface class Bot {
  PlayerAction decide(BotContext ctx, Random rng);
}

/// Builds the bot's view of [s] for the player to act.
BotContext buildBotContext(HandState s) {
  final legal = legalActions(s);
  final me = s.seats[s.toAct];
  final raisedPre = <int>{};
  final postflopAggression = <int, int>{};
  final calledPre = <int>{};
  var preflopRaises = 0, limpers = 0, streetRaises = 0;
  var aggressor = -1;
  for (final e in s.log) {
    if (e is! PlayerActed) continue;
    final aggressive = e.type == ActionType.bet || e.type == ActionType.raise;
    if (e.street == Street.preflop) {
      if (aggressive) {
        preflopRaises++;
        raisedPre.add(e.seat);
        aggressor = e.seat;
      } else if (e.type == ActionType.call) {
        calledPre.add(e.seat);
        if (preflopRaises == 0) limpers++;
      }
    }
    if (e.street == s.street && aggressive) streetRaises++;
    if (e.street != Street.preflop && aggressive) {
      postflopAggression[e.seat] = (postflopAggression[e.seat] ?? 0) + 1;
    }
  }

  final n = s.seats.length;
  final start = s.street == Street.preflop ? s.bigBlindSeat : s.button;
  int dist(int seat) => (seat - start - 1 + n) % n;
  final myDist = dist(me.index);
  final live = s.liveSeats.where((p) => p.index != me.index).toList();
  final playersAfter = live.where((p) => p.canAct && dist(p.index) > myDist).length;

  // Preflop action sets a starting range; every postflop bet or raise
  // narrows it further (people bet stronger hands).
  double rangeFor(Seat p) {
    final base = raisedPre.contains(p.index)
        ? (preflopRaises >= 2 ? 0.1 : 0.22)
        : calledPre.contains(p.index)
            ? 0.5
            : 1.0;
    final n = postflopAggression[p.index] ?? 0;
    return max(0.04, base * pow(0.55, n));
  }

  final ranges = [for (final p in live) rangeFor(p)];

  return BotContext(
    seat: me.index,
    hole: List.of(me.hole),
    board: List.of(s.board),
    street: s.street,
    legal: legal,
    pot: s.pot,
    bigBlind: s.bigBlind,
    stack: me.stack,
    opponents: live.length,
    playersAfter: playersAfter,
    preflopRaises: preflopRaises,
    limpers: limpers,
    isPreflopAggressor: aggressor == me.index,
    opponentRanges: ranges,
    streetRaises: streetRaises,
  );
}

/// Clamps a desired raise-to into the legal window; shoves when the leftover
/// stack would be tiny relative to the pot.
PlayerAction raiseOrShove(BotContext ctx, int desiredTo) {
  final l = ctx.legal;
  if (!l.canRaise) return l.canCall ? const PlayerAction.call() : const PlayerAction.check();
  var to = desiredTo.clamp(l.minRaiseTo, l.maxRaiseTo);
  final leftover = l.maxRaiseTo - to;
  if (leftover < (ctx.pot + to) * 0.35) to = l.maxRaiseTo;
  return PlayerAction(l.isBet ? ActionType.bet : ActionType.raise, to);
}
