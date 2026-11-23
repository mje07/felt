# Felt

A clean, Apple-inspired No-Limit Texas Hold'em table for **Windows and Linux**.
Play a cash game against AI opponents with distinct styles. Built with Flutter, so it ships native desktop binaries with no Electron or webview.

## Layout

| Path | What |
| --- | --- |
| `packages/poker_engine/` | Pure-Dart engine: cards, shuffle, 7-card evaluator, betting rules, side pots, equity, bots, hand history. No Flutter imports. |
| `lib/app/` | Theme tokens, persisted settings, hand-history store, and `GameController`, which runs the hand loop and replays engine events so the UI can animate them. |
| `lib/widgets/` | Vector playing cards, chips, seats, table geometry, action bar. |
| `lib/screens/` | Lobby, table, settings and history panels. |
| `test_screenshots/` | Renders the real UI to PNG for visual review. |

## Engine rules

- Fisher–Yates shuffle over `Random.secure()`, with a burn card before each street.
- Heads-up: the button posts the small blind, acts first preflop and last postflop.
- Min-raise is the size of the last *full* raise. A short all-in raise does not reopen betting, but several short all-ins that add up to a full raise do.
- The uncalled part of a bet goes back to the bettor. When nobody can bet any more, the board runs out automatically.
- Side pots are built in layers from each player's contribution. Folded chips stay in the pot, and odd chips go to the first winner left of the button.
- Chips are conserved across every action (asserted in tests).

## Bots

`HeuristicBot` decides preflop from a 169-hand equity chart (`tool/gen_preflop.dart`) adjusted for position. Postflop it runs a Monte Carlo equity estimate against opponent ranges narrowed by their preflop actions, then compares that with pot odds. Each personality (Rock, Shark, Maverick, Station, Wildcard) has its own looseness, aggression, bluffing and stickiness. Skill level controls the sample count and the error rate. Postflop decisions run in a background isolate.

## Develop

```sh
flutter pub get
flutter run -d windows        # or: -d linux

# engine
cd packages/poker_engine
dart test                                   # fast suite
dart test --run-skipped -t slow             # exhaustive 133,784,560-hand evaluator check
dart run tool/simulate.dart --hands 100000  # bot-vs-bot soak test

# app
flutter test
flutter test test_screenshots --dart-define=OUT=build/screenshots
```

Windows needs Visual Studio (or Build Tools) with the *Desktop development with C++* workload, plus **Developer Mode** turned on (plugins need symlinks).
Linux needs `clang cmake ninja-build pkg-config libgtk-3-dev`.

## Keyboard

`F` fold · `C` check/call · `R` bet/raise · `↑`/`↓` change bet size · `Space` deal next hand

Fonts: Inter (SIL OFL, `assets/fonts/Inter-LICENSE.txt`).
