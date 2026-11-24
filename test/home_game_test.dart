import 'package:felt/app/controller.dart';
import 'package:felt/app/history_store.dart';
import 'package:felt/app/settings.dart';
import 'package:felt/net/client.dart';
import 'package:felt/net/host.dart';
import 'package:felt/net/protocol.dart';
import 'package:felt/screens/friends_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poker_engine/poker_engine.dart';

/// A friend connected over an in-memory channel, with every message they
/// receive recorded.
class Friend {
  Friend(this.name, HomeGameHost host) {
    final (a, b) = memoryChannelPair();
    host.accept(a);
    channel = b;
    b.messages.listen(received.add);
    client = HomeGameClient(b, name: name);
  }
  final String name;
  late final Channel channel;
  late final HomeGameClient client;
  final received = <Map<String, Object?>>[];
  final history = HistoryStore.memory();
  late GameController controller;
}

Settings quick() => Settings.memory()
  ..speed = GameSpeed.quick
  ..reduceMotion = true;

void main() {
  for (final sng in [false, true]) {
  testWidgets('a home ${sng ? 'Sit & Go' : 'cash game'} keeps every player in sync and never leaks hole cards', (tester) async {
    final host = HomeGameHost(
        HomeGameSettings(name: 'Friday', seats: 4, tournament: sng, speed: BlindSpeed.hyper), hostName: 'Hosty');
    final ann = Friend('Ann', host), bob = Friend('Bob', host);
    await ann.client.join();
    await bob.client.join();
    expect(host.players.map((p) => p.name), ['Ann', 'Bob']);
    expect(ann.client.seat, isNot(bob.client.seat));
    host.markStarted();

    final hostHistory = HistoryStore.memory();
    final config = homeGameConfig(host.settings);
    final hostCtl = GameController(config: config, settings: quick(), history: hostHistory, host: host, useIsolates: false);
    for (final f in [ann, bob]) {
      f.controller =
          GameController(config: config, settings: quick(), history: f.history, client: f.client, useIsolates: false);
    }
    hostCtl.start();
    ann.controller.start();
    bob.controller.start();

    var i = 0;
    while (hostHistory.hands.length < (sng ? 30 : 12) && hostCtl.outcome == null && i++ < 60000) {
      await tester.pump(const Duration(milliseconds: 50));
      for (final c in [hostCtl, ann.controller, bob.controller]) {
        final l = c.heroLegal;
        if (l == null) continue;
        // Friends call everything; the host only checks, so it outlasts them.
        c.act(l.canCheck ? const PlayerAction.check() : (identical(c, hostCtl) && sng ? const PlayerAction(ActionType.fold) : const PlayerAction.call()));
      }
      if (hostCtl.heroBusted) hostCtl.rebuy(); // free in home games
      if (hostCtl.handOver) hostCtl.dealNext();
    }
    expect(hostHistory.hands.length, greaterThanOrEqualTo(sng ? 3 : 12));
    if (sng) {
      // Both friends are told where everyone finished.
      for (final f in [ann, bob]) {
        expect(f.received.where((m) => m['t'] == 'out'), isNotEmpty, reason: f.name);
      }
    }
    await tester.pump(const Duration(seconds: 2));

    // Every hand a friend finished ends with the host's exact stacks.
    for (final f in [ann, bob]) {
      expect(f.history.hands, isNotEmpty);
      for (final h in f.history.hands) {
        final hostHand = hostHistory.hands.firstWhere((x) => x.handNumber == h.handNumber);
        final hostEnd = (hostHand.events.last['stacks'] as Map).cast<String, Object?>();
        final mine = (h.events.last['stacks'] as Map).cast<String, Object?>();
        for (final e in hostEnd.entries) {
          final mirrorSeat = (int.parse(e.key) - f.client.seat + 4) % 4;
          expect(mine['$mirrorSeat'], e.value, reason: '${f.name} hand ${h.handNumber} seat ${e.key}');
        }
      }
    }

    // Nobody is sent anyone else's cards before showdown.
    for (final f in [ann, bob]) {
      for (final m in f.received) {
        if (m['t'] == 'hand') {
          final hole = (m['hole'] as List).cast<int>();
          final mirror = f.history.hands.where((h) => h.handNumber == m['n']).firstOrNull;
          if (mirror != null) expect(hole, mirror.heroHole);
          // Exactly one set of cards in the deal message: ours.
          expect(m.keys.where((k) => k == 'hole').length, 1);
        }
        if (m['t'] == 'act' && m['show'] != null) {
          // Cards are only shown by the action that ends the hand at showdown.
          final hand = hostHistory.hands.firstWhere((h) => h.handNumber == m['n']);
          expect(hand.events.any((e) => e['e'] == 'showdown'), isTrue);
          final acts = f.received.where((x) => x['t'] == 'act' && x['n'] == m['n']).toList();
          expect(identical(acts.last, m), isTrue, reason: 'cards shown before the last action of hand ${m['n']}');
        }
      }
    }

    hostCtl.dispose();
    bob.controller.dispose();
    ann.controller.dispose();
    await host.close();
    await tester.pump(const Duration(seconds: 5));
  }, timeout: const Timeout(Duration(minutes: 5)));
  }

  test('hosting over a real WebSocket: join, lobby, version check', () async {
    final host = HomeGameHost(const HomeGameSettings(name: 'Socket game', seats: 3), hostName: 'Hosty');
    await host.listen(port: 0, announce: false);
    final uri = Uri.parse('ws://127.0.0.1:${host.port}/felt');
    final client = HomeGameClient(await SocketChannel.connect(uri), name: 'Cleo');
    await client.join();
    expect(client.seat, 1);
    expect(client.settings.name, 'Socket game');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(client.lobby.map((p) => p.$1), ['Hosty', 'Cleo']);

    // An older or newer Felt is turned away politely.
    final ch = await SocketChannel.connect(uri);
    final reply = ch.messages.first;
    ch.send({'t': 'hello', 'v': protocolVersion + 1, 'name': 'Future'});
    final m = await reply.timeout(const Duration(seconds: 5));
    expect(m['t'], 'reject');
    await client.leave();
    await host.close();
  });

  test('a friend who drops comes back to the same seat with their token, mid-hand', () async {
    final host = HomeGameHost(const HomeGameSettings(seats: 3), hostName: 'Hosty');
    final (a, b) = memoryChannelPair();
    host.accept(a);
    final ann = HomeGameClient(b, name: 'Ann');
    await ann.join();
    host.markStarted();

    // Late joiners without a token are turned away once the game starts.
    final (c, d) = memoryChannelPair();
    host.accept(c);
    await expectLater(HomeGameClient(d, name: 'Late').join(), throwsStateError);

    final s = startHand(
      players: const [SeatSetup('Hosty', 1000), SeatSetup('Ann', 1000), SeatSetup('Bot', 1000)],
      button: 0,
      smallBlind: 5,
      bigBlind: 10,
      handNumber: 1,
    );
    host.sendHand(s, anteFromEveryone: false);
    await Future<void>.delayed(Duration.zero);

    final token = ann.token!;
    await ann.leave();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(host.playerAt(ann.seat)!.connected, isFalse);

    final (e, f) = memoryChannelPair();
    host.accept(e);
    final back = <Map<String, Object?>>[];
    f.messages.listen(back.add);
    final rejoin = HomeGameClient(f, name: 'Ann', token: token);
    await rejoin.join();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(rejoin.seat, ann.seat);
    expect(host.playerAt(ann.seat)!.connected, isTrue);
    final resync = back.firstWhere((m) => m['t'] == 'hand');
    expect(resync['resync'], isTrue);
    expect((resync['hole'] as List).cast<int>(), s.seats[ann.seat].hole);
    await host.close();
  });

  test('LAN announcements parse, and junk is ignored', () {
    const g = LanGame(name: 'Friday', host: '', port: 47110, players: 2, seats: 6);
    final parsed = LanGame.parse(g.encode(), '192.168.1.20')!;
    expect(parsed.name, 'Friday');
    expect(parsed.uri.toString(), 'ws://192.168.1.20:47110/felt');
    expect(LanGame.parse('not json', '1.2.3.4'), isNull);
    expect(LanGame.parse('{"felt": 99, "port": 1}', '1.2.3.4'), isNull);
  });
}
