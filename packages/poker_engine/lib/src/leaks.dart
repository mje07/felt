import 'coach/review.dart';
import 'game_state.dart';
import 'history.dart';

/// A recurring mistake and what it costs.
class Leak {
  Leak(this.street, this.kind);
  final Street street;
  final MistakeKind kind;

  /// Graded decisions in this category, and the EV they gave up.
  int spots = 0;
  double lostBb = 0;

  /// Cost spread over every hand analysed.
  double bbPer100 = 0;

  String get title => '${street.name[0].toUpperCase()}${street.name.substring(1)}: ${kind.label.toLowerCase()}';
}

/// Groups the coach's graded mistakes by street and type, ranked by how
/// much they cost per 100 hands. Only categories seen at least [minSpots]
/// times are reported.
List<Leak> findLeaks(Iterable<HandHistory> hands, {int minSpots = 3}) {
  final byKey = <String, Leak>{};
  var count = 0;
  for (final h in hands) {
    count++;
    for (final r in h.reviews) {
      final kind = r.kind;
      if (kind == null || r.grade.index < Grade.inaccuracy.index) continue;
      final leak = byKey.putIfAbsent('${r.street.name}/${kind.name}', () => Leak(r.street, kind));
      leak.spots++;
      leak.lostBb += r.lossBb ?? 0;
    }
  }
  final out = [for (final l in byKey.values) if (l.spots >= minSpots) l];
  for (final l in out) {
    l.bbPer100 = count == 0 ? 0 : l.lostBb / count * 100;
  }
  out.sort((a, b) {
    final c = b.bbPer100.compareTo(a.bbPer100);
    return c != 0 ? c : b.spots.compareTo(a.spots);
  });
  return out;
}
