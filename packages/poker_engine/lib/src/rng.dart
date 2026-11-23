import 'dart:math';

/// Cryptographically secure RNG for real play; pass a seeded [Random] in tests.
Random secureRandom() => Random.secure();

/// In-place unbiased Fisher–Yates shuffle.
void shuffle<T>(List<T> list, Random rng) {
  for (var i = list.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final tmp = list[i];
    list[i] = list[j];
    list[j] = tmp;
  }
}
