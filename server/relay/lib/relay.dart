/// Felt's invite-code relay.
///
/// A host connects to `/host` and is given a short invite code. Friends
/// connect to `/join/CODE`. The relay only forwards frames: it never looks
/// inside them and stores nothing. The host's single connection carries every
/// friend's traffic, wrapped in small envelopes:
///
///   relay to host:  {"r":"code","code":"K7QH2M"}
///                   {"r":"open","id":3}   {"r":"msg","id":3,"d":"FRAME"}
///                   {"r":"close","id":3}
///   host to relay:  {"r":"to","id":3,"d":"FRAME"}   {"r":"kick","id":3}
///
/// Friends see plain frames, exactly as if connected to the host directly.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Limits that keep a free-tier relay healthy.
class RelayLimits {
  const RelayLimits({
    this.maxRooms = 500,
    this.maxClientsPerRoom = 8,
    this.maxFrameBytes = 16 * 1024,
    this.maxFramesPerSecond = 40,
    this.idleTimeout = const Duration(minutes: 15),
    this.maxConnectionsPerAddress = 20,
  });

  final int maxRooms, maxClientsPerRoom, maxFrameBytes, maxFramesPerSecond, maxConnectionsPerAddress;
  final Duration idleTimeout;
}

/// Invite codes avoid look-alike characters (0/O, 1/I/L).
const codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const codeLength = 6;

class _Room {
  _Room(this.code, this.host);
  final String code;
  final WebSocket host;
  final Map<int, WebSocket> clients = {};
  int nextId = 1;
  DateTime lastActivity = DateTime.now();
}

/// Counts frames per second for one connection.
class _Rate {
  _Rate(this.limit);
  final int limit;
  DateTime _start = DateTime.now();
  int _n = 0;

  bool allow() {
    final now = DateTime.now();
    if (now.difference(_start).inMilliseconds >= 1000) {
      _start = now;
      _n = 0;
    }
    return ++_n <= limit;
  }
}

class Relay {
  Relay({this.limits = const RelayLimits(), Random? rng}) : _rng = rng ?? Random.secure();

  final RelayLimits limits;
  final Random _rng;
  final Map<String, _Room> _rooms = {};
  final Map<String, int> _perAddress = {};
  HttpServer? _server;
  Timer? _sweeper;

  int get roomCount => _rooms.length;
  int get port => _server!.port;

