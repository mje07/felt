import 'dart:math';

import 'bots/bot.dart';
import 'bots/reads.dart';
import 'cash_game.dart';
import 'game_state.dart';
import 'rng.dart';
import 'rules.dart';
import 'tournament.dart';

/// Places paid in a multi-table tournament: about 15% of the field.
int mttPaidPlaces(int field) {
  if (field <= 4) return 1;
  if (field <= 6) return 2;
  if (field <= 9) return 3;
  return max(3, (field * 0.15).round());
}

/// Prizes for each paid place. Shares fall off like 1/place, so 1st takes
/// about a quarter of a big field's pool and the last paid place a little
/// under two buy-ins. Whole chips; the rounding remainder goes to 1st.
List<int> mttPrizes(int field, int pool) {
  final paid = mttPaidPlaces(field);
  final weights = [for (var i = 1; i <= paid; i++) 1 / i];
  final total = weights.fold(0.0, (a, b) => a + b);
  final prizes = [for (final w in weights) (pool * w / total).floor()];
  prizes[0] += pool - prizes.fold(0, (a, b) => a + b);
  return prizes;
}

/// One table in a multi-table tournament.
class MttTable {
  MttTable(this.id, int size) : seats = List<int?>.filled(size, null);

  final int id;

  /// Player id in each seat (null = empty).
  final List<int?> seats;
  final rotation = BlindRotation();
  int handsPlayed = 0;

  Iterable<int> get playerIds => seats.whereType<int>();
}

/// A player moved between tables (balancing or a table breaking).
class TableMove {
  const TableMove(this.player, this.fromTable, this.toTable, {required this.broke});
  final int player, fromTable, toTable;

  /// The player's old table was broken up (rather than balanced).
  final bool broke;
}

/// A multi-table tournament: everyone starts with the same stack across
/// tables of [tableSize]; tables are balanced and broken as players bust
/// until one final table remains. Blinds rise on a shared hand clock.
class MultiTableTournament {
  MultiTableTournament({
    required this.players,
    required this.buyIn,
    this.tableSize = 9,
    this.speed = BlindSpeed.turbo,
    int? guarantee,
    Random? rng,
  })  : rng = rng ?? secureRandom(),
        prizePool = max(buyIn * players.length, guarantee ?? 0) {
    prizes = mttPrizes(players.length, prizePool);
    // Seat everyone at random, spreading players evenly over the tables.
    final order = List<int>.generate(players.length, (i) => i)..shuffle(this.rng);
    final tableCount = (players.length / tableSize).ceil();
    for (var t = 0; t < tableCount; t++) {
      tables.add(MttTable(t, tableSize));
    }
    for (var k = 0; k < order.length; k++) {
      final table = tables[k % tableCount];
      table.seats[k ~/ tableCount] = order[k];
    }
  }

  final List<TablePlayer> players;
  final int buyIn, tableSize, prizePool;
  final BlindSpeed speed;
  final Random rng;
  late final List<int> prizes;
  final List<MttTable> tables = [];

  /// Finishing place by player id (1 = winner).
  final Map<int, int> places = {};

  /// Rounds played: one hand at every table. Blinds rise on this clock.
  int clock = 0;
  int _handNumber = 0;

  int get field => players.length;
  int get paidPlaces => prizes.length;
  bool isAlive(int id) => players[id].stack > 0 && !places.containsKey(id);
  int get playersLeft => players.indexed.where((e) => isAlive(e.$1)).length;
  bool get isFinished => playersLeft <= 1;
  bool get isFinalTable => tables.length == 1;
  bool get inTheMoney => playersLeft <= paidPlaces;
  bool get onBubble => playersLeft == paidPlaces + 1;

  int get levelIndex => clock ~/ speed.handsPerLevel;
  BlindLevel get currentLevel => levelAt(levelIndex);
  BlindLevel get nextLevel => levelAt(levelIndex + 1);
  int get handsUntilNextLevel => speed.handsPerLevel - clock % speed.handsPerLevel;

  int? get winner => places.entries.where((e) => e.value == 1).map((e) => e.key).firstOrNull;
  int prizeFor(int id) {
    final p = places[id];
    return p != null && p <= prizes.length ? prizes[p - 1] : 0;
  }

  MttTable tableOf(int id) => tables.firstWhere((t) => t.seats.contains(id));

  /// Live players ranked by stack (chip leader first).
  List<int> get chipCounts {
    final ids = [for (var i = 0; i < players.length; i++) if (isAlive(i)) i];
    ids.sort((a, b) => players[b].stack.compareTo(players[a].stack));
    return ids;
  }

  int get averageStack {
    final left = playersLeft;
    return left == 0 ? 0 : players.fold(0, (s, p) => s + p.stack) ~/ left;
  }

  TournamentInfo get info => TournamentInfo(prizes: prizes, playersLeft: playersLeft);

