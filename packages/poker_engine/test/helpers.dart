import 'package:poker_engine/poker_engine.dart';

/// Builds a deck so that seats receive [holes] (listed in deal order,
/// i.e. starting with the small blind) and the board is [board].
List<int> stackedDeck(List<String> holes, String board) {
  final hs = [for (final h in holes) parseCards(h)];
  final b = parseCards(board);
  final used = {for (final h in hs) ...h, ...b};
  final rest = [for (var c = 0; c < 52; c++) if (!used.contains(c)) c];
  var r = 0;
  return [
    for (final h in hs) h[0],
    for (final h in hs) h[1],
    rest[r++], b[0], b[1], b[2],
    rest[r++], b[3],
    rest[r++], b[4],
    ...rest.sublist(r),
  ];
}

HandState deal(List<int> stacks,
    {int button = 0, int sb = 5, int bb = 10, List<int>? deck}) {
  return startHand(
    players: [for (var i = 0; i < stacks.length; i++) SeatSetup('P$i', stacks[i])],
    button: button,
    smallBlind: sb,
    bigBlind: bb,
    handNumber: 1,
    deck: deck ?? List<int>.generate(52, (i) => i),
  );
}

HandState act(HandState s, PlayerAction a) => applyAction(s, a);
const fold = PlayerAction.fold();
const check = PlayerAction.check();
const call = PlayerAction.call();
PlayerAction raise(int to) => PlayerAction.raiseTo(to);
