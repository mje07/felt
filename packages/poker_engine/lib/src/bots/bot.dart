import 'dart:math';

import '../game_state.dart';
import '../rules.dart';
import '../stats.dart' show positionOf;
import '../range_model.dart';
import 'reads.dart';

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
    this.opponentCombos = const [],
    this.inPosition = false,
    this.aggressorLastStreet = false,
    this.opponentFoldRatio = const [],
    this.aggressorPfrRatio = 1.0,
  });

  /// Postflop: each live opponent's range as explicit combos, narrowed by
  /// what they did on each street of *this* board (see `range_model.dart`).
  /// Empty preflop, where [opponentRanges] widths are used instead.
  final List<List<int>> opponentCombos;

  /// Postflop: nobody left to act after us on this street.
  final bool inPosition;

  /// We made the last bet or raise on the previous street (we can barrel).
  final bool aggressorLastStreet;

  /// Per live opponent: how often they fold to bets compared with a typical
  /// player (1.0 = average, 0.5 = half as often). From session reads.
  final List<double> opponentFoldRatio;

  /// Preflop: how often the last raiser raises compared with a typical
  /// player (2.0 = twice as often, so a much wider range). From session reads.
  final double aggressorPfrRatio;

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
/// Pass [reads] (session-long tendencies) so ranges and bluffing adapt to
/// how each opponent actually plays.
BotContext buildBotContext(HandState s, {TournamentInfo? tournament, TableReads? reads}) {
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

  // Preflop action sets a starting range, scaled by how loosely this player
  // has been raising and calling (session reads); every postflop bet or
  // raise narrows it further (people bet stronger hands).
  double preWidth(Seat p) {
    final t = reads?.of(p.name);
    if (raisedPre.contains(p.index)) {
      final ratio = t?.pfrRatio ?? 1.0;
      return preflopRaises >= 2 ? (0.1 * ratio).clamp(0.03, 0.4) : (0.22 * ratio).clamp(0.06, 0.8);
    }
    if (calledPre.contains(p.index)) return (0.5 * (t?.vpip ?? 0.28) / 0.28).clamp(0.15, 1.0);
    return 1.0;
  }

  double rangeFor(Seat p) {
    final base = preWidth(p);
    final n = postflopAggression[p.index] ?? 0;
    return max(0.04, base * pow(0.55, n));
  }

  final ranges = [for (final p in live) rangeFor(p)];

  // Postflop: explicit combo ranges, replaying each opponent's actions
  // against the board as it stood on that street.
  var combos = const <List<int>>[];
  var aggressorLastStreet = false;
  if (s.street != Street.preflop && s.street != Street.showdown) {
    final dead = [...me.hole, ...s.board];
    final byWidth = <double, List<int>>{};
    final current = {
      for (final p in live) p.index: byWidth.putIfAbsent(preWidth(p), () => preflopRange(preWidth(p), dead: dead)),
    };
    var board = const <int>[];
    var lastAggr = -1, prevStreetAggr = -1;
    var street = Street.preflop;
    for (final e in s.log) {
      if (e is StreetDealt) {
        board = e.board;
        prevStreetAggr = lastAggr;
        lastAggr = -1;
        street = e.street;
      } else if (e is PlayerActed) {
        final aggressive = e.type == ActionType.bet || e.type == ActionType.raise;
        if (aggressive) lastAggr = e.seat;
        if (street == Street.preflop || !current.containsKey(e.seat)) continue;
        final action = switch (e.type) {
          ActionType.bet => RangeAction.bet,
          ActionType.raise => RangeAction.raise,
          ActionType.call => RangeAction.call,
          ActionType.check => RangeAction.check,
          ActionType.fold => null,
        };
        if (action != null) {
          final agg = reads?.of(s.seats[e.seat].name).aggressionRatio ?? 1.0;
          current[e.seat] = narrowRange(current[e.seat]!, board, action, aggression: agg);
        }
      }
    }
    combos = [for (final p in live) current[p.index]!];
    // On the flop the previous street is preflop.
    aggressorLastStreet = s.street == Street.flop ? aggressor == me.index : prevStreetAggr == me.index;
  }
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
    opponentCombos: combos,
    inPosition: s.street != Street.preflop && playersAfter == 0,
    aggressorLastStreet: aggressorLastStreet,
    opponentFoldRatio: [for (final p in live) reads?.of(p.name).foldRatio ?? 1.0],
    aggressorPfrRatio: aggressor >= 0 && aggressor != me.index ? reads?.of(s.seats[aggressor].name).pfrRatio ?? 1.0 : 1.0,
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
