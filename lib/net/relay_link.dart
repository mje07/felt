import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol.dart';

/// Turns a relay address the user typed ("felt-relay.fly.dev",
/// "https://…", "ws://localhost:8080") into its WebSocket base URI.
Uri? relayBase(String text) {
  var t = text.trim();
  if (t.isEmpty) return null;
  if (!t.contains('://')) t = 'wss://$t';
  final u = Uri.tryParse(t);
  if (u == null || u.host.isEmpty) return null;
  final scheme = switch (u.scheme) { 'https' || 'wss' => 'wss', 'http' || 'ws' => 'ws', _ => null };
  if (scheme == null) return null;
  return u.replace(scheme: scheme, path: '', query: null, fragment: null);
}

/// Invite codes are six characters (no look-alikes like 0/O or 1/I).
const inviteCodeLength = 6;

/// Where a friend connects to join with [code].
Uri relayJoinUri(Uri base, String code) => base.replace(path: '/join/${code.trim().toUpperCase()}');

/// The host's connection to the relay. Each friend who joins with the
/// invite code arrives as a [Channel] on [connections].
class RelayHostLink {
  RelayHostLink._(this._socket);

  final WebSocket _socket;
  final _channels = <int, _RelayChannel>{};
  final _connections = StreamController<Channel>();
  final _closed = Completer<void>();
  late String code;

  Stream<Channel> get connections => _connections.stream;

  /// Completes when the relay connection drops.
  Future<void> get closed => _closed.future;

  static Future<RelayHostLink> connect(Uri base, {Duration timeout = const Duration(seconds: 10)}) async {
    final ws = await WebSocket.connect(base.replace(path: '/host').toString()).timeout(timeout);
    final link = RelayHostLink._(ws);
    final gotCode = Completer<void>();
    ws.listen(
      (data) {
        if (data is! String) return;
        final Object? m;
        try {
          m = jsonDecode(data);
        } catch (_) {
          return;
        }
        if (m is! Map) return;
        final id = m['id'];
        switch (m['r']) {
          case 'code':
            link.code = m['code'] as String;
            if (!gotCode.isCompleted) gotCode.complete();
          case 'open' when id is int:
            final ch = _RelayChannel(link, id);
            link._channels[id] = ch;
            link._connections.add(ch);
          case 'msg' when id is int:
            link._channels[id]?._receive(m['d']);
          case 'close' when id is int:
            link._channels.remove(id)?._end();
        }
      },
      onDone: () {
        for (final c in link._channels.values) {
          c._end();
        }
        link._channels.clear();
        if (!link._closed.isCompleted) link._closed.complete();
        if (!gotCode.isCompleted) gotCode.completeError(StateError('The relay closed the connection.'));
      },
      onError: (_) {},
    );
    await gotCode.future.timeout(timeout);
    return link;
  }

  void _send(int id, Map<String, Object?> m) {
    _add({'r': 'to', 'id': id, 'd': jsonEncode(m)});
  }

  void _add(Map<String, Object?> m) {
    if (_socket.readyState != WebSocket.open) return;
    try {
      _socket.add(jsonEncode(m));
    } on StateError {
      // Closing.
    }
  }

  void _kick(int id) {
    _channels.remove(id)?._end();
    _add({'r': 'kick', 'id': id});
  }

  Future<void> close() async {
    await _socket.close();
    await _connections.close();
  }
}

class _RelayChannel implements Channel {
  _RelayChannel(this._link, this._id);
  final RelayHostLink _link;
  final int _id;
  final _in = StreamController<Map<String, Object?>>.broadcast();
  final _done = Completer<void>();
  DateTime _windowStart = DateTime.now();
  int _count = 0;

  void _receive(Object? d) {
    if (d is! String || d.length > maxMessageBytes) return _link._kick(_id);
    final now = DateTime.now();
    if (now.difference(_windowStart).inMilliseconds > 1000) {
      _windowStart = now;
      _count = 0;
    }
    if (++_count > maxMessagesPerSecond) return _link._kick(_id);
    try {
      final m = jsonDecode(d);
      if (m is Map<String, Object?> && m['t'] is String) _in.add(m);
    } catch (_) {}
  }

  void _end() {
    if (!_done.isCompleted) _done.complete();
    unawaited(_in.close());
  }

  @override
  Stream<Map<String, Object?>> get messages => _in.stream;

  @override
  void send(Map<String, Object?> message) {
    if (!_done.isCompleted) _link._send(_id, message);
  }

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _link._kick(_id);
  }

  @override
  Future<void> get done => _done.future;
}
