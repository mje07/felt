import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';

import 'bankroll.dart';
import 'history_store.dart';
import 'settings.dart';
import 'sounds.dart';
import 'theme.dart';
import 'tournament_store.dart';

enum GameMode { cash, sitAndGo }

/// Lobby choices for a new table.
class TableConfig {
  const TableConfig({
    this.mode = GameMode.cash,
    this.seats = 6,
    this.smallBlind = 5,
    this.bigBlind = 10,
    this.buyInBigBlinds = 100,
    this.style = 'mixed',
    this.difficulty = Difficulty.standard,
    this.sngBuyIn = 500,
    this.speed = BlindSpeed.turbo,
    this.startingStack = StartingStack.standard,
    this.payoutStyle = PayoutStyle.standard,
  });

  final GameMode mode;
  final int seats, smallBlind, bigBlind, buyInBigBlinds;

  /// 'mixed' or a [Personality.id].
  final String style;
  final Difficulty difficulty;

  // Sit & Go.
  final int sngBuyIn;
  final BlindSpeed speed;
  final StartingStack startingStack;
  final PayoutStyle payoutStyle;

  bool get isTournament => mode == GameMode.sitAndGo;

  /// Cash-game buy-in (100 big blinds).
  int get buyIn => bigBlind * buyInBigBlinds;

  /// What sitting down costs from the bankroll.
  int get entryCost => isTournament ? sngBuyIn : buyIn;
}

/// How a Sit & Go ended for the player.
class TournamentOutcome {
  const TournamentOutcome({
    required this.place,
    required this.players,
    required this.prize,
    required this.buyIn,
    required this.winnerName,
  });
  final int place, players, prize, buyIn;
  final String winnerName;
  bool get won => place == 1;
  bool get inTheMoney => prize > 0;
}

