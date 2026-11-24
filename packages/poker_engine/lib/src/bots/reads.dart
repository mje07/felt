import '../game_state.dart';

/// What a player has shown over a session, as seen by everyone at the table
/// (public actions only, never hidden cards).
class PlayerTendencies {
  /// Hands dealt in, and how many they voluntarily played / raised preflop.
  int hands = 0, vpipHands = 0, pfrHands = 0;

  static const _vpipPrior = 0.28, _pfrPrior = 0.18, _preWeight = 25.0;

  /// Share of hands played voluntarily preflop (≈0.28 typical).
  double get vpip => (vpipHands + _vpipPrior * _preWeight) / (hands + _preWeight);

  /// Share of hands raised preflop (≈0.18 typical).
  double get pfr => (pfrHands + _pfrPrior * _preWeight) / (hands + _preWeight);

  /// How much more often they raise preflop than a typical player.
  double get pfrRatio => pfr / _pfrPrior;

  /// Postflop decisions, and how many of them were bets or raises.
  int postflopActions = 0, postflopAggressive = 0;

  /// Times they faced a postflop bet, and how many of those they folded.
  int facedBets = 0, foldedToBets = 0;

  // Priors (in observations) keep early reads close to an average player.
  static const _aggPrior = 0.35, _foldPrior = 0.45, _weight = 20.0;

  /// Share of postflop decisions that were bets or raises (≈0.35 typical).
  double get aggression =>
      (postflopAggressive + _aggPrior * _weight) / (postflopActions + _weight);

  /// How often they fold to a postflop bet (≈0.45 typical).
  double get foldToBet => (foldedToBets + _foldPrior * _weight) / (facedBets + _weight);

  /// How much more (or less) often they bet than a typical player.
  double get aggressionRatio => aggression / _aggPrior;

  /// How much more (or less) often they fold than a typical player.
  double get foldRatio => foldToBet / _foldPrior;
}

/// Session-long reads on everyone at the table, keyed by player name.
/// Feed every finished hand to [observe].
class TableReads {
  final Map<String, PlayerTendencies> _byName = {};

  PlayerTendencies of(String name) => _byName.putIfAbsent(name, PlayerTendencies.new);

  void observe(HandState done) {
    final volunteered = <int>{}, raised = <int>{};
    for (final p in done.seats) {
      if (p.inHand) of(p.name).hands++;
    }
    var street = Street.preflop;
    var facing = false;
    for (final e in done.log) {
      if (e is StreetDealt) {
        street = e.street;
        facing = false;
      } else if (e is PlayerActed && street == Street.preflop) {
        if (e.type != ActionType.fold && e.type != ActionType.check) volunteered.add(e.seat);
        if (e.type == ActionType.raise || e.type == ActionType.bet) raised.add(e.seat);
      } else if (e is PlayerActed && street != Street.preflop) {
        final t = of(done.seats[e.seat].name);
        t.postflopActions++;
        final aggressive = e.type == ActionType.bet || e.type == ActionType.raise;
        if (aggressive) t.postflopAggressive++;
        if (facing) {
          t.facedBets++;
          if (e.type == ActionType.fold) t.foldedToBets++;
        }
        if (aggressive) facing = true;
      }
    }
    for (final seat in volunteered) {
      of(done.seats[seat].name).vpipHands++;
    }
    for (final seat in raised) {
      of(done.seats[seat].name).pfrHands++;
    }
  }

  void clear() => _byName.clear();
}