  /// Starts the next hand at [table]. Hand seat `i` is table seat
  /// `(i + offset) % size`, so a human can always sit at hand seat 0.
  HandState startHandAt(MttTable table, {int offset = 0, List<int>? deck}) {
    final n = table.seats.length;
    int toTable(int i) => (i + offset) % n;
    int toHand(int pos) => pos < 0 ? pos : (pos - offset + n) % n;
    final alive = [for (final id in table.seats) id != null && isAlive(id)];
    table.rotation.advance(alive, rng);
    final level = currentLevel;
    table.handsPlayed++;
    return startHand(
      players: [
        for (var i = 0; i < n; i++)
          () {
            final id = table.seats[toTable(i)];
            return id != null && isAlive(id) ? SeatSetup(players[id].name, players[id].stack) : null;
          }(),
      ],
      button: toHand(table.rotation.buttonPos),
      smallBlindSeat: toHand(table.rotation.smallBlindSeat),
      bigBlindSeat: toHand(table.rotation.bigBlindPos),
      smallBlind: level.smallBlind,
      bigBlind: level.bigBlind,
      ante: level.ante,
      handNumber: ++_handNumber,
      rng: rng,
      deck: deck,
    );
  }

  /// Copies stacks back after a hand at [table] (dealt with [offset], see
  /// [startHandAt]) and records busts (players busting together are placed
  /// by their stack at the start of the hand). Eliminations carry player
  /// ids, best place last.
  List<Elimination> settle(MttTable table, HandState done, {int offset = 0}) {
    final n = table.seats.length;
    final start = done.log.whereType<HandStarted>().first;
    final busted = <int>[];
    for (final s in done.seats) {
      final id = table.seats[(s.index + offset) % n];
      if (!s.inHand || id == null) continue;
      players[id].stack = s.stack;
      if (s.stack == 0 && !places.containsKey(id)) busted.add(s.index);
    }
    int startStack(int seat) => (start.seats[seat]['stack'] as int?) ?? 0;
    busted.sort((a, b) => startStack(a).compareTo(startStack(b)));
    var place = playersLeft + busted.length;
    final out = <Elimination>[];
    for (final seat in busted) {
      final id = table.seats[(seat + offset) % n]!;
      places[id] = place;
      out.add(Elimination(id, place));
      place--;
    }
    if (playersLeft == 1) {
      places[[for (var i = 0; i < players.length; i++) if (isAlive(i)) i].single] = 1;
    }
    return out;
  }

  /// Clears busted players from their seats, breaks tables that the others
  /// can absorb, and moves players so table sizes differ by at most one.
  /// Call between rounds. The player due the big blind next is the one moved
  /// from a table being balanced.
  List<TableMove> balance() {
    final moves = <TableMove>[];
    for (final t in tables) {
      for (var i = 0; i < t.seats.length; i++) {
        final id = t.seats[i];
        if (id != null && !isAlive(id)) t.seats[i] = null;
      }
    }
    int count(MttTable t) => t.playerIds.length;
    int emptySeat(MttTable t) => t.seats.indexOf(null);

    // Break tables while the rest have room.
    while (tables.length > 1 && playersLeft <= (tables.length - 1) * tableSize) {
      final smallest = tables.reduce((a, b) => count(a) <= count(b) ? a : b);
      tables.remove(smallest);
      for (final id in smallest.playerIds.toList()) {
        final target = tables.reduce((a, b) => count(a) <= count(b) ? a : b);
        target.seats[emptySeat(target)] = id;
        moves.add(TableMove(id, smallest.id, target.id, broke: true));
      }
    }
    // Balance: biggest to smallest until within one.
    while (tables.length > 1) {
      final big = tables.reduce((a, b) => count(a) >= count(b) ? a : b);
      final small = tables.reduce((a, b) => count(a) <= count(b) ? a : b);
      if (count(big) - count(small) <= 1) break;
      final seat = _dueBigBlind(big);
      final id = big.seats[seat]!;
      big.seats[seat] = null;
      small.seats[emptySeat(small)] = id;
      moves.add(TableMove(id, big.id, small.id, broke: false));
    }
    return moves;
  }

  int _dueBigBlind(MttTable t) {
    final n = t.seats.length;
    final from = t.rotation.bigBlindPos < 0 ? 0 : t.rotation.bigBlindPos;
    for (var k = 1; k <= n; k++) {
      final s = (from + k) % n;
      if (t.seats[s] != null) return s;
    }
    return t.seats.indexWhere((x) => x != null);
  }

  /// Plays one hand at every table except [skip] (the human's), with the
  /// bots deciding instantly. Returns all eliminations.
  List<Elimination> playOtherTables({MttTable? skip, required TableReads reads}) {
    final out = <Elimination>[];
    for (final t in List.of(tables)) {
      if (identical(t, skip) || isFinished) continue;
      if (t.playerIds.where(isAlive).length < 2) continue;
      var s = startHandAt(t);
      while (!s.isComplete) {
        final id = t.seats[s.toAct]!;
        final bot = players[id].bot;
        if (bot == null) throw StateError('Only bots can be simulated');
        s = applyAction(s, bot.decide(buildBotContext(s, tournament: info, reads: reads), rng));
      }
      reads.observe(s);
      out.addAll(settle(t, s));
    }
    return out;
  }

  /// Plays the tournament to the end with bots only (after the human busts).
  /// [onRound] reports progress.
  void simulateRest({void Function(int playersLeft)? onRound, int maxRounds = 20000}) {
    final reads = TableReads();
    var rounds = 0;
    while (!isFinished && rounds++ < maxRounds) {
      playOtherTables(reads: reads);
      balance();
      clock++;
      onRound?.call(playersLeft);
    }
  }
}
