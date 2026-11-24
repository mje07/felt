import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:poker_engine/poker_engine.dart';

import 'protocol.dart';

/// How a home game is set up.
class HomeGameSettings {
  const HomeGameSettings({
    this.name = 'Home game',
    this.seats = 6,
    this.tournament = false,
    this.smallBlind = 5,
    this.bigBlind = 10,
    this.startingStack = 1500,
    this.speed = BlindSpeed.turbo,
    this.fillWithBots = true,
    this.actionSeconds = 30,
  });

  final String name;
  final int seats, smallBlind, bigBlind, startingStack, actionSeconds;
  final bool tournament, fillWithBots;
  final BlindSpeed speed;

  Map<String, Object?> toJson() => {
        'name': name,
        'seats': seats,
        'tournament': tournament,
        'sb': smallBlind,
        'bb': bigBlind,
        'stack': startingStack,
        'speed': speed.name,
        'bots': fillWithBots,
        'secs': actionSeconds,
      };

  static HomeGameSettings fromJson(Map<String, Object?> j) => HomeGameSettings(
        name: j['name'] as String? ?? 'Home game',
        seats: (j['seats'] as int? ?? 6).clamp(2, 9),
        tournament: j['tournament'] as bool? ?? false,
        smallBlind: j['sb'] as int? ?? 5,
        bigBlind: j['bb'] as int? ?? 10,
        startingStack: j['stack'] as int? ?? 1500,
        speed: BlindSpeed.values.where((s) => s.name == j['speed']).firstOrNull ?? BlindSpeed.turbo,
        fillWithBots: j['bots'] as bool? ?? true,
        actionSeconds: j['secs'] as int? ?? 30,
      );
}

/// A friend at the table.
class RemotePlayer {
  RemotePlayer(this.name, this.token, this.seat);
  final String name, token;
  final int seat;
  Channel? channel;
  bool get connected => channel != null;
  DateTime? lostAt;
}

/// Hosts a home game: accepts friends (LAN, direct connection or the relay),
/// keeps the lobby, and is how the game controller talks to remote seats.
class HomeGameHost extends ChangeNotifier {
  HomeGameHost(this.settings, {required this.hostName, Random? rng}) : _rng = rng ?? Random.secure();

  final HomeGameSettings settings;
  final String hostName;
  final Random _rng;
  final List<RemotePlayer> players = [];
  bool started = false;
  HttpServer? _server;
  LanAnnouncer? _announcer;
  int? port;

  /// Set when the game is reachable through the relay.
  String? inviteCode;

  /// Pending action requests by seat.
  final Map<int, (int, Completer<PlayerAction>)> _pending = {};

  /// This hand's messages for each seat, to resync a player who reconnects.
  int _handNo = -1;
  final Map<int, Map<String, Object?>> _handMessage = {};
  final List<Map<String, Object?>> _handActions = [];
  Map<String, Object?>? _status;

  /// Seats a friend can still take.
  int get openSeats => settings.seats - 1 - players.length;

  RemotePlayer? playerAt(int seat) => players.where((p) => p.seat == seat).firstOrNull;

