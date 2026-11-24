# Felt

A clean, Apple-inspired No-Limit Texas Hold'em table for **Windows and Linux**.
Website: https://mje07.github.io/felt/
Play cash games, Sit & Gos and multi-table tournaments against adaptive AI opponents, or host a home game for friends. Learn with lessons, a daily plan and a career mode; study spots with a built-in game-theory solver; and analyse your real online hands. Built with Flutter, so it ships native desktop binaries with no Electron or webview.

## Layout

| Path | What |
| --- | --- |
| `packages/poker_engine/` | Pure-Dart engine: cards, shuffle, 7-card evaluator, betting rules, side pots, equity, bots, hand history. No Flutter imports. |
| `lib/app/` | Theme tokens, persisted settings, hand-history store, and `GameController`, which runs the hand loop and replays engine events so the UI can animate them. |
| `lib/widgets/` | Vector playing cards, chips, seats, table geometry, action bar. |
| `lib/screens/` | Lobby, table, settings and history panels. |
| `lib/net/` | Home games: the protocol, host, client, LAN discovery and the relay link. |
| `lib/learn/` | Lesson content for the learning path. |
| `server/relay/` | The invite-code relay server (standalone Dart, with a Dockerfile; `render.yaml` deploys it free on Render). |
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


## Multi-table tournaments

Fields of 18 to 180 players at 9-handed tables, from a free daily freeroll to The Big One (1,000,000 buy-in). Each event has its own speed, starting stack and, for the big ones, a guaranteed prize pool.
- **Tables:** your table is played out hand by hand. The others are simulated with the same bots and rules, on the same blind clock.
- **Balancing:** after each hand, players move from the biggest table to the smallest until sizes are within one, and tables break when the others can absorb them. The final table forms at 9.
- **Dead button:** the big blind always moves forward one seat, so nobody skips or pays it twice when players bust (TDA rules).
- **Payouts:** about 15% of the field is paid, on a decreasing curve.
- **At the table:** the header shows your level, blinds, rank and the average stack, and a field panel lists chip leaders and the payout ladder. When you bust, the rest is simulated so the results name the winner.

## Learning path

- **Lessons:** 24 lessons in 6 units, from pot odds to ICM and hand reading. Each ends with questions, and figures are drawn with the real cards and range grids. `test/lessons_test.dart` checks every factual claim against the engine.
- **Skill ratings:** an Elo-style rating for each of 7 skills, updated by lesson questions, drills, Spot Trainer decisions and graded hands at the table.
- **Today's plan:** up to four activities a day, mixing spaced-repetition reviews (SM-2), the next lesson, your biggest leak and your weakest skill.
- **Career mode:** a separate bankroll that starts at micro stakes. Promotion through 6 stages needs both chips and skill ratings, and ends at The Big One.
- **Achievements:** 26 of them.

## Play with friends

One player hosts. Their Felt deals and runs the game with the real engine, and friends play from their own PCs.
- **Joining:** games on the same network appear in "Join a game" (UDP broadcast on port 47111). Anyone can join by address and port (TCP 47110), for example over port forwarding or a VPN such as Tailscale. Friends anywhere can join with a 6-letter invite code.
- **Fair by design:** each player is only ever sent their own hole cards, and other hands only when they're shown down. Friends send intended actions, which the host checks with the rules engine.
- **Coach included:** each friend's Felt rebuilds the hand from the host's messages, so their coach grades their own decisions and the hands are saved to their own history.
- **Games:** cash (free rebuys) or a Sit & Go, with bots in empty seats if you like (a Sit & Go always fills them), and a 15–60 second action timer (check if possible, otherwise fold). If a friend drops, they can reconnect to the same seat.
- **Play chips only:** home games never touch your bankroll.

**Invite codes** go through a small relay in `server/relay/`. Felt uses one at `felt-relay.onrender.com` by default; to run your own (free and 24/7 on Render with the included `render.yaml`, see [its README](server/relay/README.md)), put its address in Play with friends → Invite-code server. The relay only forwards messages and stores nothing, but it does carry the traffic, hole cards included, so use one you trust.

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

## Study tools

