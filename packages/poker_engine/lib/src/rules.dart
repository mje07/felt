import 'dart:math';

import 'evaluator.dart';
import 'game_state.dart';
import 'pots.dart';
import 'rng.dart';

/// Someone sitting at the table when a hand starts.
class SeatSetup {
  const SeatSetup(this.name, this.stack);
  final String name;
  final int stack;
}

class IllegalActionException implements Exception {
  IllegalActionException(this.message);
  final String message;
  @override
  String toString() => 'IllegalActionException: $message';
}

/// Seat order helpers.
int _next(List<Seat> seats, int from, bool Function(Seat) test) {
  final n = seats.length;
  for (var i = 1; i <= n; i++) {
    final s = seats[(from + i) % n];
    if (test(s)) return s.index;
  }
  return -1;
}

/// Starts a hand. [players] is indexed by seat; null = empty seat.
/// Seats with no chips are dealt out. [button] must be a seat that is dealt in.
/// Pass [deck] to stack the deck (tests); otherwise it is shuffled with [rng].
HandState startHand({
  required List<SeatSetup?> players,
  required int button,
  required int smallBlind,
  required int bigBlind,
  int ante = 0,
  required int handNumber,
  Random? rng,
  List<int>? deck,
}) {
  final seats = <Seat>[
    for (var i = 0; i < players.length; i++)
      Seat(
        index: i,
        name: players[i]?.name ?? '',
        stack: players[i]?.stack ?? 0,
        inHand: (players[i]?.stack ?? 0) > 0,
      ),
  ];
  final active = seats.where((s) => s.inHand).length;
  if (active < 2) throw ArgumentError('Need at least two players with chips');
  if (!seats[button].inHand) throw ArgumentError('Button seat $button is empty');

  final cards = deck ?? List<int>.generate(52, (i) => i);
  if (deck == null) shuffle(cards, rng ?? secureRandom());

  // Heads-up: the button posts the small blind.
  final sbSeat = active == 2 ? button : _next(seats, button, (s) => s.inHand);
  final bbSeat = _next(seats, sbSeat, (s) => s.inHand);

  final state = HandState(
    handNumber: handNumber,
    smallBlind: smallBlind,
    bigBlind: bigBlind,
    button: button,
    smallBlindSeat: sbSeat,
    bigBlindSeat: bbSeat,
    seats: seats,
    deck: cards,
    lastRaiseSize: bigBlind,
    startingChips: seats.fold(0, (s, p) => s + p.stack),
  );
  final log = state.log;
  log.add(HandStarted(handNumber, button, sbSeat, bbSeat, smallBlind, bigBlind,
      [for (final s in seats) s.toJson()], ante: ante));

  void post(int seat, int amount, bool big) {
    final s = seats[seat];
    final a = min(amount, s.stack);
    s.stack -= a;
    s.streetBet += a;
    s.totalBet += a;
    if (s.stack == 0) s.allIn = true;
    log.add(BlindPosted(seat, a, isBig: big));
  }

  post(sbSeat, smallBlind, false);
  post(bbSeat, bigBlind, true);
  // Big-blind ante: dead money (counts towards the pot, not the street bet).
  if (ante > 0) {
    final b = seats[bbSeat];
    final a = min(ante, b.stack);
    if (a > 0) {
      b.stack -= a;
      b.totalBet += a;
      if (b.stack == 0) b.allIn = true;
      log.add(AntePosted(bbSeat, a));
    }
  }
  // Players must call the full big blind even if the BB is short.
  state.currentBet = bigBlind;

  // Deal two rounds, one card at a time, starting with the small blind.
  final order = <int>[];
  var seat = sbSeat;
  do {
    order.add(seat);
    seat = _next(seats, seat, (s) => s.inHand);
  } while (seat != sbSeat);
  for (var round = 0; round < 2; round++) {
    for (final i in order) {
      seats[i].hole.add(state.drawCard());
    }
  }
  log.add(HoleCardsDealt(order));

  state.toAct = _nextToAct(state, bbSeat);
  if (_roundComplete(state)) _progress(state);
  return state;
}

bool _needsToAct(HandState s, Seat p) =>
    p.canAct && (!p.hasActed || p.streetBet < s.currentBet);

int _nextToAct(HandState s, int from) =>
    _next(s.seats, from, (p) => _needsToAct(s, p));

bool _roundComplete(HandState s) {
  final actors = s.seats.where((p) => p.canAct).toList();
  if (actors.isEmpty) return true;
  if (actors.length == 1) {
    // Everyone else is all-in or folded: only act if facing a bet.
    final p = actors.first;
    final othersLive = s.seats.where((o) => o.live && o.index != p.index);
    if (othersLive.isEmpty) return true;
    return p.streetBet >= s.currentBet;
  }
  return actors.every((p) => p.hasActed && p.streetBet == s.currentBet);
}

/// The options open to the player whose turn it is.
LegalActions legalActions(HandState s) {
  if (s.isComplete || s.toAct < 0) {
    throw StateError('No player to act');
  }
  final p = s.seats[s.toAct];
  final toCall = max(0, s.currentBet - p.streetBet);
  final maxTo = p.streetBet + p.stack;
  final reopened =
      !p.hasActed || s.currentBet - p.actedAtLevel >= s.lastRaiseSize;
  final othersCanAct =
      s.seats.any((o) => o.index != p.index && o.canAct);
  final canRaise = p.stack > toCall && reopened && othersCanAct;
  final isBet = s.currentBet == 0;
  var minTo = isBet ? s.bigBlind : s.currentBet + s.lastRaiseSize;
  if (minTo > maxTo) minTo = maxTo;
  return LegalActions(
    seat: p.index,
    canFold: toCall > 0,
    canCheck: toCall == 0,
    canCall: toCall > 0,
    callAmount: min(toCall, p.stack),
    toCall: toCall,
    canRaise: canRaise,
    isBet: isBet,
    minRaiseTo: minTo,
    maxRaiseTo: maxTo,
    currentBet: s.currentBet,
    streetBet: p.streetBet,
  );
}

