import 'dart:convert';

import 'coach/review.dart';
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
    this.heroHole,
    this.reviews = const [],
    this.mode = 'cash',
    this.level,
    this.source,
    this.sourceId,
  });

  factory HandHistory.fromState(HandState s,
      {required int heroSeat, DateTime? at, List<DecisionReview> reviews = const [], String mode = 'cash', int? level}) {
    final start = s.log.whereType<HandStarted>().first;
    final startStack = (start.seats[heroSeat]['stack'] as int?) ?? 0;
    final hero = s.seats[heroSeat];
    return HandHistory(
      handNumber: s.handNumber,
      playedAt: at ?? DateTime.now(),
      heroSeat: heroSeat,
      heroNet: hero.inHand ? hero.stack - startStack : 0,
      events: [for (final e in s.log) e.toJson()],
      summary: _summary(s, heroSeat),
      heroHole: hero.inHand ? List.of(hero.hole) : null,
      reviews: reviews,
      mode: mode,
      level: level,
    );
  }

  factory HandHistory.fromJson(Map<String, Object?> j) => HandHistory(
        handNumber: j['hand'] as int,
        playedAt: DateTime.parse(j['at'] as String),
        heroSeat: j['hero'] as int,
        heroNet: j['net'] as int,
        events: [for (final e in j['events'] as List) (e as Map).cast<String, Object?>()],
        summary: j['summary'] as String,
        heroHole: (j['hole'] as List?)?.cast<int>(),
        mode: (j['mode'] as String?) ?? 'cash',
        level: j['level'] as int?,
        source: j['source'] as String?,
        sourceId: j['sourceId'] as String?,
        reviews: [
          for (final r in (j['reviews'] as List?) ?? const [])
            DecisionReview.fromJson((r as Map).cast<String, Object?>()),
        ],
      );

  final int handNumber;
  final DateTime playedAt;
  final int heroSeat;
  final int heroNet;
  final List<Map<String, Object?>> events;
  final String summary;

  /// The hero's hole cards (null for records made before this was stored,
  /// or if the hero sat the hand out).
  final List<int>? heroHole;

  /// The coach's grades for the hero's decisions (empty for older records).
  final List<DecisionReview> reviews;

  /// 'cash' or 'sng'.
  final String mode;

  /// Tournament blind level (1-based), if [mode] is 'sng'.
  final int? level;
  bool get isTournament => mode != 'cash';

  /// Where an imported hand came from ('PokerStars', 'GGPoker'); null for
  /// hands played in Felt. [sourceId] is the site's hand number.
  final String? source, sourceId;
  bool get isImported => source != null;

  Map<String, Object?> toJson() => {
        'hand': handNumber,
        'at': playedAt.toIso8601String(),
        'hero': heroSeat,
        'net': heroNet,
        'events': events,
        'summary': summary,
        if (heroHole != null) 'hole': heroHole,
        if (reviews.isNotEmpty) 'reviews': [for (final r in reviews) r.toJson()],
        if (mode != 'cash') 'mode': mode,
        if (level != null) 'level': level,
        if (source != null) 'source': source,
        if (sourceId != null) 'sourceId': sourceId,
      };

  String encode() => jsonEncode(toJson());
  static HandHistory decode(String s) =>
      HandHistory.fromJson((jsonDecode(s) as Map).cast<String, Object?>());
}

String _summary(HandState s, int heroSeat) {
  final winners = <int, int>{};
  for (final a in s.awards) {
    for (final e in a.shares.entries) {
      winners[e.key] = (winners[e.key] ?? 0) + e.value;
    }
  }
  return [
    for (final e in winners.entries) e.key == heroSeat ? 'You win ${e.value}' : '${s.seats[e.key].name} wins ${e.value}'
  ].join(', ');
}
