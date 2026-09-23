# Chpok! (iOS)

A native iOS port of the classic bubble-shooter game at [bubbleshooter.com](https://www.bubbleshooter.com/): the original's engine logic (deployed in an iframe from `https://cdn.bubbleshooter.com/games/bubbleshooter-game/`) is ported 1:1 to a deterministic, unit-tested Swift core, driving a SwiftUI + SpriteKit front end. The site was the starting point only; the game's look and feel now evolve according to the app owner's own requirements rather than mirroring the site.

## Requirements

- Xcode 26 (developed/tested with Xcode 26.6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — generates `BubbleShooter.xcodeproj` from `project.yml`; the generated project is not checked into git
- iOS 17+ simulator or device

## Commands

The project is built, tested and run through the scripts in `scripts/`. Each one is self-contained (`cd`s to the repo root itself) and targets a fixed simulator: iPhone 17 Pro, bundle id `com.dimazhuravlev.BubbleShooter`.

| Script | What it does |
|---|---|
| `scripts/build.sh` | Regenerates the Xcode project (`xcodegen generate`) and builds the `BubbleShooter` app for the simulator (Debug). Log: `build/xcodebuild-build.log`. |
| `scripts/run-sim.sh [path-to-.app]` | Boots the simulator, opens `Simulator.app`, installs and launches the app, and saves a screenshot to `build/screenshots/`. Defaults to the app produced by `build.sh`. |
| `scripts/test-core.sh` | Runs the core engine's unit tests (`swift test` in `Packages/BubbleShooterCore`). |
| `scripts/test-ui.sh` | Builds and runs the UI test bundle (`BubbleShooterUITests`) on the simulator via `xcodebuild test`. Log: `build/xcodebuild-test.log`. |

Run them in that rough order (`test-core` → `build` → `test-ui` → `run-sim`) for a full check of a change.

### Installing on a physical iPhone

Simulator builds are intentionally unsigned. To install on a real device: run `xcodegen generate` (or any script above, which does this for you), open the generated `BubbleShooter.xcodeproj` in Xcode, select your iPhone as the run destination, and press **Run**. Automatic signing (`DEVELOPMENT_TEAM = Z55ZV5538M`) provisions and signs the app; the first run may need you to trust the developer certificate on the device under Settings → General → VPN & Device Management.

## Architecture

- **`Packages/BubbleShooterCore`** — a platform-independent Swift package with the game engine (no UIKit/SwiftUI/SpriteKit imports). `GameEngine` advances state on a fixed **15 ms** tick (`GameConsts.tickMs`), driven by a single `TimerQueue` that replaces the original's one-Phaser-timer-per-bubble scheme with an equivalent deterministic global tick. State changes are reported as a stream of `GameEvent`s (score changed, bubble removed, game over, …) for the app layer to consume. `GameEngine` can be created fresh or restored from a `GameSnapshot`, and is covered by its own test target, `BubbleShooterCoreTests`.
- **`App`** — the iOS app. `GameViewModel` (`ObservableObject`) owns the `GameEngine`/`GameScene` pair and republishes their state to SwiftUI views (`RootView`, `HUDView`, `GameOverOverlay`). `GameScene` (SpriteKit) renders the board and turns taps into shots. `GameSaveStore` persists the single in-progress match as JSON under Application Support; `GameViewModel` loads it on launch and saves on backgrounding/turn resolution.
- **`UITests`** — `SmokeUITests` (app launches), `GameplayUITests` (tap-to-fire, Restart resets the board, gameplay screenshot), `PersistenceUITests` (save/resume across a relaunch).

## Game rules and constants (from the original)

- Board: **17 columns × 9 starting rows**, **6** bubble colors.
- A shot fires on tap — matching the original's pointer-*down*-to-fire behavior (not pointer-up).
- A landing cluster of same-colored, ceiling-connected bubbles pops once it reaches **3+** bubbles.
- Score per popped bubble: **`10 · ceil(k/3)`**, where `k` is the bubble's 1-based position within the cluster (10, 10, 10, 20, 20, 20, 30, …).
- Bubbles left disconnected from the ceiling after a pop ("hanging") are swept separately and score a flat **100** each.
- **5** starting lives; each miss costs one life; once lives reach 0, a miss instead adds **`1 + (colors currently absent from the board)`** new row(s) at the top.
- Winning (board fully cleared) doubles the score: final = `score + bonus`, with `bonus = score`.

See `docs/original-game-logic.md` for the full derivation — every rule, timer, coordinate formula and original quirk, each backed by a line reference into the original's JS.

## Deliberate deviations from the original

- **Loss boundary is measured from the cannon**, not the original's hardcoded `boardCoordY > 14 && pixelY > 470` (a fixed offset from the top of its 800×600 canvas). The port derives the equivalent thresholds from the cannon's own Y position instead, so the loss line scales with the on-screen layout rather than being pixel-fixed — a conscious choice made for the full-screen portrait layout below.
- **Layout**: portrait only; the board is stretched to fill the screen beneath the HUD header, instead of the original's fixed 800×600 desktop canvas.
- **Tap = shoot**: chosen deliberately to mirror the original's pointer-down semantics 1:1, even though many touch games fire on release instead.
- Board uses true hexagonal packing: row height is 32·√3/2 ≈ 27.71 instead of the original's 32, so all six neighbours of a cell are exactly one bubble diameter apart and the rows have no gaps between them.
- Bubbles are drawn 30 px wide on a 32 px grid with no stroke, leaving an even 2 px gap; the app is rendered on a pure black background.
- Rows alternate 17 and 16 bubbles so both board edges are straight; the parity reference flips with every dropped row, so the board keeps its silhouette and no longer shifts sideways.

## Not ported

- Sound.
- The original's dev cheats (Space/Q hotkeys to change the ready bubble's color or drop the last row).
- Dead/unreachable code identified in the original while reading it (unused constants, the unreachable "add high score" name-entry flow, `banBubbleFromShooting`, the always-zero recoil offset, etc. — catalogued in `docs/original-game-logic.md`).
- The Top 10 high-score screen.
- Any menu: the app opens straight into the board. Only the current in-progress match is ever persisted (no history), Restart acts immediately without a confirmation prompt, and winning starts a brand-new match from scratch.
