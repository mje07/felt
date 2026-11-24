# Felt

A clean, Apple-inspired No-Limit Texas Hold'em table for **Windows and Linux**.
Website: https://mje07.github.io/felt/
Play a cash game against AI opponents with distinct styles. Built with Flutter, so it ships native desktop binaries with no Electron or webview.

## Layout

| Path | What |
| --- | --- |
| `packages/poker_engine/` | Pure-Dart engine: cards, shuffle, 7-card evaluator, betting rules, side pots, equity, bots, hand history. No Flutter imports. |
| `lib/app/` | Theme tokens, persisted settings, hand-history store, and `GameController`, which runs the hand loop and replays engine events so the UI can animate them. |
| `lib/widgets/` | Vector playing cards, chips, seats, table geometry, action bar. |
| `lib/screens/` | Lobby, table, settings and history panels. |
| `test_screenshots/` | Renders the real UI to PNG for visual review. |
| `tool/gen_sounds.dart` | Synthesizes the sound effects in `assets/sounds/` (procedural, so there are no sample licences). |

## Engine rules

- Fisher–Yates shuffle over `Random.secure()`, with a burn card before each street.
- Heads-up: the button posts the small blind, acts first preflop and last postflop.
- Min-raise is the size of the last *full* raise. A short all-in raise does not reopen betting, but several short all-ins that add up to a full raise do.
- The uncalled part of a bet goes back to the bettor. When nobody can bet any more, the board runs out automatically.
- Side pots are built in layers from each player's contribution. Folded chips stay in the pot, and odd chips go to the first winner left of the button.
- Chips are conserved across every action (asserted in tests).

## Sit & Go tournaments

Single-table tournaments for 2–9 players with a buy-in and prizes, either winner-takes-all or the top places (65/35, or 50/30/20 with 7+ players). Blinds rise every 5, 8 or 12 hands (Hyper, Turbo or Regular), with big-blind antes from 100/200. Starting stacks are 1,000, 1,500 or 3,000.
Players who bust in the same hand are placed by their stack at the start of that hand. When you're knocked out, the rest of the tournament is simulated in the background so the results screen can name the winner.

**Bankroll:** one balance covers both modes. Tournament buy-ins and cash-game buy-ins and rebuys come out of it; prizes and cash-outs go back in. Chips left on a cash table are returned on the next launch if the app closes mid-session. When you're running low you can top back up to 10,000.

**Tournament coaching:**
- At 15 big blinds or fewer, unopened spots are graded against push/fold charts.
- Calling an all-in is graded on chip outcomes in cash games and on prize equity (ICM, `icm.dart`) in tournaments. Near the bubble, a call that wins chips on average can still lose prize money, and the coach says so.

## Statistics

The engine's `computeStats` turns saved hand histories into the standard stats: VPIP, PFR, 3-bet, aggression factor, c-bet, fold to c-bet, WTSD, W$SD and WWSF. It also breaks your results down by position and by starting hand, and builds a running results line.
`profileFor` places you on a tight/loose × passive/aggressive map, names your archetype (Nit, Rock, Shark, Maverick, Maniac or Calling Station) and writes coaching notes from your numbers.

## Sound

`tool/gen_sounds.dart` synthesizes the effects in `assets/sounds/`. They're procedural, so there are no sample licences to deal with. Playback goes through `flutter_soloud`, which bundles its own audio engine (miniaudio).

## Bots

`HeuristicBot` decides preflop from a 169-hand equity chart (`tool/gen_preflop.dart`), adjusted for position and the number of players left in the hand.
Postflop it runs a Monte Carlo equity estimate against each opponent's range, then weighs it against pot odds, position, board texture and its own betting line. Each personality (Rock, Shark, Maverick, Station, Wildcard) has its own looseness, aggression, bluffing and stickiness. Skill level controls the sample count and the error rate.

**Ranges** (`range_model.dart`) are explicit lists of two-card combos, sampled exactly.
- Preflop action sets the starting range.
- Every postflop action narrows it against the board as it stood at the time: a bet keeps the strongest made hands and draws, plus a bluff share; a call drops the nuts and the junk.
- The coach uses the same model, so its equity numbers reflect what opponents actually hold on that board.

**Reads** (`bots/reads.dart`) build up over a session for every player, you included: how often they play and raise preflop, bet postflop and fold to bets.
- Ranges widen for players who raise and bet a lot.
- The adaptive styles (Shark and Maverick) also defend wider against loose raisers, bluff players who fold, and value-bet players who call.
- Rock, Station and Wildcard are fixed archetypes, which keeps them exploitable.

**Sit & Go play:** at 15 big blinds or fewer, bots open-shove and call all-ins from the same push/fold charts the coach uses, shifted by personality. Expert bots check calls near the bubble with ICM.

**Measuring strength:** `tool/arena.dart` plays duplicate-format matches, where each deal is replayed with every seat rotation and every hand starts at the same stack. It reports bb/100 with a 95% confidence interval. `test/bot_strength_test.dart` (slow) guards the ordering.
## Develop

```sh
flutter pub get
flutter run -d windows        # or: -d linux

# engine
cd packages/poker_engine
dart test                                   # fast suite
dart test --run-skipped -t slow             # exhaustive 133,784,560-hand evaluator check
dart run tool/simulate.dart --hands 100000  # bot-vs-bot soak test (chip conservation)
dart run tool/arena.dart --deals 20000 --difficulty expert  # bot strength, duplicate format
dart test --run-skipped -t slow test/bot_strength_test.dart

# app
flutter test
flutter test test_screenshots --dart-define=OUT=build/screenshots
```

### Windows installer

```powershell
powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1
```

This builds the release and packages `build\installer\Felt-Setup-<version>.exe` with Inno Setup 6 (`winget install JRSoftware.InnoSetup`). The version comes from `pubspec.yaml`.
The installer:
- installs per-user by default, with no admin prompt (all users is an option in the wizard)
- adds a Start-menu shortcut, and an optional desktop shortcut
- registers an uninstaller in Settings → Apps
- bundles the Visual C++ runtime, so it works on a clean PC
- leaves your saved hands, stats and bankroll in place when you uninstall

The installer isn't code-signed, so SmartScreen shows "Windows protected your PC" the first time (More info → Run anyway). A code-signing certificate removes that.
The app icon comes from `tool/icon/` (`flutter test tool/icon/render_icon_test.dart`, then `dart tool/icon/make_ico.dart`).

Windows needs Visual Studio (or Build Tools) with the *Desktop development with C++* workload, plus **Developer Mode** turned on (plugins need symlinks).
Linux needs `clang cmake ninja-build pkg-config libgtk-3-dev`.

## Keyboard

`F` fold · `C` check/call · `R` bet/raise · `↑`/`↓` change bet size · `Space` deal next hand

Fonts: Inter (SIL OFL, `assets/fonts/Inter-LICENSE.txt`).
