# NX Library

A personal, native macOS front-end for [nxnative](https://github.com/seedds/nxnative). It builds your own Switch dumps into self-contained Mac apps and launches them from a console-style library. No emulator is involved.

**Status:** v0.1.0, implemented and verified on this Apple-silicon Mac. The engine is used in place; the front-end never patches it. Design and plan are in [`docs/superpowers/`](docs/superpowers/).

## What it does

- Imports existing nxnative Mac apps (including the current 18.17 GB Breath of the Wild build) and keeps Play available when sources are missing.
- Imports `prod.keys` once into Application Support with mode `0600`; the original file is untouched and key values are never shown or logged.
- Detects NSP/XCI/NSZ/XCZ base, update and DLC files, including files reached through symlinks, and groups them by title ID.
- Creates a symlinked workspace or uses a source folder in place; sources are never copied into the library.
- Builds a Mac `.app` in `~/Applications` through the pinned nxnative CLI with JSON progress, stages, ETA, a live log and cancellation.
- Replaces the previous app atomically; a failed or cancelled build leaves it untouched.
- Stores the library in `~/Library/Application Support/NXLibrary/library.json` with a backup copy.
- Keeps runtime settings per game (FPS target, docked mode, render scale, MetalFX spatial upscale, Metal HUD, language, rumble, fullscreen). It reads the app's `launcher.json` to show only the settings the game supports, writes nxnative's `env.txt`, and passes the chosen values in the launch environment as well.
- Shows storage usage and can delete only caches and logs; apps and sources require explicit action. **Remove Sources & Build Cache** deletes the original NSP/XCI files and the app-owned workspace for one game, keeping the installed app, saves and logs; sources can be attached again later.
- Checks the upstream `seedds/nxnative` commit history on demand in **Settings → Engine**. The check is read-only: it contacts the GitHub API, shows new commits and a compare link, never fetches, merges, checks out or re-pins the engine. The engine gate keeps blocking builds until an update is manually re-pinned and re-tested.
- Includes synthesized UI tones, controller prompts, and keyboard shortcuts. The theme and symbols are original; no Nintendo assets are included.

## Interface

NX Library follows the [Selene](https://github.com/mattxslv/Selene) Playnite theme (MIT) as closely as a SwiftUI app can: the same 1920×1080 canvas units, palettes, Material Icons glyphs, hint rows and motion. Only the button prompts differ: they show Switch, Xbox or PlayStation names to match the connected controller. It does not include Sony or Nintendo branding, fonts, sounds or artwork.

- **Spotlight:** Selene's home row of square tiles with cards (Collection, Surprise me, Activity, Add game), filter pill, info block, screenshot strip and a full-screen screenshot viewer. Hold A to lift and move a tile.
- **Collection:** a single row of covers over the selected game's art.
- **Details:** banded page (play row, Build & Sources, screenshots, More like this) with Selene's scrim masks.
- **Game options:** Selene's 1040u panel with runtime settings, favorite, hide and move, and confirm dialogs.
- **Control center:** Menu/Start or `⌘K` opens Selene's menu with Resume and Close Game for a running game, and Power (quit, relaunch).
- **Launch screen:** on Play, the game's art and logo (per Settings → Games) stay up until the game's window appears.
- **Find a game:** hold View or press `⌘F` for a search over the whole library.
- **Settings:** Selene's two-column layout with Search and Changed, then Start-up, Navigation, Spotlight, Sound & music, Look, Games, Controllers, Library, Storage, Engine and About. Value rows step with Left/Right; X resets a group.
- **Look:** 23 palettes, wallpaper per theme or none (Fill/Fit/Stretch) and an optional animated backdrop.
- **Sounds:** Selene's cues. Four MIT cues ship with the app; **Settings → Sound & music → Import sounds and wallpapers from Selene** copies the rest from a Selene folder you own into Application Support.
- **Intro:** the app mark with the boot cue on a cold launch (Settings → Start-up). Any input skips it.
- **Add Game, Setup, Console:** the import/build flow, first-run checklist and log share the canvas units. Console's **Copy log** copies the last 200 log lines and the latest build log's tail.
- **Controller and keyboard:** A/Return confirms or plays, B/Esc goes back, LB/RB switch filters, View/Tab flips Spotlight and Collection, Menu/Start opens the control center, holding Menu or `⌘,` opens Settings.
- **Artwork:** Store descriptions and artwork are cached locally under Application Support. Nothing is written to the repository.

The design specification and implementation plan live in [`docs/superpowers/`](docs/superpowers/). Visual acceptance is a manual pass on this Mac; the automated suite covers the data and build layers.

## Requirements

- Apple-silicon Mac, macOS 13 or newer.
- Xcode 27.1 or newer (with the matching Metal toolchain) on this machine.
- .NET 10 runtime (`/usr/local/share/dotnet`).
- Homebrew `xcodegen`, `zstd`, `spirv-cross`, `glslang`.
- The nxnative checkout at `~/nxnative`, pinned to `ee369f09984f23adbe003f55e94be5d81cd8c0e6`, with a Python 3.14 venv (3.12 or newer is required) containing `lz4`, `capstone` and `fontTools`; Python 3.14 uses the standard-library zstd.

## Build and run

```bash
cd ~/Developer/NXLibrary
bash scripts/build_app.sh
open "$HOME/Applications/NXLibrary.app"
```

The app is ad-hoc signed and installed as `NXLibrary.app` (bundle ID `local.nxlibrary`). Set `NX_BUILD_CONFIG=debug` to package the debug binary:

```bash
NX_BUILD_CONFIG=debug bash scripts/build_app.sh /tmp/NXLibrary-Debug.app
/tmp/NXLibrary-Debug.app/Contents/MacOS/NXLibrary --preview-build   # DEBUG only
```

`--show-setup` (DEBUG only) reopens the first-run sheet.

## First run

Setup checks the nxnative checkout, build tools, `prod.keys`, the app library folder (`~/Applications`) and existing builds. Imported apps are playable immediately; their rebuilds stay disabled until sources are located.

## Adding a game

1. Open **Add Game**, drop a folder or file, or use **Choose Folder**.
2. Review the detected base/update/DLC sources. The base is locked; the newest update and non-empty DLC are selected by default.
3. Review the destination and disk estimate (twice the selected sources plus 10 GB).
4. Choose **Add to Library** or **Add & Build**.

Builds go to `~/Applications/<game>.app`. Sources stay where they are; a staged workspace uses symlinks.

## Compatibility gate

New builds are blocked unless the installed engine commit, working tree, Metal compiler and nxnative CLI match the certified combination. This Mac has Xcode 27.1 and Metal `32023.921`, matching the engine lock. The gate is visible under **Settings → Engine**.

An explicit **Build anyway with an untested toolchain** override exists. It requires confirmation, persists in `UserDefaults`, passes `--allow-other-metal` to the engine, and records every build made under it as **untested**. Corrupted graphics are a documented upstream risk; the existing BotW build is left untouched.

## Updating the engine

Engine upgrades are manual and never follow `main`. Before changing the pin, review the commits and decide what belongs in the UI and what stays backend-only. The checklist and dated notes are in [`docs/upstream-upgrades/`](docs/upstream-upgrades/); the current pin is `ee369f09984f23adbe003f55e94be5d81cd8c0e6`.

## Tests

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

The suite covers models and persistence, source parsing (including a regression for `*.cnmt.nca` vs `*.cnmt.xml`), symlink workspaces, key import/permissions, the compatibility gate, build-command construction, atomic install, process cancellation, launch environment writing, import, storage, and game playability.

## Repository layout

- `Sources/NXLibraryCore/` — models, library store, source catalog, key store, workspace, build/launch/import/storage/compatibility services.
- `Sources/NXLibrary/` — SwiftUI app, view model, views and theme.
- `Tests/NXLibraryCoreTests/` — core tests with synthetic PFS0 fixtures; no copyrighted game data.
- `Resources/` — original app icon and appearance variants.
- `scripts/build_app.sh` — release/debug app bundling and ad-hoc signing.
- `docs/superpowers/` — design spec and implementation plan.

## Licenses and attribution

NX Library is MIT licensed. `NOTICE` retains the MIT copyrights for nxnative and the [rennan101/nxnative_Launcher](https://github.com/rennan101/nxnative_Launcher) GUI baseline; NX2Apple was a reference only and no code from it was copied. The app icon is original.

Bundled media and their licenses are listed in `Resources/Selene/NOTICE.txt` and `NOTICE-palettes.txt`: Material Icons (Apache 2.0), Selene's four synthesized sounds (MIT), the Selene palettes (MIT) and five public-domain wallpapers. Other Selene sounds and wallpapers are never bundled; the import action copies them from the user's own checkout.

No games, keys, Nintendo logos, fonts, sounds, or other Nintendo assets are included. NX Library is not affiliated with, endorsed by, or sponsored by Nintendo.

## Known limitations

- The Breath of the Wild sources were removed from this Mac. Its imported app remains playable, but a BotW rebuild is blocked until the XCI base, update 1.9.0 and DLC are restored and attached.
- Super Mario Odyssey 1.4.1 builds with engine `4f24ce6` (27,984 shaders and 32,864 pipeline pairs) and reaches the controller screen; gameplay beyond that is not yet verified.
- Native 1440p/4K rendering is not supported. The window or fullscreen display sets output resolution; render scale is 50–100% and only changes the internal 3D resolution. MetalFX improves the upscale. BotW supports the render-scale stub; the current SMO build does not, so its render-scale card is hidden.
- No DMG, no iOS/IPA output, no online compatibility database and no automatic engine updates. The upstream changelog check is manual and read-only; only the commit hash is sent to `api.github.com`.
- The engine checkout is never modified; nxnative upgrades are manual and re-pin the engine commit in `AppViewModel.pinnedEngineCommit`.
- A detached-sources game shows no source badge over its tile and keeps its artwork; the detail card shows **Sources detached** with an info tooltip and **Attach Sources…** next to Rebuild.
