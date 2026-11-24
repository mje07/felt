import 'dart:io';

import 'package:felt/net/client.dart';
import 'package:felt/net/host.dart';
import 'package:felt/net/protocol.dart';
import 'package:felt/net/relay_link.dart';
import 'package:felt_relay/relay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poker_engine/poker_engine.dart';

void main() {
  test('relay addresses are understood however they are typed', () {
    expect(relayBase('felt-relay.fly.dev').toString(), 'wss://felt-relay.fly.dev');
    expect(relayBase('https://felt-relay.fly.dev/').toString(), 'wss://felt-relay.fly.dev');
    expect(relayBase('ws://localhost:8080').toString(), 'ws://localhost:8080');
    expect(relayBase(''), isNull);
    expect(relayBase('ftp://x.com'), isNull);
    expect(relayFor('').toString(), 'wss://felt-relay.onrender.com');
    expect(relayFor('  ').toString(), 'wss://felt-relay.onrender.com');
    expect(relayFor('ws://localhost:8080').toString(), 'ws://localhost:8080');
    expect(relayFor('ftp://x.com'), isNull);
    expect(relayJoinUri(Uri.parse('wss://r.dev'), ' k7qh2m ').toString(), 'wss://r.dev/join/K7QH2M');
  });

  test('a friend joins with an invite code and plays through the relay', () async {
    final relay = Relay();
    await relay.start(address: InternetAddress.loopbackIPv4, port: 0);
    final base = Uri.parse('ws://127.0.0.1:${relay.port}');

    final host = HomeGameHost(const HomeGameSettings(name: 'Over the internet', seats: 3), hostName: 'Hosty');
    await host.openRelay(base);
    final code = host.inviteCode!;
    expect(code, hasLength(inviteCodeLength));

    // A wrong code gets a clear answer.
    final wrong = HomeGameClient(await SocketChannel.connect(relayJoinUri(base, 'ZZZZZZ')), name: 'Lost');
    await expectLater(wrong.join(), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('invite code'))));

    final ann = HomeGameClient(await SocketChannel.connect(relayJoinUri(base, code.toLowerCase())), name: 'Ann');
    await ann.join();
    expect(ann.seat, 1);
    expect(ann.hostName, 'Hosty');
    host.markStarted();

    final got = <Map<String, Object?>>[];
    final sub = ann.gameMessages.listen(got.add);
    final s = startHand(
      players: const [SeatSetup('Hosty', 1000), SeatSetup('Ann', 1000), SeatSetup('Bot', 1000)],
      button: 0,
      smallBlind: 5,
      bigBlind: 10,
      handNumber: 1,
    );
    host.sendHand(s, anteFromEveryone: false);

    // Whoever acts first, a friend's turn goes out and their answer comes back.
    final asking = host.askAction(s.toAct, s);
    Future<void> until(bool Function() ok) async {
      for (var i = 0; i < 100 && !ok(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    if (s.toAct == ann.seat) {
      await until(() => got.any((m) => m['t'] == 'turn'));
      ann.act(1, 'call', 0);
      expect((await asking).type, ActionType.call);
    } else {
      await asking;
    }
    await until(() => got.any((m) => m['t'] == 'hand'));
    final hand = got.firstWhere((m) => m['t'] == 'hand');
    expect((hand['hole'] as List).cast<int>(), s.seats[1].hole);
    expect(hand.toString(), isNot(contains('${s.seats[0].hole}')));

    // The host closing the table ends the game for Ann.
    await host.close();
    await until(() => ann.ended != null);
    expect(ann.ended, isNotNull);
    await sub.cancel();
    await relay.stop();
  });
}
