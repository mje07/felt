/// Independent Chip Model (Malmuth–Harville): each player's expected share of
/// the prize pool given current stacks.
///
/// The chance a player finishes first is their share of the chips; given who
/// finished first, the rest of the places are decided the same way among
/// the remaining players. Players with no chips get nothing. Memoised over
/// subsets of remaining players, so it is exact and fast for a single table.
List<double> icmEquities(List<int> stacks, List<num> payouts) {
  final n = stacks.length;
  if (n > 16) throw ArgumentError('ICM supports at most 16 players');
  final alive = [for (var i = 0; i < n; i++) if (stacks[i] > 0) i];
  final out = List<double>.filled(n, 0);
  if (alive.isEmpty) return out;
  final pay = [for (var k = 0; k < alive.length; k++) k < payouts.length ? payouts[k].toDouble() : 0.0];

  final memo = <int, List<double>>{};

  // Expected winnings from place `depth` downwards for players in `mask`.
  List<double> solve(int mask, int depth) {
    final cached = memo[mask];
    if (cached != null) return cached;
    final res = List<double>.filled(n, 0);
    if (depth >= pay.length || mask == 0) return memo[mask] = res;
    var total = 0;
    for (final i in alive) {
      if (mask & (1 << i) != 0) total += stacks[i];
    }
    for (final j in alive) {
      if (mask & (1 << j) == 0) continue;
      final pj = stacks[j] / total;
      res[j] += pj * pay[depth];
      final rest = solve(mask & ~(1 << j), depth + 1);
      for (final i in alive) {
        if (i != j && mask & (1 << i) != 0) res[i] += pj * rest[i];
      }
    }
    return memo[mask] = res;
  }

  var full = 0;
  for (final i in alive) {
    full |= 1 << i;
  }
  final res = solve(full, 0);
  for (final i in alive) {
    out[i] = res[i];
  }
  return out;
}
