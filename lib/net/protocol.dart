import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Home-game protocol. Every message is a JSON object with a type `t`.
///
/// Client to host:
///   hello {v, name, token?}   act {n, type, amount}   leave {}
/// Host to client:
///   welcome {seat, token, game}   reject {reason}   lobby {players, started}
///   hand {n, seats, button, sbSeat, bbSeat, sb, bb, ante, anteAll, hole}
///   act {n, type, amount, board?, show?}   turn {n, seconds}
///   status {title, status, pool}   end {reason}
///
/// The host never sends a player anyone else's hole cards before showdown.
const protocolVersion = 1;

/// TCP port for hosting, and the UDP port games are announced on.
const defaultGamePort = 47110;
const discoveryPort = 47111;

/// Largest message accepted, and how many a connection may send per second.
const maxMessageBytes = 16 * 1024;
const maxMessagesPerSecond = 40;

/// A two-way message pipe (a WebSocket, the relay, or memory in tests).
abstract class Channel {
  Stream<Map<String, Object?>> get messages;
  void send(Map<String, Object?> message);
  Future<void> close();

  /// Completes when the other side goes away.
  Future<void> get done;
}

/// A [Channel] over a WebSocket, with size and rate limits on what arrives.
class SocketChannel implements Channel {
  SocketChannel(this._socket) {
    _socket.listen(
      (data) {
        if (data is! String || data.length > maxMessageBytes) return _drop('Message too large');
        final now = DateTime.now();
        if (now.difference(_windowStart).inMilliseconds > 1000) {
          _windowStart = now;
          _count = 0;
        }
        if (++_count > maxMessagesPerSecond) return _drop('Too many messages');
        try {
          final m = jsonDecode(data);
          if (m is Map<String, Object?> && m['t'] is String) _in.add(m);
        } catch (_) {
          // Ignore garbage.
        }
      },
      onDone: () {
        _in.close();
        if (!_done.isCompleted) _done.complete();
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  static Future<SocketChannel> connect(Uri uri, {Duration timeout = const Duration(seconds: 8)}) async =>
      SocketChannel(await WebSocket.connect(uri.toString()).timeout(timeout));

  final WebSocket _socket;
  final _in = StreamController<Map<String, Object?>>.broadcast();
  final _done = Completer<void>();
  DateTime _windowStart = DateTime.now();
  int _count = 0;

  void _drop(String why) {
    _socket.close(WebSocketStatus.policyViolation, why);
  }

  @override
  Stream<Map<String, Object?>> get messages => _in.stream;

  @override
  void send(Map<String, Object?> message) {
    if (_socket.readyState == WebSocket.open) _socket.add(jsonEncode(message));
  }

  @override
  Future<void> close() => _socket.close();

  @override
  Future<void> get done => _done.future;
}

/// Two connected in-memory channels (tests, and the host's own seat).
(Channel, Channel) memoryChannelPair() {
  final a = _MemoryChannel(), b = _MemoryChannel();
  a._peer = b;
  b._peer = a;
  return (a, b);
}

class _MemoryChannel implements Channel {
  late _MemoryChannel _peer;
  final _in = StreamController<Map<String, Object?>>.broadcast();
  final _done = Completer<void>();

  @override
  Stream<Map<String, Object?>> get messages => _in.stream;

  @override
  void send(Map<String, Object?> message) {
    if (_peer._in.isClosed) return;
    // Round-trip through JSON so tests see exactly what a socket would carry.
    final copy = jsonDecode(jsonEncode(message)) as Map<String, Object?>;
    scheduleMicrotask(() {
      if (!_peer._in.isClosed) _peer._in.add(copy);
    });
  }

  @override
  Future<void> close() async {
    for (final c in [this, _peer]) {
      if (!c._done.isCompleted) c._done.complete();
      unawaited(c._in.close());
    }
  }

  @override
  Future<void> get done => _done.future;
}

/// A game announced on the local network.
class LanGame {
  const LanGame({required this.name, required this.host, required this.port, required this.players, required this.seats});
  final String name, host;
  final int port, players, seats;

  Uri get uri => Uri(scheme: 'ws', host: host, port: port, path: '/felt');

  static LanGame? parse(String json, String fromAddress) {
    try {
      final m = jsonDecode(json) as Map<String, Object?>;
      if (m['felt'] != protocolVersion) return null;
      return LanGame(
        name: (m['name'] as String? ?? 'Felt game').characters(40),
        host: fromAddress,
        port: m['port'] as int,
        players: m['players'] as int,
        seats: m['seats'] as int,
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode({'felt': protocolVersion, 'name': name, 'port': port, 'players': players, 'seats': seats});
}

extension on String {
  String characters(int max) => length <= max ? this : substring(0, max);
}

/// Listens for games announced on the LAN.
class LanDiscovery {
  RawDatagramSocket? _socket;
  final _games = <String, (LanGame, DateTime)>{};
  final _changes = StreamController<List<LanGame>>.broadcast();

  Stream<List<LanGame>> get games => _changes.stream;

  List<LanGame> get current {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 4));
    _games.removeWhere((_, v) => v.$2.isBefore(cutoff));
    return [for (final v in _games.values) v.$1];
  }

  Future<void> start() async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort, reuseAddress: true);
    } catch (_) {
      return; // Port busy (e.g. hosting on this PC): manual join still works.
    }
    _socket!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final d = _socket?.receive();
      if (d == null || d.data.length > 512) return;
      final g = LanGame.parse(utf8.decode(d.data, allowMalformed: true), d.address.address);
      if (g == null) return;
      _games['${g.host}:${g.port}'] = (g, DateTime.now());
      _changes.add(current);
    });
  }

  void stop() {
    _socket?.close();
    _socket = null;
    _changes.close();
  }
}

/// Announces a hosted game on the LAN once a second.
class LanAnnouncer {
  LanAnnouncer(this.describe);
  final LanGame Function() describe;
  RawDatagramSocket? _socket;
  Timer? _timer;

  Future<void> start() async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)..broadcastEnabled = true;
    } catch (_) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      try {
        _socket?.send(utf8.encode(describe().encode()), InternetAddress('255.255.255.255'), discoveryPort);
      } catch (_) {}
    });
  }

  void stop() {
    _timer?.cancel();
    _socket?.close();
  }
}

/// This PC's IPv4 addresses on the local network (for "join at …").
Future<List<String>> localAddresses() async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final i in interfaces)
        for (final a in i.addresses)
          if (!a.isLoopback) a.address,
    ];
  } catch (_) {
    return const [];
  }
}
