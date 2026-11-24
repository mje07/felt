import 'dart:math';

import 'bots/bot.dart';
import 'bots/reads.dart';
import 'cash_game.dart';
import 'game_state.dart';
import 'rng.dart';
import 'rules.dart';

/// Blinds and big-blind ante for one level.
class BlindLevel {
  const BlindLevel(this.smallBlind, this.bigBlind, [this.ante = 0]);
  final int smallBlind, bigBlind, ante;

  @override
  String toString() => ante > 0 ? '$smallBlind/$bigBlind · ante $ante' : '$smallBlind/$bigBlind';

  @override
  bool operator ==(Object other) =>
      other is BlindLevel && other.smallBlind == smallBlind && other.bigBlind == bigBlind && other.ante == ante;

  @override
  int get hashCode => Object.hash(smallBlind, bigBlind, ante);
}

/// The level table. Big-blind antes start at 100/200.
const blindLevels = [
  BlindLevel(10, 20),
  BlindLevel(15, 30),
  BlindLevel(25, 50),
  BlindLevel(50, 100),
  BlindLevel(75, 150),
  BlindLevel(100, 200, 200),
  BlindLevel(150, 300, 300),
  BlindLevel(200, 400, 400),
  BlindLevel(300, 600, 600),
  BlindLevel(400, 800, 800),
  BlindLevel(600, 1200, 1200),
  BlindLevel(800, 1600, 1600),
  BlindLevel(1000, 2000, 2000),
];

/// Level [index] (0-based); after the table runs out, blinds keep doubling.
BlindLevel levelAt(int index) {
  if (index < blindLevels.length) return blindLevels[index];
  final last = blindLevels.last;
  final f = 1 << (index - blindLevels.length + 1);
  return BlindLevel(last.smallBlind * f, last.bigBlind * f, last.ante * f);
}

/// How quickly blinds rise, in hands per level (offline vs bots, so levels
/// are counted in hands rather than minutes).
enum BlindSpeed {
  hyper('Hyper', 5),
  turbo('Turbo', 8),
  regular('Regular', 12);

  const BlindSpeed(this.label, this.handsPerLevel);
  final String label;
  final int handsPerLevel;
}

enum StartingStack {
  short('Short', 1000),
  standard('Standard', 1500),
  deep('Deep', 3000);

  const StartingStack(this.label, this.chips);
  final String label;
  final int chips;
}

enum PayoutStyle {
  winnerTakesAll('Winner takes all'),
  standard('Top places');

  const PayoutStyle(this.label);
  final String label;
}

/// Share of the pool for each paid place.
List<double> payoutFractions(PayoutStyle style, int players) {
  if (style == PayoutStyle.winnerTakesAll || players <= 4) return const [1.0];
  if (players <= 6) return const [0.65, 0.35];
  return const [0.5, 0.3, 0.2];
}

/// Prizes in chips for each paid place; rounding remainder goes to 1st.
List<int> prizesFor(PayoutStyle style, int players, int buyIn) {
  final pool = buyIn * players;
  final prizes = [for (final f in payoutFractions(style, players)) (pool * f).floor()];
  prizes[0] += pool - prizes.fold(0, (a, b) => a + b);
  return prizes;
}

class Elimination {
  const Elimination(this.seat, this.place);
  final int seat, place;
}

/// A single-table Sit & Go: fixed buy-in, no rebuys, rising blinds, last
/// player standing wins.
class Tournament {
  Tournament({
    required this.seats,
    required this.buyIn,
    this.speed = BlindSpeed.turbo,
    this.payoutStyle = PayoutStyle.standard,
    Random? rng,
  })  : rng = rng ?? secureRandom(),
        prizes = prizesFor(payoutStyle, seats.length, buyIn);

  final List<TablePlayer> seats;
  final int buyIn;
  final BlindSpeed speed;
  final PayoutStyle payoutStyle;
  final Random rng;

  /// Prize for 1st, 2nd, ... (only paid places).
  final List<int> prizes;

  int button = -1;

  /// Hands started so far.
  int handNumber = 0;

  /// Finishing place by seat (1 = winner), filled as players bust.
  final Map<int, int> places = {};

  int get startingPlayers => seats.length;
  int get prizePool => buyIn * seats.length;
  int get paidPlaces => prizes.length;

  bool _alive(int i) => seats[i].stack > 0 && !places.containsKey(i);
  List<int> get alive => [for (var i = 0; i < seats.length; i++) if (_alive(i)) i];
  int get playersLeft => alive.length;
  bool get isFinished => playersLeft <= 1;

