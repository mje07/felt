import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';

import 'host.dart';
import 'protocol.dart';

/// A friend's side of a home game: joins, keeps the lobby, and hands game
/// messages to the table.
class HomeGameClient extends ChangeNotifier {
  HomeGameClient(this.channel, {required this.name, this.token});

  final Channel channel;
  final String name;
  String? token;

  /// Our seat at the host's table, and the game's settings.
  late int seat;
  late HomeGameSettings settings;
  String hostName = 'Host';
  String? myName;

  List<(String, int, bool)> lobby = const [];
  bool started = false;

  /// Why the game ended for us (host closed it, rejected, lost connection).
  String? ended;

  final _game = StreamController<Map<String, Object?>>();
  StreamSubscription<Map<String, Object?>>? _sub;

  /// Game messages (hand, act, turn, status, out, end), in order.
  Stream<Map<String, Object?>> get gameMessages => _game.stream;

  /// Says hello and waits to be seated. Throws a [StateError] with the
  /// host's reason if refused.
  Future<void> join({Duration timeout = const Duration(seconds: 10)}) async {
    final welcome = Completer<void>();
    _sub = channel.messages.listen((m) {
      switch (m['t']) {
        case 'welcome':
          seat = m['seat'] as int;
          token = m['token'] as String?;
          myName = m['name'] as String?;
          hostName = m['host'] as String? ?? 'Host';
          settings = HomeGameSettings.fromJson((m['game'] as Map).cast<String, Object?>());
          if (!welcome.isCompleted) welcome.complete();
        case 'reject':
          if (!welcome.isCompleted) welcome.completeError(StateError(m['reason'] as String? ?? 'Refused'));
        case 'lobby':
          started = m['started'] as bool? ?? false;
          lobby = [
            for (final p in (m['players'] as List? ?? const []))
              ((p as Map)['name'] as String, p['seat'] as int, p['on'] as bool? ?? true),
          ];
          notifyListeners();
        case 'end':
          ended = m['reason'] as String? ?? 'The game is over.';
          _game.add(m);
          notifyListeners();
        default:
          _game.add(m);
      }
    });
    channel.done.then((_) {
      if (ended == null) {
        ended = 'Lost connection to the host.';
        _game.add({'t': 'end', 'reason': ended});
        notifyListeners();
      }
    });
    channel.send({'t': 'hello', 'v': protocolVersion, 'name': name, if (token != null) 'token': token});
    await welcome.future.timeout(timeout, onTimeout: () => throw StateError('The host didn\'t answer.'));
  }

  void act(int hand, String type, int amount) => channel.send({'t': 'act', 'n': hand, 'type': type, 'amount': amount});

  Future<void> leave() async {
    channel.send({'t': 'leave'});
    await _sub?.cancel();
    await channel.close();
  }
}