  /// Starts serving on [port] (0 picks a free one).
  Future<void> start({InternetAddress? address, int port = 8080}) async {
    final server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    _server = server;
    _sweeper = Timer.periodic(const Duration(seconds: 30), (_) => _sweep());
    server.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    _sweeper?.cancel();
    for (final room in _rooms.values.toList()) {
      await _closeRoom(room);
    }
    await _server?.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    if (path == '/' || path == '/health') {
      req.response
        ..headers.contentType = ContentType.text
        ..write('Felt relay: ${_rooms.length} tables open\n');
      await req.response.close();
      return;
    }
    final isHost = path == '/host';
    final join = RegExp('^/join/([${codeAlphabet}a-z]{$codeLength})\$').firstMatch(path);
    if ((!isHost && join == null) || !WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final addr = req.connectionInfo?.remoteAddress.address ?? '?';
    if ((_perAddress[addr] ?? 0) >= limits.maxConnectionsPerAddress) {
      req.response.statusCode = HttpStatus.tooManyRequests;
      await req.response.close();
      return;
    }
    final room = join == null ? null : _rooms[join[1]!.toUpperCase()];
    if (isHost && _rooms.length >= limits.maxRooms) {
      req.response.statusCode = HttpStatus.serviceUnavailable;
      await req.response.close();
      return;
    }
    final WebSocket ws;
    try {
      ws = await WebSocketTransformer.upgrade(req);
    } catch (_) {
      return;
    }
    ws.pingInterval = const Duration(seconds: 20);
    _perAddress[addr] = (_perAddress[addr] ?? 0) + 1;
    unawaited(ws.done.whenComplete(() {
      final n = (_perAddress[addr] ?? 1) - 1;
      if (n <= 0) {
        _perAddress.remove(addr);
      } else {
        _perAddress[addr] = n;
      }
    }));
    if (isHost) {
      _hostConnected(ws);
    } else if (room == null) {
      // Tell the friend in the game's own language, then hang up.
      ws.add(jsonEncode({'t': 'reject', 'reason': 'No table with that invite code. Check it and try again.'}));
      await ws.close(WebSocketStatus.normalClosure);
    } else if (room.clients.length >= limits.maxClientsPerRoom) {
      ws.add(jsonEncode({'t': 'reject', 'reason': 'The table is full.'}));
      await ws.close(WebSocketStatus.normalClosure);
    } else {
      _clientConnected(room, ws);
    }
  }

  String _newCode() {
    while (true) {
      final code = List.generate(codeLength, (_) => codeAlphabet[_rng.nextInt(codeAlphabet.length)]).join();
      if (!_rooms.containsKey(code)) return code;
    }
  }

  void _hostConnected(WebSocket ws) {
    final room = _Room(_newCode(), ws);
    _rooms[room.code] = room;
    ws.add(jsonEncode({'r': 'code', 'code': room.code}));
    final rate = _Rate(limits.maxFramesPerSecond * (limits.maxClientsPerRoom + 1));
    ws.listen(
      (data) {
        if (data is! String || data.length > limits.maxFrameBytes * 2 || !rate.allow()) {
          unawaited(_closeRoom(room, why: WebSocketStatus.policyViolation));
          return;
        }
        room.lastActivity = DateTime.now();
        final Object? m;
        try {
          m = jsonDecode(data);
        } catch (_) {
          return;
        }
        if (m is! Map) return;
        final client = room.clients[m['id']];
        if (client == null) return;
        switch (m['r']) {
          case 'to':
            final d = m['d'];
            if (d is String && d.length <= limits.maxFrameBytes) client.add(d);
          case 'kick':
            room.clients.remove(m['id']);
            unawaited(client.close(WebSocketStatus.normalClosure));
        }
      },
      onDone: () => _closeRoom(room),
      onError: (_) => _closeRoom(room),
      cancelOnError: true,
    );
  }

  void _clientConnected(_Room room, WebSocket ws) {
    final id = room.nextId++;
    room.clients[id] = ws;
    room.host.add(jsonEncode({'r': 'open', 'id': id}));
    final rate = _Rate(limits.maxFramesPerSecond);
    void gone() {
      if (room.clients.remove(id) != null && _rooms[room.code] == room) {
        room.host.add(jsonEncode({'r': 'close', 'id': id}));
      }
    }

    ws.listen(
      (data) {
        if (data is! String || data.length > limits.maxFrameBytes || !rate.allow()) {
          gone();
          unawaited(ws.close(WebSocketStatus.policyViolation));
          return;
        }
        room.lastActivity = DateTime.now();
        room.host.add(jsonEncode({'r': 'msg', 'id': id, 'd': data}));
      },
      onDone: gone,
      onError: (_) => gone(),
      cancelOnError: true,
    );
  }

  Future<void> _closeRoom(_Room room, {int why = WebSocketStatus.goingAway}) async {
    if (_rooms[room.code] != room) return;
    _rooms.remove(room.code);
    for (final c in room.clients.values.toList()) {
      c.add(jsonEncode({'t': 'end', 'reason': 'The host left the game.'}));
      await c.close(WebSocketStatus.goingAway);
    }
    room.clients.clear();
    await room.host.close(why);
  }

  void _sweep() {
    final cutoff = DateTime.now().subtract(limits.idleTimeout);
    for (final room in _rooms.values.toList()) {
      if (room.lastActivity.isBefore(cutoff)) unawaited(_closeRoom(room));
    }
  }
}
