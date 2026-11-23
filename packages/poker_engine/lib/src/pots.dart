import 'game_state.dart';

/// Builds main + side pots from each seat's total contribution.
///
/// Folded players' chips stay in the pots but they are not eligible.
/// Adjacent layers with identical eligibility are merged.
List<Pot> buildPots(List<Seat> seats) {
  final contributors = seats.where((s) => s.inHand && s.totalBet > 0).toList();
  final levels = contributors
      .where((s) => !s.folded)
      .map((s) => s.totalBet)
      .toSet()
      .toList()
    ..sort();
  final pots = <Pot>[];
  var prev = 0;
  for (final level in levels) {
    var amount = 0;
    for (final s in contributors) {
      final c = s.totalBet;
      amount += (c < level ? c : level) - (c < prev ? c : prev);
    }
    final eligible = [
      for (final s in contributors)
        if (!s.folded && s.totalBet >= level) s.index
    ];
    if (pots.isNotEmpty && _sameSet(pots.last.eligible, eligible)) {
      pots[pots.length - 1] = Pot(pots.last.amount + amount, eligible);
    } else if (amount > 0) {
      pots.add(Pot(amount, eligible));
    }
    prev = level;
  }
  // Dead money above the highest live contribution (rare) joins the last pot.
  var leftover = 0;
  for (final s in contributors) {
    if (s.totalBet > prev) leftover += s.totalBet - prev;
  }
  if (leftover > 0 && pots.isNotEmpty) {
    pots[pots.length - 1] =
        Pot(pots.last.amount + leftover, pots.last.eligible);
  }
  return pots;
}

bool _sameSet(List<int> a, List<int> b) =>
    a.length == b.length && a.toSet().containsAll(b);

/// Splits each pot among the best eligible hands.
///
/// [handValues] maps live seat -> hand value (omit for an uncontested pot).
/// Odd chips go one at a time to winners in seat order starting left of the
/// button.
List<PotAward> awardPots({
  required List<Pot> pots,
  required Map<int, int> handValues,
  required int button,
  required int seatCount,
}) {
  final awards = <PotAward>[];
  for (var i = 0; i < pots.length; i++) {
    final pot = pots[i];
    List<int> winners;
    int? best;
    if (pot.eligible.length == 1 || handValues.isEmpty) {
      winners = [pot.eligible.first];
    } else {
      best = pot.eligible.map((s) => handValues[s]!).reduce((a, b) => a > b ? a : b);
      winners = [for (final s in pot.eligible) if (handValues[s] == best) s];
    }
    int dist(int s) => (s - button - 1 + seatCount) % seatCount;
    winners.sort((a, b) => dist(a).compareTo(dist(b)));
    final share = pot.amount ~/ winners.length;
    var odd = pot.amount - share * winners.length;
    final shares = <int, int>{};
    for (final w in winners) {
      shares[w] = share + (odd > 0 ? 1 : 0);
      if (odd > 0) odd--;
    }
    awards.add(PotAward(
      potIndex: i,
      amount: pot.amount,
      shares: shares,
      handValue: best,
    ));
  }
  return awards;
}
