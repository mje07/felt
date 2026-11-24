import 'package:poker_engine/poker_engine.dart';

/// A multi-table tournament on the lobby's schedule.
class TournamentEvent {
  const TournamentEvent({
    required this.name,
    required this.field,
    required this.buyIn,
    this.guarantee = 0,
    this.speed = BlindSpeed.turbo,
    this.stack = StartingStack.standard,
    required this.blurb,
  });

  final String name, blurb;
  final int field, buyIn, guarantee;
  final BlindSpeed speed;
  final StartingStack stack;

  /// Buy-ins from every entrant, or the guarantee if that's bigger.
  int get prizePool => buyIn * field > guarantee ? buyIn * field : guarantee;
  int get firstPrize => mttPrizes(field, prizePool).first;
  int get paidPlaces => mttPaidPlaces(field);
  bool get isFreeroll => buyIn == 0;
}

/// From a freeroll to the million-chip buy-in.
const tournamentEvents = [
  TournamentEvent(
    name: 'Daily Freeroll',
    field: 45,
    buyIn: 0,
    guarantee: 5000,
    speed: BlindSpeed.hyper,
    blurb: 'Free to enter. The top 7 share 5,000.',
  ),
  TournamentEvent(name: 'Nightly 500', field: 45, buyIn: 500, blurb: 'A quick evening tournament.'),
  TournamentEvent(name: 'Turbo 2K', field: 90, buyIn: 2000, speed: BlindSpeed.hyper, blurb: 'Fast blinds, big field.'),
  TournamentEvent(
    name: 'Sunday Million',
    field: 180,
    buyIn: 5000,
    guarantee: 1000000,
    speed: BlindSpeed.regular,
    stack: StartingStack.deep,
    blurb: 'The weekly flagship: 1,000,000 guaranteed.',
  ),
  TournamentEvent(
    name: 'High Roller',
    field: 45,
    buyIn: 25000,
    speed: BlindSpeed.regular,
    stack: StartingStack.deep,
    blurb: 'Deep stacks, tough field.',
  ),
  TournamentEvent(
    name: 'Super High Roller',
    field: 18,
    buyIn: 100000,
    speed: BlindSpeed.regular,
    stack: StartingStack.deep,
    blurb: 'Two tables, a 1,800,000 pool.',
  ),
  TournamentEvent(
    name: 'Main Event',
    field: 180,
    buyIn: 250000,
    guarantee: 50000000,
    speed: BlindSpeed.regular,
    stack: StartingStack.deep,
    blurb: 'The year\'s biggest prize: 50,000,000 guaranteed.',
  ),
  TournamentEvent(
    name: 'The Big One',
    field: 45,
    buyIn: 1000000,
    speed: BlindSpeed.regular,
    stack: StartingStack.deep,
    blurb: 'A one-million buy-in. Only legends sit down.',
  ),
];

/// Sit & Go buy-ins, from micro to nosebleed.
const sngBuyIns = [100, 500, 2500, 10000, 25000, 100000, 250000, 1000000];
