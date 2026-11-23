import 'dart:convert';

import 'game_state.dart';

/// A finished hand, stored as its event log (enough to replay it).
class HandHistory {
  HandHistory({
    required this.handNumber,
    required this.playedAt,
    required this.heroSeat,
    required this.heroNet,
    required this.events,
    required this.summary,
  });

  factory HandHistory.fromState(HandState s, {required int heroSeat, DateTime? at}) {
    final start = s.log.whereType<HandStarted>().first;
    final startStack = (start.seats[heroSeat]['stack'] as int?) ?? 0;
    final endStack = s.seats[heroSeat].stack;
    return HandHistory(
      handNumber: s.handNumber,
      playedAt: at ?? DateTime.now(),
      heroSeat: heroSeat,
      heroNet: s.seats[heroSeat].inHand ? endStack - startStack : 0,
      events: [for (final e in s.log) e.toJson()],
      summary: _summary(s),
    );
  }

  factory HandHistory.fromJson(Map<String, Object?> j) => HandHistory(
        handNumber: j['hand'] as int,
        playedAt: DateTime.parse(j['at'] as String),
        heroSeat: j['hero'] as int,
        heroNet: j['net'] as int,
        events: [for (final e in j['events'] as List) (e as Map).cast<String, Object?>()],
        summary: j['summary'] as String,
      );

  final int handNumber;
  final DateTime playedAt;
  final int heroSeat;
  final int heroNet;
  final List<Map<String, Object?>> events;
  final String summary;

  Map<String, Object?> toJson() => {
        'hand': handNumber,
        'at': playedAt.toIso8601String(),
        'hero': heroSeat,
        'net': heroNet,
        'events': events,
        'summary': summary,
      };

  String encode() => jsonEncode(toJson());
  static HandHistory decode(String s) =>
      HandHistory.fromJson((jsonDecode(s) as Map).cast<String, Object?>());
}

String _summary(HandState s) {
  final winners = <int, int>{};
  for (final a in s.awards) {
    for (final e in a.shares.entries) {
      winners[e.key] = (winners[e.key] ?? 0) + e.value;
    }
  }
  final parts = [
    for (final e in winners.entries) '${s.seats[e.key].name} wins ${e.value}'
  ];
  return parts.join(', ');
}
