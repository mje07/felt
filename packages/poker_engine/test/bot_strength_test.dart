@Tags(['slow'])
library;

import 'package:poker_engine/poker_engine.dart';
import 'package:test/test.dart';

// Bot strength regression, in duplicate format (see runArena). Slow; run with:
//   dart test --run-skipped -t slow test/bot_strength_test.dart
// For a full report: dart run tool/arena.dart --deals 20000 --difficulty expert
void main() {
  test('the Shark beats the Station and the Rock heads-up', () {
    for (final opp in [Personality.station, Personality.rock]) {
      final lines = runArena(
        lineup: [Personality.tag, opp],
        difficulty: Difficulty.expert,
        deals: 10000,
        seed: 21,
      );
      final shark = lines.firstWhere((l) => l.personality.id == 'tag');
      expect(shark.bbPer100, greaterThan(0), reason: 'vs ${opp.label}: $lines');
    }
  });

  test('at a full table the Station loses the most and the adaptive styles win', () {
    final lines = runArena(lineup: Personality.all, difficulty: Difficulty.expert, deals: 6000, seed: 22);
    expect(lines.last.personality.id, 'station', reason: '$lines');
    for (final id in ['tag', 'lag']) {
      expect(lines.firstWhere((l) => l.personality.id == id).bbPer100, greaterThan(0), reason: '$lines');
    }
  });
}
