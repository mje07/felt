import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:felt_relay/relay.dart';
import 'package:test/test.dart';

/// A WebSocket with its incoming frames queued for easy awaiting.
class Peer {
  Peer._(this.ws) {
    ws.listen((d) => _in.add(jsonDecode(d as String) as Map<String, Object?>), onDone: () => _in.close());
  }
  static Future<Peer> connect(String url) async => Peer._(await WebSocket.connect(url));

  final WebSocket ws;
  final _in = StreamController<Map<String, Object?>>();
  late final _q = StreamIterator(_in.stream);

  Future<Map<String, Object?>> next() async {
    if (!await _q.moveNext().timeout(const Duration(seconds: 5))) throw StateError('closed');
    return _q.current;
  }

  void send(Object m) => ws.add(jsonEncode(m));
}

void main() {
  late Relay relay;
  String url(String path) => 'ws://127.0.0.1:${relay.port}$path';

  setUp(() async {
    relay = Relay(limits: const RelayLimits(maxClientsPerRoom: 2, maxRooms: 3));
    await relay.start(address: InternetAddress.loopbackIPv4, port: 0);
  });
  tearDown(() => relay.stop());

  test('forwards frames both ways and tells the host who comes and goes', () async {
    final host = await Peer.connect(url('/host'));
    final code = (await host.next())['code'] as String;
    expect(code, hasLength(codeLength));
    expect(code.split('').every(codeAlphabet.contains), isTrue);

    final ann = await Peer.connect(url('/join/${code.toLowerCase()}'));
    final open = await host.next();
    expect(open, {'r': 'open', 'id': 1});

    ann.send({'t': 'hello', 'name': 'Ann'});
    final msg = await host.next();
    expect(msg['r'], 'msg');
    expect(msg['id'], 1);
    expect(jsonDecode(msg['d'] as String), {'t': 'hello', 'name': 'Ann'});

    host.send({'r': 'to', 'id': 1, 'd': jsonEncode({'t': 'welcome', 'seat': 1})});
    expect(await ann.next(), {'t': 'welcome', 'seat': 1});

    await ann.ws.close();
    expect(await host.next(), {'r': 'close', 'id': 1});
    await host.ws.close();
  });

  test('wrong codes, full tables and too many rooms are turned away', () async {
    final nobody = await Peer.connect(url('/join/ABCDEF'));
    expect((await nobody.next())['t'], 'reject');

    final host = await Peer.connect(url('/host'));
    final code = (await host.next())['code'] as String;
    await Peer.connect(url('/join/$code'));
    await Peer.connect(url('/join/$code'));
    final third = await Peer.connect(url('/join/$code'));
    expect(await third.next(), {'t': 'reject', 'reason': 'The table is full.'});

    await Peer.connect(url('/host'));
    await Peer.connect(url('/host'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(relay.roomCount, 3);
    await expectLater(WebSocket.connect(url('/host')), throwsA(isA<WebSocketException>()));
  });

  test('when the host leaves, friends are told and the code stops working', () async {
    final host = await Peer.connect(url('/host'));
    final code = (await host.next())['code'] as String;
    final ann = await Peer.connect(url('/join/$code'));
    await host.next();
    await host.ws.close();
    expect((await ann.next())['t'], 'end');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(relay.roomCount, 0);
    final late = await Peer.connect(url('/join/$code'));
    expect((await late.next())['t'], 'reject');
  });

  test('oversized frames close the sender', () async {
    final host = await Peer.connect(url('/host'));
    final code = (await host.next())['code'] as String;
    final ann = await Peer.connect(url('/join/$code'));
    await host.next();
    ann.ws.add('x' * (20 * 1024));
    expect(await host.next(), {'r': 'close', 'id': 1});
    await ann.ws.done;
    expect(ann.ws.closeCode, WebSocketStatus.policyViolation);
  });

  test('codes never collide', () async {
    final r = Relay(rng: Random(1), limits: const RelayLimits(maxConnectionsPerAddress: 100));
    await r.start(address: InternetAddress.loopbackIPv4, port: 0);
    final codes = <String>{};
    for (var i = 0; i < 40; i++) {
      final p = await Peer.connect('ws://127.0.0.1:${r.port}/host');
      codes.add((await p.next())['code'] as String);
    }
    expect(codes, hasLength(40));
    await r.stop();
  });

  test('health check', () async {
    final c = HttpClient();
    final res = await (await c.getUrl(Uri.parse('http://127.0.0.1:${relay.port}/health'))).close();
    expect(res.statusCode, 200);
    expect(await utf8.decodeStream(res), contains('Felt relay'));
    c.close();
  });
}