  /// Level for the next hand to be dealt.
  int get levelIndex => handNumber ~/ speed.handsPerLevel;
  BlindLevel get currentLevel => levelAt(levelIndex);
  BlindLevel get nextLevel => levelAt(levelIndex + 1);
  int get handsUntilNextLevel => speed.handsPerLevel - handNumber % speed.handsPerLevel;

  int prizeFor(int seat) {
    final place = places[seat];
    return place != null && place <= prizes.length ? prizes[place - 1] : 0;
  }

  int? get winner => places.entries.where((e) => e.value == 1).map((e) => e.key).firstOrNull;

  HandState startNextHand({List<int>? deck}) {
    if (isFinished) throw StateError('Tournament is over');
    final n = seats.length;
    final live = alive;
    if (button < 0) {
      button = live[rng.nextInt(live.length)];
    } else {
      for (var i = 1; i <= n; i++) {
        final s = (button + i) % n;
        if (_alive(s)) {
          button = s;
          break;
        }
      }
    }
    final level = currentLevel;
    handNumber++;
    return startHand(
      players: [for (var i = 0; i < n; i++) _alive(i) ? SeatSetup(seats[i].name, seats[i].stack) : null],
      button: button,
      smallBlind: level.smallBlind,
      bigBlind: level.bigBlind,
      ante: level.ante,
      handNumber: handNumber,
      rng: rng,
      deck: deck,
    );
  }

  /// Copies stacks back and records anyone who busted. Players busting in
  /// the same hand are placed by their stack at the start of it (bigger
  /// stack finishes higher). Returns the eliminations, best place last.
  List<Elimination> settle(HandState done) {
    final start = done.log.whereType<HandStarted>().first;
    for (final s in done.seats) {
      if (s.inHand) seats[s.index].stack = s.stack;
    }
    final busted = [
      for (final s in done.seats)
        if (s.inHand && s.stack == 0 && !places.containsKey(s.index)) s.index
    ];
    int startStack(int seat) => (start.seats[seat]['stack'] as int?) ?? 0;
    busted.sort((a, b) => startStack(a).compareTo(startStack(b))); // smallest first -> worst place
    var place = playersLeft + busted.length;
    final out = <Elimination>[];
    for (final seat in busted) {
      places[seat] = place;
      out.add(Elimination(seat, place));
      place--;
    }
    if (playersLeft == 1) places[alive.single] = 1;
    return out;
  }

  /// Plays out the rest of the tournament instantly with the bots' own
  /// decisions (used after the human is eliminated). Every remaining player
  /// must be a bot.
  void simulateRest({int maxHands = 20000}) {
    final reads = TableReads();
    var hands = 0;
    while (!isFinished && hands++ < maxHands) {
      var s = startNextHand();
      while (!s.isComplete) {
        final p = seats[s.toAct];
        final bot = p.bot;
        if (bot == null) throw StateError('simulateRest needs bots only');
        s = applyAction(s, bot.decide(buildBotContext(s, tournament: TournamentInfo(prizes: prizes, playersLeft: playersLeft), reads: reads), rng));
      }
      reads.observe(s);
      settle(s);
    }
  }
}


/// One finished Sit & Go from the player's point of view.
class TournamentResult {
  const TournamentResult({
    required this.at,
    required this.players,
    required this.buyIn,
    required this.place,
    required this.prize,
    required this.speed,
    required this.payoutStyle,
  });

  factory TournamentResult.fromJson(Map<String, Object?> j) => TournamentResult(
        at: DateTime.parse(j['at'] as String),
        players: j['players'] as int,
        buyIn: j['buyIn'] as int,
        place: j['place'] as int,
        prize: j['prize'] as int,
        speed: BlindSpeed.values.byName(j['speed'] as String),
        payoutStyle: PayoutStyle.values.byName(j['payouts'] as String),
      );

  final DateTime at;
  final int players, buyIn, place, prize;
  final BlindSpeed speed;
  final PayoutStyle payoutStyle;

  int get profit => prize - buyIn;
  bool get inTheMoney => prize > 0;

  Map<String, Object?> toJson() => {
        'at': at.toIso8601String(),
        'players': players,
        'buyIn': buyIn,
        'place': place,
        'prize': prize,
        'speed': speed.name,
        'payouts': payoutStyle.name,
      };
}
