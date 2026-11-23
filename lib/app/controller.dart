import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';

import 'history_store.dart';
import 'settings.dart';
import 'sounds.dart';
import 'theme.dart';

/// Lobby choices for a new table.
class TableConfig {
  const TableConfig({
    this.seats = 6,
    this.smallBlind = 5,
    this.bigBlind = 10,
    this.buyInBigBlinds = 100,
    this.style = 'mixed',
    this.difficulty = Difficulty.standard,
  });

  final int seats, smallBlind, bigBlind, buyInBigBlinds;

  /// 'mixed' or a [Personality.id].
  final String style;
  final Difficulty difficulty;

  int get buyIn => bigBlind * buyInBigBlinds;
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
    Random? rng,
    this.useIsolates = true,
  }) : _rng = rng ?? Random.secure() {
    final players = <TablePlayer?>[];
    final names = List.of(_botNames)..shuffle(_rng);
    for (var i = 0; i < config.seats; i++) {
      if (i == heroSeat) {
        players.add(TablePlayer(name: settings.playerName, stack: config.buyIn, isHuman: true));
      } else {
        final style = config.style == 'mixed'
            ? _mixedStyles[(i - 1) % _mixedStyles.length]
            : Personality.byId(config.style);
        players.add(TablePlayer(
          name: names[(i - 1) % names.length],
          stack: config.buyIn,
          personality: style,
          difficulty: config.difficulty,
        ));
      }
    }
    game = CashGame(seats: players, smallBlind: config.smallBlind, bigBlind: config.bigBlind, rng: _rng);
    view = TableView([
      for (var i = 0; i < players.length; i++)
        SeatView(
          index: i,
          name: players[i]!.name,
          isHuman: players[i]!.isHuman,
          style: players[i]!.personality?.label ?? '',
        )..stack = players[i]!.stack,
    ]);
  }

  static const heroSeat = 0;

  final TableConfig config;
  final Settings settings;
  final HistoryStore history;
  final Sounds sounds;
  final bool useIsolates;
  final Random _rng;

  late final CashGame game;
  late final TableView view;
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

  TablePlayer get hero => game.seats[heroSeat]!;
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

  void rebuy() {
    game.rebuy(heroSeat, config.buyIn - hero.stack);
    view.seats[heroSeat].stack = hero.stack;
    heroBusted = false;
    final c = _rebuy;
    if (c != null && !c.isCompleted) c.complete();
    _notify();
  }

  @override
  void dispose() {
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
      // Bots who bust buy back in.
      for (var i = 0; i < game.seats.length; i++) {
        final p = game.seats[i]!;
        if (!p.isHuman && p.stack < config.bigBlind) {
          game.rebuy(i, config.buyIn - p.stack);
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

      var s = game.startNextHand();
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
      game.settle(s);
      lastHandReviews = List.unmodifiable(_handReviews);
      unawaited(history.add(HandHistory.fromState(s, heroSeat: heroSeat, reviews: lastHandReviews)));

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
    final bot = game.seats[s.toAct]!.bot!;
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

  /// Static so the closure captures only the bot and its context.
  /// Coach analysis of the hero's spot (postflop runs Monte Carlo, so off the UI isolate).
  Future<DecisionAnalysis> _analyze(HandState s) {
    final ctx = buildBotContext(s);
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
          view.headline = null;
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
