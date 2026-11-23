import 'dart:math';

import '../game_state.dart';
import '../rules.dart';
import '../stats.dart' show positionOf;

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
    this.position = 'UTG',
    this.openerPosition,
    this.effectiveStackBb = 100,
    this.opponentNames = const [],
    this.tournament,
    this.stacksBefore = const [],
    this.committed = const [],
    this.allInAggressor,
    this.allInAggressorName,
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

  /// Position label (UTG, MP, HJ, CO, BTN, SB, BB).
  final String position;

  /// Position of the first preflop raiser, if any.
  final String? openerPosition;

  /// Smaller of our stack and the biggest live opponent stack, in big blinds.
  final double effectiveStackBb;

  /// Live opponents' names, aligned with [opponentRanges].
  final List<String> opponentNames;

  /// Set in tournaments: prizes and players left (for ICM).
  final TournamentInfo? tournament;

  /// Per seat: chips at the start of the hand, and chips committed so far.
  final List<int> stacksBefore, committed;

  /// Seat of an opponent whose bet/raise put them all-in (we face a shove).
  final int? allInAggressor;
  final String? allInAggressorName;
}

abstract interface class Bot {
  PlayerAction decide(BotContext ctx, Random rng);
}

/// Builds the bot's view of [s] for the player to act.
BotContext buildBotContext(HandState s, {TournamentInfo? tournament}) {
  final legal = legalActions(s);
  final me = s.seats[s.toAct];
  final raisedPre = <int>{};
  final postflopAggression = <int, int>{};
  final calledPre = <int>{};
  var preflopRaises = 0, limpers = 0, streetRaises = 0;
  var aggressor = -1, opener = -1;
  for (final e in s.log) {
    if (e is! PlayerActed) continue;
    final aggressive = e.type == ActionType.bet || e.type == ActionType.raise;
    if (e.street == Street.preflop) {
      if (aggressive) {
        preflopRaises++;
        raisedPre.add(e.seat);
        aggressor = e.seat;
        if (opener < 0) opener = e.seat;
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
  final active = [for (final p in s.seats) if (p.inHand) p.index];
  final myTotal = me.stack + me.streetBet;
  final biggestOther = live.fold(0, (m, p) => max(m, p.stack + p.streetBet));
  final effective = min(myTotal, biggestOther);

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
    position: positionOf(seat: me.index, button: s.button, bbSeat: s.bigBlindSeat, active: active),
    openerPosition: opener < 0
        ? null
        : positionOf(seat: opener, button: s.button, bbSeat: s.bigBlindSeat, active: active),
    effectiveStackBb: effective / s.bigBlind,
    opponentNames: [for (final p in live) p.name],
    tournament: tournament,
    stacksBefore: [for (final p in s.seats) p.inHand ? p.stack + p.totalBet : 0],
    committed: [for (final p in s.seats) p.totalBet],
    allInAggressor: s.lastAggressor >= 0 && s.seats[s.lastAggressor].allIn && s.seats[s.lastAggressor].live && s.lastAggressor != me.index
        ? s.lastAggressor
        : null,
    allInAggressorName: s.lastAggressor >= 0 ? s.seats[s.lastAggressor].name : null,
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

/// What the coach needs to know about a tournament for ICM.
class TournamentInfo {
  const TournamentInfo({required this.prizes, required this.playersLeft});

  /// Prize for 1st, 2nd, ... (paid places only).
  final List<int> prizes;
  final int playersLeft;

  int get pool => prizes.fold(0, (a, b) => a + b);
  bool get onBubble => playersLeft == prizes.length + 1;
}