**Solver** (`solver/solver.dart`) is a heads-up postflop game-theory solver that runs on your own computer.
- **How it works:** vectorised Discounted CFR over whole ranges, with card-removal-correct fold and showdown terminals. It computes best response and exploitability, and per-hand EV.
- **Sizes:** flop ⅓ and ¾ pot, turn ⅔, river ½ and pot, plus one raise and all-in when shallow.
- **Speed (compiled):** about 20 ms for the river, 14 s for the turn, and 1.5 min for the flop to reach under 1% of the pot exploitable.
- **Flop solves** model a spread of 8 turn and 6 river cards.
- **Verification:** `test/solver_test.dart` checks it against the analytic nuts-or-air river game: bluff 9.4%, call 50%.
- **Benchmark:** `tool/solver_bench.dart`.

What uses the solver:
- **Study** solves preset preflop lines on any board. You can browse the tree with every hand split by the solver's action mix, and see each hand's EV. Solves are cached on disk.
- **The coach** solves heads-up river decisions exactly and grades them by the EV given up. If the solver plays your action at least 10% of the time, it counts as sound.
- **Spot Trainer** plays whole hands against an opponent who follows the solver. Every decision is graded, and the next spot is solved in the background while you play.

**Equity Lab** (`equity_lab.dart`) shows range-against-range equity for 2–4 ranges.
- Heads-up equity on the flop, turn and river is exact, enumerated with card removal and checked against brute force. Preflop and multiway equity is sampled.
- It has a Flopzilla-style breakdown of made hands and draws, a weight brush, presets and a range notation box.

**Your real hands**
- **Import:** PokerStars and GGPoker hand histories, cash and tournaments, via `import/hand_import.dart`. Each hand is replayed through the rules engine. Results, including rake and mucked hands, come from the history's own text. Unsupported hands (straddles, run-it-twice) are skipped with a reason. Every decision is graded as hands import.
- **Export:** any hands in PokerStars format, via `import/hand_export.dart`.
- **Replayer:** step through a hand with the arrow keys, with coach comments and your equity by street.
- **Leak finder:** ranks recurring mistakes by bb/100 and links each one to the matching trainer.

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
dart compile exe tool/solver_bench.dart -o build/solver_bench.exe  # solver timings

# relay
cd ../../server/relay && dart test

# app (from the repo root)
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
- updates an existing install in place (used by the app's automatic updates)

The installer isn't code-signed, so SmartScreen shows "Windows protected your PC" the first time (More info → Run anyway). A code-signing certificate removes that.
The app icon comes from `tool/icon/` (`flutter test tool/icon/render_icon_test.dart`, then `dart tool/icon/make_ico.dart`).

### Updates

`lib/app/updater.dart` asks GitHub for the latest release when Felt starts, then every 6 hours. It sends nothing about the player or their games, and it can be turned off in Settings → Updates. Apart from this, Felt only uses the network when you host or join a game with friends.

- **Windows, installed with Setup.exe:** the new installer downloads in the background. It's only used if it comes from this repository's releases and its SHA-256 matches the digest GitHub publishes for it, and it's checked again before it runs.
  - It installs silently the next time Felt starts, or straight away with "Restart to update".
  - The updater passes `/RELAUNCH=1`, so the new version starts afterwards. Ordinary silent installs don't launch Felt.
- **Linux, or development builds:** Felt shows that a new version is available and links to the release.

To publish an update:
1. Bump `version:` in `pubspec.yaml` and `appVersion` in `lib/app/version.dart`. The build script and a test check that the two match.
2. Build the installer.
3. Attach `Felt-Setup-<version>.exe` to a GitHub release tagged `v<version>`.

Windows needs Visual Studio (or Build Tools) with the *Desktop development with C++* workload, plus **Developer Mode** turned on (plugins need symlinks).
Linux needs `clang cmake ninja-build pkg-config libgtk-3-dev`.

## Keyboard

`F` fold · `C` check/call · `R` bet/raise · `↑`/`↓` change bet size · `Space` deal next hand

Fonts: Inter (SIL OFL, `assets/fonts/Inter-LICENSE.txt`).
