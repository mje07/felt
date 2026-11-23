import 'dart:math';

import 'bots/heuristic_bot.dart';
import 'bots/personality.dart';
import 'game_state.dart';
import 'rng.dart';
import 'rules.dart';

/// Someone occupying a seat across hands.
class TablePlayer {
  TablePlayer({
    required this.name,
    required this.stack,
    this.isHuman = false,
    this.personality,
    this.difficulty = Difficulty.standard,
    this.sittingOut = false,
  });

  final String name;
  int stack;
  final bool isHuman;
  final Personality? personality;
  final Difficulty difficulty;
  bool sittingOut;

  /// Total chips this player has bought in for (for net results).
  int buyIns = 0;

  HeuristicBot? get bot =>
      isHuman ? null : HeuristicBot(personality ?? Personality.tag, difficulty);
}

/// A ring cash game: tracks seats, the button and hand numbers.
class CashGame {
  CashGame({
    required this.seats,
    required this.smallBlind,
    required this.bigBlind,
    Random? rng,
  }) : rng = rng ?? secureRandom() {
    for (final p in seats) {
      if (p != null) p.buyIns = p.stack;
    }
  }

  final List<TablePlayer?> seats;
  final int smallBlind, bigBlind;
  final Random rng;
  int button = -1;
  int handNumber = 0;

  bool _eligible(int i) {
    final p = seats[i];
    return p != null && !p.sittingOut && p.stack > 0;
  }

  bool get canDeal =>
      [for (var i = 0; i < seats.length; i++) _eligible(i)].where((e) => e).length >= 2;

  HandState startNextHand({List<int>? deck}) {
    if (!canDeal) throw StateError('Not enough players');
    final n = seats.length;
    if (button < 0) {
      final candidates = [for (var i = 0; i < n; i++) if (_eligible(i)) i];
      button = candidates[rng.nextInt(candidates.length)];
    } else {
      for (var i = 1; i <= n; i++) {
        final s = (button + i) % n;
        if (_eligible(s)) {
          button = s;
          break;
        }
      }
    }
    handNumber++;
    return startHand(
      players: [
        for (var i = 0; i < n; i++)
          _eligible(i) ? SeatSetup(seats[i]!.name, seats[i]!.stack) : null,
      ],
      button: button,
      smallBlind: smallBlind,
      bigBlind: bigBlind,
      handNumber: handNumber,
      rng: rng,
      deck: deck,
    );
  }

  /// Copies final stacks back to the players.
  void settle(HandState done) {
    for (final s in done.seats) {
      if (s.inHand) seats[s.index]!.stack = s.stack;
    }
  }

  void rebuy(int seat, int amount) {
    final p = seats[seat]!;
    p.stack += amount;
    p.buyIns += amount;
  }
}
