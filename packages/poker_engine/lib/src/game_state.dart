import 'card.dart';

enum Street { preflop, flop, turn, river, showdown }

enum ActionType { fold, check, call, bet, raise }

/// A player decision. For [ActionType.bet]/[ActionType.raise], [amount] is the
/// total the player's street bet becomes ("raise to"). Otherwise it is ignored.
class PlayerAction {
  const PlayerAction(this.type, [this.amount = 0]);
  const PlayerAction.fold() : this(ActionType.fold);
  const PlayerAction.check() : this(ActionType.check);
  const PlayerAction.call() : this(ActionType.call);
  const PlayerAction.raiseTo(int to) : this(ActionType.raise, to);

  final ActionType type;
  final int amount;

  @override
  String toString() =>
      amount > 0 ? '${type.name} $amount' : type.name;
}

/// What the player to act may do.
class LegalActions {
  const LegalActions({
    required this.seat,
    required this.canFold,
    required this.canCheck,
    required this.canCall,
    required this.callAmount,
    required this.canRaise,
    required this.isBet,
    required this.minRaiseTo,
    required this.maxRaiseTo,
    required this.toCall,
    required this.currentBet,
    required this.streetBet,
  });

  final int seat;
  final bool canFold, canCheck, canCall, canRaise;

  /// True when nobody has bet this street (the aggressive action is a "bet").
  final bool isBet;

  /// Chips the player adds by calling (capped by stack).
  final int callAmount;

  /// Full amount owed to match the current bet (may exceed stack).
  final int toCall;
  final int minRaiseTo, maxRaiseTo, currentBet, streetBet;
}

/// One seat at the table during a hand.
class Seat {
  Seat({
    required this.index,
    required this.name,
    required this.stack,
    this.inHand = true,
    List<int>? hole,
  }) : hole = hole ?? <int>[];

  final int index;
  final String name;
  int stack;
  bool inHand;
  int streetBet = 0;
  int totalBet = 0;
  List<int> hole;
  bool folded = false;
  bool allIn = false;
  bool hasActed = false;

  /// The street's current bet level right after this seat last acted.
  int actedAtLevel = 0;

  bool get live => inHand && !folded;
  bool get canAct => live && !allIn;

  Seat copy() => Seat(
        index: index,
        name: name,
        stack: stack,
        inHand: inHand,
        hole: List.of(hole),
      )
        ..streetBet = streetBet
        ..totalBet = totalBet
        ..folded = folded
        ..allIn = allIn
        ..hasActed = hasActed
        ..actedAtLevel = actedAtLevel;

  Map<String, Object?> toJson() => {
        'index': index,
        'name': name,
        'stack': stack,
        'inHand': inHand,
        'hole': hole,
      };
}

class Pot {
  const Pot(this.amount, this.eligible);
  final int amount;
  final List<int> eligible;

  @override
  String toString() => 'Pot($amount, $eligible)';
}

/// Result of awarding one pot.
class PotAward {
  const PotAward({
    required this.potIndex,
    required this.amount,
    required this.shares,
    this.handValue,
  });
  final int potIndex;
  final int amount;

  /// seat -> chips won from this pot.
  final Map<int, int> shares;

  /// Winning hand value, or null if uncontested.
  final int? handValue;

  Map<String, Object?> toJson() => {
        'potIndex': potIndex,
        'amount': amount,
        'shares': {for (final e in shares.entries) '${e.key}': e.value},
        'handValue': handValue,
      };
}

// ---------------------------------------------------------------- events

/// Events describe what happened, in order, so the UI can animate them.
sealed class GameEvent {
  const GameEvent();
  Map<String, Object?> toJson();
}

class HandStarted extends GameEvent {
  const HandStarted(this.handNumber, this.button, this.smallBlindSeat,
      this.bigBlindSeat, this.smallBlind, this.bigBlind, this.seats);
  final int handNumber, button, smallBlindSeat, bigBlindSeat, smallBlind,
      bigBlind;
  final List<Map<String, Object?>> seats;
  @override
  Map<String, Object?> toJson() => {
        'e': 'start',
        'hand': handNumber,
        'button': button,
        'sbSeat': smallBlindSeat,
        'bbSeat': bigBlindSeat,
        'sb': smallBlind,
        'bb': bigBlind,
        'seats': seats,
      };
}

class BlindPosted extends GameEvent {
  const BlindPosted(this.seat, this.amount, {required this.isBig});
  final int seat, amount;
  final bool isBig;
  @override
  Map<String, Object?> toJson() =>
      {'e': 'blind', 'seat': seat, 'amount': amount, 'big': isBig};
}

class HoleCardsDealt extends GameEvent {
  /// Seats in deal order (starting left of the button).
  const HoleCardsDealt(this.order);
  final List<int> order;
  @override
  Map<String, Object?> toJson() => {'e': 'deal', 'order': order};
}