/// Applies [action] for the player to act and returns the new state.
/// New events are appended to the returned state's [HandState.log].
HandState applyAction(HandState state, PlayerAction action) {
  final s = state.copy();
  final legal = legalActions(s);
  final p = s.seats[s.toAct];
  var type = action.type;
  var added = 0;

  switch (type) {
    case ActionType.fold:
      if (!legal.canFold) throw IllegalActionException('Cannot fold: check is free');
      p.folded = true;
    case ActionType.check:
      if (!legal.canCheck) throw IllegalActionException('Cannot check facing ${legal.toCall}');
    case ActionType.call:
      if (!legal.canCall) throw IllegalActionException('Nothing to call');
      added = legal.callAmount;
    case ActionType.bet:
    case ActionType.raise:
      if (!legal.canRaise) throw IllegalActionException('Raising is not allowed');
      final to = action.amount;
      if (to < legal.minRaiseTo || to > legal.maxRaiseTo) {
        throw IllegalActionException(
            'Raise to $to outside ${legal.minRaiseTo}..${legal.maxRaiseTo}');
      }
      type = legal.isBet ? ActionType.bet : ActionType.raise;
      added = to - p.streetBet;
      final increment = to - s.currentBet;
      if (increment >= s.lastRaiseSize) s.lastRaiseSize = increment;
      s.currentBet = to;
      s.lastAggressor = p.index;
  }

  p.stack -= added;
  p.streetBet += added;
  p.totalBet += added;
  if (p.stack == 0 && !p.folded) p.allIn = true;
  p.hasActed = true;
  p.actedAtLevel = s.currentBet;
  s.log.add(PlayerActed(p.index, type, added, p.streetBet,
      allIn: p.allIn, street: s.street));

  if (s.liveSeats.length == 1 || _roundComplete(s)) {
    _progress(s);
  } else {
    s.toAct = _nextToAct(s, p.index);
  }
  assert(s.totalChips == s.startingChips, 'Chips not conserved');
  return s;
}

/// Returns the uncalled part of the biggest street bet.
void _returnUncalled(HandState s) {
  Seat? top;
  var second = 0;
  for (final p in s.seats) {
    if (top == null || p.streetBet > top.streetBet) {
      if (top != null) second = max(second, top.streetBet);
      top = p;
    } else {
      second = max(second, p.streetBet);
    }
  }
  if (top != null && top.streetBet > second) {
    final diff = top.streetBet - second;
    top.streetBet -= diff;
    top.totalBet -= diff;
    top.stack += diff;
    if (top.allIn && top.stack > 0) top.allIn = false;
    s.log.add(UncalledReturned(top.index, diff));
  }
}

/// Called whenever a betting round closes: deals streets, runs out the
/// board when nobody can bet, or finishes the hand.
void _progress(HandState s) {
  while (true) {
    _returnUncalled(s);
    if (s.liveSeats.length == 1) {
      _finish(s);
      return;
    }
    if (s.street == Street.river) {
      _finish(s);
      return;
    }
    // Next street.
    for (final p in s.seats) {
      p.streetBet = 0;
      p.hasActed = false;
      p.actedAtLevel = 0;
    }
    s.currentBet = 0;
    s.lastRaiseSize = s.bigBlind;
    s.deckPos++; // burn
    final n = s.street == Street.preflop ? 3 : 1;
    final dealt = [for (var i = 0; i < n; i++) s.drawCard()];
    s.board.addAll(dealt);
    s.street = Street.values[s.street.index + 1];
    s.log.add(StreetDealt(s.street, dealt, List.of(s.board)));

    if (s.seats.where((p) => p.canAct).length >= 2) {
      s.toAct = _nextToAct(s, s.button);
      return;
    }
    // Zero or one player can still bet: keep dealing.
  }
}

void _finish(HandState s) {
  s.toAct = -1;
  final pots = buildPots(s.seats);
  final live = s.liveSeats.toList();
  final values = <int, int>{};
  if (live.length > 1) {
    s.street = Street.showdown;
    final hands = <int, (List<int>, int)>{};
    for (final p in live) {
      final v = evaluate([...p.hole, ...s.board]);
      values[p.index] = v;
      hands[p.index] = (List.of(p.hole), v);
    }
    s.log.add(ShowdownRevealed(hands));
  }
  final awards = awardPots(
    pots: pots,
    handValues: values,
    button: s.button,
    seatCount: s.seats.length,
  );
  for (final a in awards) {
    for (final e in a.shares.entries) {
      s.seats[e.key].stack += e.value;
    }
    s.log.add(PotAwarded(a));
  }
  s.awards.addAll(awards);
  // Chips have moved from bets to stacks.
  for (final p in s.seats) {
    p.streetBet = 0;
    p.totalBet = 0;
  }
  s.isComplete = true;
  s.log.add(HandEnded({for (final p in s.seats) if (p.inHand) p.index: p.stack}));
}
