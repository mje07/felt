/// Playing style. All knobs are 0..1.
class Personality {
  const Personality({
    required this.id,
    required this.label,
    required this.looseness,
    required this.aggression,
    required this.bluffing,
    required this.stickiness,
  });

  final String id, label;

  /// Roughly the fraction of hands played preflop (VPIP).
  final double looseness;

  /// Tendency to bet/raise rather than check/call.
  final double aggression;

  /// Frequency of bets with weak hands.
  final double bluffing;

  /// Reluctance to fold (calling-station factor).
  final double stickiness;

  static const rock = Personality(
      id: 'rock', label: 'Rock', looseness: 0.13, aggression: 0.45, bluffing: 0.03, stickiness: 0.0);
  static const tag = Personality(
      id: 'tag', label: 'Shark', looseness: 0.21, aggression: 0.75, bluffing: 0.10, stickiness: 0.05);
  static const lag = Personality(
      id: 'lag', label: 'Maverick', looseness: 0.34, aggression: 0.85, bluffing: 0.18, stickiness: 0.1);
  static const station = Personality(
      id: 'station', label: 'Station', looseness: 0.45, aggression: 0.2, bluffing: 0.03, stickiness: 0.65);
  static const maniac = Personality(
      id: 'maniac', label: 'Wildcard', looseness: 0.55, aggression: 0.95, bluffing: 0.3, stickiness: 0.3);

  static const all = [rock, tag, lag, station, maniac];

  static Personality byId(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => tag);
}

enum Difficulty {
  casual(samples: 250, noise: 0.12, rangeReading: false),
  standard(samples: 700, noise: 0.06, rangeReading: true),
  expert(samples: 1800, noise: 0.02, rangeReading: true);

  const Difficulty({
    required this.samples,
    required this.noise,
    required this.rangeReading,
  });

  /// Monte Carlo iterations per postflop decision.
  final int samples;

  /// Std-dev-ish error added to equity estimates (mistakes).
  final double noise;

  /// Whether to narrow opponents' ranges by their preflop actions.
  final bool rangeReading;
}