  /// Starts listening for connections and announcing the game on the LAN.
  Future<void> listen({int port = defaultGamePort, bool announce = true}) async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    this.port = server.port;
    server.listen((req) async {
      if (req.uri.path != '/felt' || !WebSocketTransformer.isUpgradeRequest(req)) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }
      try {
        accept(SocketChannel(await WebSocketTransformer.upgrade(req)));
      } catch (_) {}
    });
    if (announce) {
      _announcer = LanAnnouncer(() => LanGame(
          name: settings.name, host: '', port: this.port!, players: players.length + 1, seats: settings.seats))
        ..start();
    }
  }

  /// Handles a new connection: waits for its hello, then seats it (or
  /// reattaches a returning player by token).
  void accept(Channel ch) {
    late StreamSubscription<Map<String, Object?>> sub;
    RemotePlayer? me;
    final helloTimer = Timer(const Duration(seconds: 8), () {
      if (me == null) ch.close();
    });
    sub = ch.messages.listen((m) {
      if (me == null) {
        if (m['t'] != 'hello') return;
        helloTimer.cancel();
        me = _hello(ch, m);
        if (me == null) {
          sub.cancel();
          Future<void>.delayed(const Duration(milliseconds: 200), ch.close);
        }
        return;
      }
      final p = me!;
      switch (m['t']) {
        case 'act':
          final pending = _pending[p.seat];
          if (pending == null || m['n'] != pending.$1) return;
          final type = ActionType.values.where((t) => t.name == m['type']).firstOrNull;
          if (type == null) return;
          final amount = (m['amount'] as int?) ?? 0;
          _pending.remove(p.seat);
          pending.$2.complete(PlayerAction(type, amount));
        case 'leave':
          _lost(p, left: true);
      }
    });
    ch.done.then((_) {
      final p = me;
      if (p != null && identical(p.channel, ch)) _lost(p);
    });
  }

  RemotePlayer? _hello(Channel ch, Map<String, Object?> m) {
    if (m['v'] != protocolVersion) {
      ch.send({'t': 'reject', 'reason': 'This game needs the same version of Felt. Update and try again.'});
      return null;
    }
    final token = m['token'];
    final returning = token is String ? players.where((p) => p.token == token).firstOrNull : null;
    if (returning != null) {
      returning
        ..channel = ch
        ..lostAt = null;
      ch.send(_welcome(returning));
      _resync(returning);
      _broadcastLobby();
      notifyListeners();
      return returning;
    }
    if (started) {
      ch.send({'t': 'reject', 'reason': 'The game has already started.'});
      return null;
    }
    if (openSeats <= 0) {
      ch.send({'t': 'reject', 'reason': 'The table is full.'});
      return null;
    }
    final raw = (m['name'] as String? ?? 'Player').trim();
    var name = raw.isEmpty ? 'Player' : (raw.length > 16 ? raw.substring(0, 16) : raw);
    final taken = {hostName, for (final p in players) p.name};
    for (var k = 2; taken.contains(name); k++) {
      name = '${raw.length > 13 ? raw.substring(0, 13) : raw} $k';
    }
    final used = {for (final p in players) p.seat};
    final seat = [for (var i = 1; i < settings.seats; i++) i].firstWhere((i) => !used.contains(i));
    final p = RemotePlayer(name, _token(), seat)..channel = ch;
    players.add(p);
    ch.send(_welcome(p));
    _broadcastLobby();
    notifyListeners();
    return p;
  }

  Map<String, Object?> _welcome(RemotePlayer p) =>
      {'t': 'welcome', 'seat': p.seat, 'token': p.token, 'name': p.name, 'game': settings.toJson(), 'host': hostName};

  String _token() => List.generate(24, (_) => 'abcdefghijkmnpqrstuvwxyz23456789'[_rng.nextInt(32)]).join();

  void _lost(RemotePlayer p, {bool left = false}) {
    p.channel = null;
    p.lostAt = DateTime.now();
    // Anyone waiting on them acts for them now.
    final pending = _pending.remove(p.seat);
    if (pending != null && !pending.$2.isCompleted) pending.$2.complete(const PlayerAction(ActionType.fold));
    if (!started) players.remove(p);
    _broadcastLobby();
    notifyListeners();
  }

  void _broadcastLobby() => _broadcast({
        't': 'lobby',
        'started': started,
        'players': [
          {'name': hostName, 'seat': 0, 'on': true},
          for (final p in players) {'name': p.name, 'seat': p.seat, 'on': p.connected},
        ],
      });

  void _broadcast(Map<String, Object?> m) {
    for (final p in players) {
      p.channel?.send(m);
    }
  }

  void markStarted() {
    started = true;
    _broadcastLobby();
    notifyListeners();
  }

  // ------------------------------------------------------------ game hooks

  /// A new hand: everyone gets the setup and only their own hole cards.
  void sendHand(HandState s, {required bool anteFromEveryone}) {
    _handNo = s.handNumber;
    _handActions.clear();
    _handMessage.clear();
    final start = s.log.whereType<HandStarted>().first;
    for (final p in players) {
      final hole = p.seat < s.seats.length && s.seats[p.seat].inHand ? s.seats[p.seat].hole : const <int>[];
      final msg = <String, Object?>{
        't': 'hand',
        'n': s.handNumber,
        'seats': [for (final seat in s.seats) seat.inHand ? [seat.name, start.seats[seat.index]['stack']] : null],
        'button': s.button,
        'sbSeat': s.smallBlindSeat,
        'bbSeat': s.bigBlindSeat,
        'sb': s.smallBlind,
        'bb': s.bigBlind,
        'ante': start.ante,
        'anteAll': anteFromEveryone,
        'hole': hole,
      };
      _handMessage[p.seat] = msg;
      p.channel?.send(msg);
    }
  }

  /// An action was applied: everyone gets it, with any new board cards and,
  /// at showdown, the hands that were shown.
  void sendAction(HandState before, PlayerAction action, HandState after) {
    final newEvents = after.log.sublist(before.log.length);
    final board = [for (final e in newEvents.whereType<StreetDealt>()) ...e.cards];
    final shown = newEvents.whereType<ShowdownRevealed>().firstOrNull;
    final msg = <String, Object?>{
      't': 'act',
      'n': before.handNumber,
      'type': action.type.name,
      'amount': action.amount,
      if (board.isNotEmpty) 'board': board,
      if (shown != null) 'show': {for (final e in shown.hands.entries) '${e.key}': e.value.$1},
    };
    _handActions.add(msg);
    _broadcast(msg);
  }

  /// A player busted from a home-game tournament (place 1 = the winner).
  void sendOut(int seat, int place) => _broadcast({'t': 'out', 'seat': seat, 'place': place});

  /// Tournament or table status line for everyone's header.
  void sendStatus(String title, String status, int pool) {
    _status = {'t': 'status', 'title': title, 'status': status, 'pool': pool};
    _broadcast(_status!);
  }

  void _resync(RemotePlayer p) {
    final hand = _handMessage[p.seat];
    if (hand == null || _handNo < 0) return;
    p.channel?.send({...hand, 'resync': true});
    for (final a in _handActions) {
      p.channel?.send(a);
    }
    if (_status != null) p.channel?.send(_status!);
    final pending = _pending[p.seat];
    if (pending != null) p.channel?.send({'t': 'turn', 'n': pending.$1, 'seconds': settings.actionSeconds});
  }

  /// Asks a friend for their action, with a timer. A timeout or disconnect
  /// checks if possible, otherwise folds.
  Future<PlayerAction> askAction(int seat, HandState s) async {
    final p = playerAt(seat);
    final legal = legalActions(s);
    final fallback = legal.canCheck ? const PlayerAction.check() : const PlayerAction(ActionType.fold);
    if (p == null || !p.connected) return fallback;
    final done = Completer<PlayerAction>();
    _pending[seat] = (s.handNumber, done);
    p.channel!.send({'t': 'turn', 'n': s.handNumber, 'seconds': settings.actionSeconds});
    final action = await done.future
        .timeout(Duration(seconds: settings.actionSeconds + 2), onTimeout: () => fallback);
    _pending.remove(seat);
    // Anything illegal becomes the safe option (the host's engine decides).
    try {
      applyAction(s, action);
      return action;
    } on IllegalActionException {
      return fallback;
    } on Object {
      return fallback;
    }
  }

  Future<void> close({String reason = 'The host closed the game.'}) async {
    _broadcast({'t': 'end', 'reason': reason});
    for (final c in _pending.values) {
      if (!c.$2.isCompleted) c.$2.complete(const PlayerAction(ActionType.fold));
    }
    _announcer?.stop();
    await _server?.close(force: true);
    for (final p in players) {
      await p.channel?.close();
    }
  }
}