String ordinal(int n) {
  final mod100 = n % 100;
  final suffix = (mod100 >= 11 && mod100 <= 13)
      ? 'th'
      : switch (n % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$n$suffix';
}

const _botNames = ['Ava', 'Milo', 'Nora', 'Theo', 'Iris', 'Leo', 'Zoe', 'Finn', 'June', 'Otto'];
const _mixedStyles = [
  Personality.tag, Personality.rock, Personality.lag, Personality.station, //
  Personality.maniac, Personality.tag, Personality.rock, Personality.lag,
];

/// What the table shows for one seat. Updated event-by-event so the UI can
/// animate each step.
class SeatView {
  SeatView({required this.index, required this.name, required this.isHuman, required this.style});

  final int index;
  final String name;
  final bool isHuman;
  final String style;
  int stack = 0, bet = 0, cardsDealt = 0, won = 0;
  bool inHand = false, folded = false, allIn = false, revealed = false, winner = false;

  /// Coach grade of this seat's latest decision (hero only).
  Grade? grade;

  /// Finishing place once eliminated from a tournament.
  int? outPlace;
  List<int> hole = const [];
  String? label;
  String? handLabel;
}

class TableView {
  TableView(this.seats);
  final List<SeatView> seats;
  final List<int> board = [];
  int pot = 0;
  int button = -1;
  int toAct = -1;
  int handNumber = 0;

  /// Cards forming the winning hand(s), highlighted at showdown.
  Set<int> highlight = {};
  String? headline;
  bool get showdownHighlight => highlight.isNotEmpty;
}

sealed class Anchor {
  const Anchor();
}

class SeatAnchor extends Anchor {
  const SeatAnchor(this.seat);
  final int seat;
}

class BetAnchor extends Anchor {
  const BetAnchor(this.seat);
  final int seat;
}

class PotAnchor extends Anchor {
  const PotAnchor();
}

/// A transient chip animation drawn by the table overlay.
class ChipFlight {
  ChipFlight(this.id, this.from, this.to, this.amount, this.duration);
  final int id;
  final Anchor from, to;
  final int amount;
  final Duration duration;
}

class GameController extends ChangeNotifier {
  GameController({
    required this.config,
    required this.settings,
    required this.history,
    this.sounds = Sounds.silent,
    Bankroll? bankroll,
    TournamentStore? tournaments,
    Random? rng,
    this.useIsolates = true,
  })  : _rng = rng ?? Random.secure(),
        bankroll = bankroll ?? Bankroll.current,
        tournaments = tournaments ?? TournamentStore.current {
    final players = <TablePlayer>[];
    final names = List.of(_botNames)..shuffle(_rng);
    final stack = config.isTournament ? config.startingStack.chips : config.buyIn;
    for (var i = 0; i < config.seats; i++) {
      if (i == heroSeat) {
        players.add(TablePlayer(name: settings.playerName, stack: stack, isHuman: true));
      } else {
        final style = config.style == 'mixed'
            ? _mixedStyles[(i - 1) % _mixedStyles.length]
            : Personality.byId(config.style);
        players.add(TablePlayer(
          name: names[(i - 1) % names.length],
          stack: stack,
          personality: style,
          difficulty: config.difficulty,
        ));
      }
    }
    if (config.isTournament) {
      tournament = Tournament(
        seats: players,
        buyIn: config.sngBuyIn,
        speed: config.speed,
        payoutStyle: config.payoutStyle,
        rng: _rng,
      );
    } else {
      cash = CashGame(seats: players, smallBlind: config.smallBlind, bigBlind: config.bigBlind, rng: _rng);
    }
    _players = players;
    view = TableView([
      for (var i = 0; i < players.length; i++)
        SeatView(
          index: i,
          name: players[i].name,
          isHuman: players[i].isHuman,
          style: players[i].personality?.label ?? '',
        )..stack = players[i].stack,
    ]);
  }

  static const heroSeat = 0;

  final TableConfig config;
  final Settings settings;
  final HistoryStore history;
  final Sounds sounds;
  final Bankroll bankroll;
  final TournamentStore tournaments;
  final bool useIsolates;
  final Random _rng;

  /// Exactly one of these is set, depending on [TableConfig.mode].
  CashGame? cash;
  Tournament? tournament;
  late final List<TablePlayer> _players;
  late final TableView view;

  /// Set when a Sit & Go is over for the player.
  TournamentOutcome? outcome;

  /// Shown as the headline when the next hand starts (e.g. "Blinds up").
  String? _pendingHeadline;
  bool _paid = false;
  HandState? _state;

  /// Non-null while waiting for the human to act.
  LegalActions? heroLegal;
  Completer<PlayerAction>? _heroTurn;
  Completer<void>? _nextHand;
  Completer<void>? _rebuy;

  bool handOver = false;
  bool heroBusted = false;
  bool _disposed = false;
  bool _running = false;

  final List<ChipFlight> flights = [];
  int _flightId = 0;

  TablePlayer get hero => _players[heroSeat];
  int get sessionNet => hero.stack - hero.buyIns;

  // Coach.
  final List<DecisionReview> _handReviews = [];

  /// Grades for the most recent finished hand.
  List<DecisionReview> lastHandReviews = const [];

  /// Every grade this session (for the session accuracy readout).
  final List<DecisionReview> sessionReviews = [];
  double? get sessionAccuracy => accuracyOf(sessionReviews);

  /// While true, the next hand is not dealt (e.g. the review panel is open).
  bool holdNextHand = false;

  /// Total in the middle including live bets (for bet sizing).
  int get potWithBets => _state?.pot ?? 0;

  void start() {
    if (_running) return;
    _running = true;
    // Take the buy-in from the bankroll.
    _paid = bankroll.debit(
      config.entryCost,
      note: config.isTournament
          ? 'Sit & Go · ${config.seats} players'
          : 'Cash table ${config.smallBlind}/${config.bigBlind}',
    );
    if (!config.isTournament && _paid) bankroll.setInPlay(hero.stack);
    unawaited(_loop().catchError((Object e, StackTrace st) {
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: st, library: 'felt game loop'));
    }));
  }

  // ---------------------------------------------------------------- input

  void act(PlayerAction action) {
    final c = _heroTurn;
    if (c == null || c.isCompleted) return;
    heroLegal = null;
    _heroTurn = null;
    c.complete(action);
  }

  void dealNext() {
    final c = _nextHand;
    if (c != null && !c.isCompleted) c.complete();
  }

  /// Whether the bankroll covers a cash-game rebuy.
  bool get canAffordRebuy => bankroll.canAfford(config.buyIn - hero.stack);

  void rebuy() {
    final amount = config.buyIn - hero.stack;
    if (!bankroll.debit(amount, kind: LedgerKind.rebuy, note: 'Rebuy')) return;
    cash!.rebuy(heroSeat, amount);
    bankroll.setInPlay(hero.stack);
    view.seats[heroSeat].stack = hero.stack;
    heroBusted = false;
    final c = _rebuy;
    if (c != null && !c.isCompleted) c.complete();
    _notify();
  }

  /// True while a Sit & Go is still running for the player (leaving forfeits).
  bool get tournamentInProgress => tournament != null && outcome == null && _running;

  @override
  void dispose() {
    // Cash games pay out the stack when you leave; leaving a Sit & Go early
    // forfeits the buy-in.
    if (cash != null && _running && _paid) bankroll.cashOut(hero.stack, note: 'Cash table ${config.smallBlind}/${config.bigBlind}');
    _disposed = true;
    _heroTurn?.complete(const PlayerAction.fold());
    if (!(_nextHand?.isCompleted ?? true)) _nextHand!.complete();
    if (!(_rebuy?.isCompleted ?? true)) _rebuy!.complete();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _wait(int ms) async {
    if (_disposed) return;
    await Future<void>.delayed(settings.scaled(Duration(milliseconds: ms)));
  }

  // ---------------------------------------------------------------- loop

  Future<void> _loop() async {
    while (!_disposed) {
      final t = tournament;
      if (t == null) {
        // Cash game: bots who bust buy back in; the player is offered a rebuy.
        final c = cash!;
        for (var i = 0; i < _players.length; i++) {
          final p = _players[i];
          if (!p.isHuman && p.stack < config.bigBlind) {
            c.rebuy(i, config.buyIn - p.stack);
            view.seats[i].stack = p.stack;
          }
        }
        if (hero.stack == 0) {
          heroBusted = true;
          _rebuy = Completer<void>();
          _notify();
          await _rebuy!.future;
          if (_disposed) return;
        }
      } else if (t.isFinished || outcome != null) {
        return;
      }


      var s = t != null ? t.startNextHand() : cash!.startNextHand();
      if (t != null && t.handNumber > 1 && (t.handNumber - 1) ~/ t.speed.handsPerLevel != (t.handNumber - 2) ~/ t.speed.handsPerLevel) {
        final lvl = levelAt((t.handNumber - 1) ~/ t.speed.handsPerLevel);
        _pendingHeadline = 'Blinds up: ${formatChips(lvl.smallBlind)}/${formatChips(lvl.bigBlind)}'
            '${lvl.ante > 0 ? ' · ante ${formatChips(lvl.ante)}' : ''}';
      }
      _handReviews.clear();
      lastHandReviews = const [];
      _state = s;
      await _play(s, s.log);
      while (!s.isComplete && !_disposed) {
        view.toAct = s.toAct;
        _notify();
        final heroTurn = s.toAct == heroSeat;
        // Always graded (even when hidden at the table) so stats stay complete.
        final analysis = heroTurn ? _analyze(s) : null;
        final action = heroTurn ? await _askHero(s) : await _askBot(s);
        if (analysis != null && !_disposed) {
          try {
            final review = gradeDecision(await analysis, action);
            if (review != null) {
              _handReviews.add(review);
              sessionReviews.add(review);
              view.seats[heroSeat].grade = review.grade;
            }
          } catch (e) {
            debugPrint('Coach analysis failed: $e');
          }
        }
        if (_disposed) return;
        HandState next;
        try {
          next = applyAction(s, action);
        } on IllegalActionException {
          final l = legalActions(s);
          next = applyAction(s, l.canCheck ? const PlayerAction.check() : const PlayerAction.fold());
        }
        view.toAct = -1;
        _state = next;
        await _play(next, next.log.sublist(s.log.length));
        s = next;
      }
      if (_disposed) return;
      lastHandReviews = List.unmodifiable(_handReviews);
      unawaited(history.add(HandHistory.fromState(
        s,
        heroSeat: heroSeat,
        reviews: lastHandReviews,
        mode: t != null ? 'sng' : 'cash',
        level: t != null ? (t.handNumber - 1) ~/ t.speed.handsPerLevel + 1 : null,
      )));

      if (t == null) {
        cash!.settle(s);
        if (_paid) bankroll.setInPlay(hero.stack);
      } else {
        final out = t.settle(s);
        if (out.isNotEmpty) {
          for (final e in out) {
            view.seats[e.seat]
              ..outPlace = e.place
              ..label = ordinal(e.place);
          }
          view.headline = out.reversed
              .map((e) => e.seat == heroSeat
                  ? 'You finish ${ordinal(e.place)}'
                  : '${view.seats[e.seat].name} finishes ${ordinal(e.place)}')
              .join(' · ');
          _notify();
        }
        if (t.places.containsKey(heroSeat)) {
          await _wait(1400);
          await _finishTournament(t);
          return;
        }
      }

      handOver = true;
      _nextHand = Completer<void>();
      _notify();
      if (settings.autoDeal && hero.stack > 0) {
        await Future.any([
          _nextHand!.future,
          Future<void>.delayed(settings.scaled(const Duration(milliseconds: 2600))),
        ]);
      } else {
        await _nextHand!.future;
      }
      while (holdNextHand && !_disposed) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      handOver = false;
    }
  }

  Future<PlayerAction> _askHero(HandState s) {
    heroLegal = legalActions(s);
    sounds.play(Sfx.turn);
    _heroTurn = Completer<PlayerAction>();
    _notify();
    return _heroTurn!.future;
  }

  Future<PlayerAction> _askBot(HandState s) async {
    final bot = _players[s.toAct].bot!;
    final ctx = buildBotContext(s);
    final think = Future<void>.delayed(
        settings.scaled(Duration(milliseconds: 450 + _rng.nextInt(850))));
    final Future<PlayerAction> decision;
    if (useIsolates && ctx.street != Street.preflop) {
      decision = _decideInIsolate(bot, ctx);
    } else {
      decision = Future.value(bot.decide(ctx, _rng));
    }
    final results = await Future.wait<Object?>([decision, think]);
    return results.first! as PlayerAction;
  }

  // ---------------------------------------------------------------- tournament

  Future<void> _finishTournament(Tournament t) async {
    final place = t.places[heroSeat]!;
    var winner = t.winner;
    // If the player is out, play the rest out instantly to name the winner.
    winner ??= useIsolates ? await _simulateWinner(t) : (t..simulateRest()).winner;
    final prize = t.prizeFor(heroSeat);
    if (prize > 0) bankroll.credit(prize, note: 'Sit & Go ${ordinal(place)}');
    unawaited(tournaments.add(TournamentResult(
      at: DateTime.now(),
      players: t.startingPlayers,
      buyIn: t.buyIn,
      place: place,
      prize: prize,
      speed: t.speed,
      payoutStyle: t.payoutStyle,
    )));
    outcome = TournamentOutcome(
      place: place,
      players: t.startingPlayers,
      prize: prize,
      buyIn: t.buyIn,
      winnerName: winner == null ? '' : (winner == heroSeat ? 'You' : _players[winner].name),
    );
    sounds.play(place == 1 ? Sfx.win : Sfx.collect);
    _notify();
  }

  /// Runs the remaining bot-only tournament in a background isolate.
  static Future<int?> _simulateWinner(Tournament t) {
    final seats = [
      for (final p in t.seats)
        (p.name, p.stack, p.personality?.id ?? 'tag', p.difficulty),
    ];
    final places = Map.of(t.places);
    final button = t.button, hands = t.handNumber, buyIn = t.buyIn;
    final speed = t.speed, style = t.payoutStyle;
    return Isolate.run(() {
      final copy = Tournament(
        seats: [
          for (final (name, stack, pid, diff) in seats)
            TablePlayer(name: name, stack: stack, personality: Personality.byId(pid), difficulty: diff),
        ],
        buyIn: buyIn,
        speed: speed,
        payoutStyle: style,
        rng: Random(),
      )
        ..button = button
        ..handNumber = hands;
      copy.places.addAll(places);
      copy.simulateRest();
      return copy.winner;
    });
  }

  /// Level of the hand in play (0-based).
  int get playingLevel {
    final t = tournament!;
    return t.handNumber == 0 ? 0 : (t.handNumber - 1) ~/ t.speed.handsPerLevel;
  }

  String get tournamentTitle {
    final lvl = levelAt(playingLevel);
    return 'Sit & Go · Level ${playingLevel + 1} · ${formatChips(lvl.smallBlind)}/${formatChips(lvl.bigBlind)}'
        '${lvl.ante > 0 ? ' · ante ${formatChips(lvl.ante)}' : ''}';
  }

  String get tournamentStatus {
    final t = tournament!;
    final untilNext = t.speed.handsPerLevel * (playingLevel + 1) - t.handNumber;
    final next = untilNext <= 0
        ? 'blinds up next hand'
        : 'next level in $untilNext hand${untilNext == 1 ? '' : 's'}';
    return '${t.playersLeft} of ${t.startingPlayers} left · $next';
  }

  TournamentInfo? get _tournamentInfo {
    final t = tournament;
    return t == null ? null : TournamentInfo(prizes: t.prizes, playersLeft: t.playersLeft);
  }

  /// Coach analysis of the hero's spot (postflop runs Monte Carlo, so off the UI isolate).
  Future<DecisionAnalysis> _analyze(HandState s) {
    final ctx = buildBotContext(s, tournament: _tournamentInfo);
    if (ctx.street == Street.preflop) return Future.value(analyzeDecision(ctx));
    if (!useIsolates) return Future.value(analyzeDecision(ctx, samples: 300, rng: _rng));
    return Isolate.run(() => analyzeDecision(ctx, samples: 2000));
  }

  static Future<PlayerAction> _decideInIsolate(HeuristicBot bot, BotContext ctx) =>
      Isolate.run(() => bot.decide(ctx, Random()));

  // ---------------------------------------------------------------- events

  Future<void> _play(HandState s, List<GameEvent> events) async {
    for (final e in events) {
      if (_disposed) return;
      switch (e) {
        case HandStarted():
          view.board.clear();
          view.pot = 0;
          view.highlight = {};
          view.headline = _pendingHeadline;
          _pendingHeadline = null;
          view.button = e.button;
          view.handNumber = e.handNumber;
          for (final sv in view.seats) {
            final seat = s.seats[sv.index];
            sv
              ..inHand = seat.inHand
              ..stack = (e.seats[sv.index]['stack'] as int?) ?? 0
              ..bet = 0
              ..folded = false
              ..allIn = false
              ..revealed = sv.isHuman
              ..winner = false
              ..won = 0
              ..cardsDealt = 0
              ..hole = List.of(seat.hole)
              ..label = null
              ..handLabel = null
              ..grade = null;
          }
          _notify();
          await _wait(300);
        case BlindPosted():
          final sv = view.seats[e.seat];
          sv.stack -= e.amount;
          sv.bet += e.amount;
          sv.allIn = sv.stack == 0;
          sv.label = e.isBig ? 'Big Blind' : 'Small Blind';
          sounds.play(Sfx.chip);
          _notify();
          await _wait(160);
        case AntePosted():
          final sv = view.seats[e.seat];
          sv.stack -= e.amount;
          sv.allIn = sv.stack == 0;
          sounds.play(Sfx.chip);
          await _fly([(SeatAnchor(e.seat), const PotAnchor(), e.amount)]);
          view.pot += e.amount;
          _notify();
        case HoleCardsDealt():
          for (var round = 0; round < 2; round++) {
            for (final i in e.order) {
              view.seats[i].cardsDealt++;
              sounds.play(Sfx.deal);
              _notify();
              await _wait(55);
            }
          }
          _updateHeroLabel();
          for (final sv in view.seats) {
            if (sv.label == 'Small Blind' || sv.label == 'Big Blind') sv.label = null;
          }
          _notify();
          await _wait(250);
        case PlayerActed():
          final sv = view.seats[e.seat];
          sv.stack -= e.added;
          sv.bet = e.streetBet;
          sv.folded = e.type == ActionType.fold;
          sv.allIn = e.allIn;
          sv.label = _verb(e);
          sounds.play(switch (e.type) {
            ActionType.fold => Sfx.fold,
            ActionType.check => Sfx.check,
            _ => e.allIn ? Sfx.collect : Sfx.chip,
          });
          _notify();
          await _wait(e.type == ActionType.fold ? 220 : 300);
        case UncalledReturned():
          final sv = view.seats[e.seat];
          sounds.play(Sfx.chip);
          await _fly([(BetAnchor(e.seat), SeatAnchor(e.seat), e.amount)]);
          sv.bet -= e.amount;
          sv.stack += e.amount;
          if (sv.stack > 0) sv.allIn = false;
          _notify();
        case StreetDealt():
          await _collectBets();
          for (final sv in view.seats) {
            if (!sv.folded && !sv.allIn) sv.label = null;
          }
          for (final c in e.cards) {
            view.board.add(c);
            sounds.play(Sfx.flip);
            _updateHeroLabel();
            _notify();
            await _wait(e.cards.length > 1 ? 140 : 60);
          }
          await _wait(420);
        case ShowdownRevealed():
          await _collectBets();
          for (final entry in e.hands.entries) {
            final sv = view.seats[entry.key];
            sv.revealed = true;
            sv.handLabel = describeHand(entry.value.$2);
            if (!sv.isHuman) sounds.play(Sfx.flip);
            sv.label = null;
            _notify();
            await _wait(260);
          }
          await _wait(500);
        case PotAwarded():
          await _collectBets();
          final a = e.award;
          view.pot -= a.amount;
          for (final w in a.shares.entries) {
            final sv = view.seats[w.key];
            sv.winner = true;
            sv.won += w.value;
          }
          if (a.handValue != null) {
            for (final w in a.shares.keys) {
              view.highlight.addAll(bestFive([...view.seats[w].hole, ...view.board]));
            }
          }
          await _fly([for (final w in a.shares.entries) (const PotAnchor(), SeatAnchor(w.key), w.value)]);
          for (final w in a.shares.entries) {
            view.seats[w.key].stack += w.value;
          }
          view.headline = _headline(a);
          if (a.shares.containsKey(heroSeat)) sounds.play(Sfx.win);
          _notify();
          await _wait(1100);
        case HandEnded():
          for (final sv in view.seats) {
            if (sv.winner) sv.label = '+${formatChips(sv.won)}';
          }
          _notify();
      }
    }
  }

  Future<void> _collectBets() async {
    final moving = [
      for (final sv in view.seats)
        if (sv.bet > 0) (BetAnchor(sv.index) as Anchor, const PotAnchor() as Anchor, sv.bet)
    ];
    if (moving.isEmpty) return;
    final total = moving.fold(0, (a, m) => a + m.$3);
    for (final sv in view.seats) {
      sv.bet = 0;
    }
    sounds.play(Sfx.collect);
    await _fly(moving);
    view.pot += total;
    _notify();
  }

  Future<void> _fly(List<(Anchor, Anchor, int)> moves) async {
    if (moves.isEmpty) return;
    final d = settings.scaled(ChipMotion.flight);
    final created = [for (final m in moves) ChipFlight(_flightId++, m.$1, m.$2, m.$3, d)];
    flights.addAll(created);
    _notify();
    await Future<void>.delayed(d);
    flights.removeWhere(created.contains);
    _notify();
  }

  void _updateHeroLabel() {
    final h = view.seats[heroSeat];
    if (h.hole.length < 2 || !h.inHand) return;
    if (view.board.length < 3) {
      h.handLabel = startingHandName(startingHandIndex(h.hole[0], h.hole[1]));
    } else {
      h.handLabel = describeHand(evaluate([...h.hole, ...view.board]));
    }
  }

  String _verb(PlayerActed e) {
    if (e.allIn && e.type != ActionType.fold) return 'All-in';
    return switch (e.type) {
      ActionType.fold => 'Fold',
      ActionType.check => 'Check',
      ActionType.call => 'Call',
      ActionType.bet => 'Bet',
      ActionType.raise => 'Raise',
    };
  }

  String _headline(PotAward a) {
    final seats = a.shares.keys.toList();
    final hand = a.handValue != null ? ' with ${describeHand(a.handValue!)}' : '';
    final amount = formatChips(a.amount);
    if (seats.length > 1) {
      return '${seats.map((s) => view.seats[s].name).join(' & ')} split $amount$hand';
    }
    final s = seats.single;
    return s == heroSeat ? 'You win $amount$hand' : '${view.seats[s].name} wins $amount$hand';
  }
}

/// Motion constant used by chip flights (kept here to avoid UI imports).
abstract final class ChipMotion {
  static const flight = Duration(milliseconds: 420);
}