class PlayerActed extends GameEvent {
  const PlayerActed(this.seat, this.type, this.added, this.streetBet,
      {required this.allIn, required this.street});
  final int seat;
  final ActionType type;

  /// Chips moved from stack this action.
  final int added;

  /// Seat's street bet after the action.
  final int streetBet;
  final bool allIn;
  final Street street;
  @override
  Map<String, Object?> toJson() => {
        'e': 'act',
        'seat': seat,
        'type': type.name,
        'added': added,
        'to': streetBet,
        'allIn': allIn,
        'street': street.name,
      };
}

class UncalledReturned extends GameEvent {
  const UncalledReturned(this.seat, this.amount);
  final int seat, amount;
  @override
  Map<String, Object?> toJson() =>
      {'e': 'uncalled', 'seat': seat, 'amount': amount};
}

class StreetDealt extends GameEvent {
  const StreetDealt(this.street, this.cards, this.board);
  final Street street;
  final List<int> cards;
  final List<int> board;
  @override
  Map<String, Object?> toJson() =>
      {'e': 'street', 'street': street.name, 'cards': cards};
}

class ShowdownRevealed extends GameEvent {
  const ShowdownRevealed(this.hands);

  /// seat -> (hole cards, hand value)
  final Map<int, (List<int>, int)> hands;
  @override
  Map<String, Object?> toJson() => {
        'e': 'showdown',
        'hands': {
          for (final e in hands.entries)
            '${e.key}': {'hole': e.value.$1, 'value': e.value.$2}
        },
      };
}

class PotAwarded extends GameEvent {
  const PotAwarded(this.award);
  final PotAward award;
  @override
  Map<String, Object?> toJson() => {'e': 'award', ...award.toJson()};
}

class HandEnded extends GameEvent {
  const HandEnded(this.stacks);
  final Map<int, int> stacks;
  @override
  Map<String, Object?> toJson() => {
        'e': 'end',
        'stacks': {for (final e in stacks.entries) '${e.key}': e.value},
      };
}

// ---------------------------------------------------------------- state

class HandState {
  HandState({
    required this.handNumber,
    required this.smallBlind,
    required this.bigBlind,
    required this.button,
    required this.smallBlindSeat,
    required this.bigBlindSeat,
    required this.seats,
    required this.deck,
    this.deckPos = 0,
    List<int>? board,
    this.street = Street.preflop,
    this.currentBet = 0,
    this.lastRaiseSize = 0,
    this.toAct = -1,
    this.isComplete = false,
    this.lastAggressor = -1,
    List<PotAward>? awards,
    List<GameEvent>? log,
    this.startingChips = 0,
  })  : board = board ?? <int>[],
        awards = awards ?? <PotAward>[],
        log = log ?? <GameEvent>[];

  final int handNumber, smallBlind, bigBlind, button, smallBlindSeat,
      bigBlindSeat;
  final List<Seat> seats;
  final List<int> deck;
  int deckPos;
  final List<int> board;
  Street street;
  int currentBet;

  /// Size of the last full bet/raise increment this street (min-raise basis).
  int lastRaiseSize;

  /// Seat to act, or -1 if nobody (hand complete).
  int toAct;
  bool isComplete;
  int lastAggressor;
  final List<PotAward> awards;

  /// Every event since the hand started.
  final List<GameEvent> log;

  /// Total chips at hand start (for conservation checks).
  final int startingChips;

  int get pot => seats.fold(0, (s, p) => s + p.totalBet);

  /// Chips in pots from previous streets (excludes current street bets).
  int get collectedPot => seats.fold(0, (s, p) => s + p.totalBet - p.streetBet);

  int get totalChips => seats.fold(0, (s, p) => s + p.stack + p.totalBet);

  Iterable<Seat> get liveSeats => seats.where((s) => s.live);

  int drawCard() => deck[deckPos++];

  HandState copy() => HandState(
        handNumber: handNumber,
        smallBlind: smallBlind,
        bigBlind: bigBlind,
        button: button,
        smallBlindSeat: smallBlindSeat,
        bigBlindSeat: bigBlindSeat,
        seats: [for (final s in seats) s.copy()],
        deck: deck,
        deckPos: deckPos,
        board: List.of(board),
        street: street,
        currentBet: currentBet,
        lastRaiseSize: lastRaiseSize,
        toAct: toAct,
        isComplete: isComplete,
        lastAggressor: lastAggressor,
        awards: List.of(awards),
        log: List.of(log),
        startingChips: startingChips,
      );

  @override
  String toString() {
    final b = StringBuffer('Hand #$handNumber ${street.name} '
        'board[${cardsToString(board)}] pot=$pot bet=$currentBet toAct=$toAct\n');
    for (final s in seats) {
      if (!s.inHand) continue;
      b.writeln('  ${s.index} ${s.name} stack=${s.stack} street=${s.streetBet} '
          'total=${s.totalBet}${s.folded ? ' folded' : ''}${s.allIn ? ' all-in' : ''}');
    }
    return b.toString();
  }
}
