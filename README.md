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
- Keeps runtime settings per game (FPS target, docked mode, render scale, MetalFX spatial upscale, Metal HUD, language, rumble, fullscreen) and writes nxnative's `env.txt` before launch.
- Shows storage usage and can delete only caches and logs; apps and sources require explicit action. **Remove Sources & Build Cache** deletes the original NSP/XCI files and the app-owned workspace for one game, keeping the installed app, saves and logs; sources can be attached again later.
- Checks the upstream `seedds/nxnative` commit history on demand in **Settings → Engine**. The check is read-only: it contacts the GitHub API, shows new commits and a compare link, never fetches, merges, checks out or re-pins the engine. The engine gate keeps blocking builds until an update is manually re-pinned and re-tested.
- Includes synthesized UI tones, controller prompts, and keyboard shortcuts. The theme and symbols are original; no Nintendo assets are included.

## Requirements

- Apple-silicon Mac, macOS 13 or newer.
- Xcode 27.1 or newer (with the matching Metal toolchain) on this machine.
- .NET 10 runtime (`/usr/local/share/dotnet`).
- Homebrew `xcodegen`, `zstd`, `spirv-cross`, `glslang`.
- The nxnative checkout at `~/nxnative`, pinned to `4f24ce6489a28aa84575e38711f3a318d7ab2a4f`, with its Python venv containing `lz4`, `capstone`, `fontTools`, `backports.zstd` and the other engine dependencies.

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

Engine upgrades are manual and never follow `main`. Before changing the pin, review the commits and decide what belongs in the UI and what stays backend-only. The checklist and dated notes are in [`docs/upstream-upgrades/`](docs/upstream-upgrades/); the current pin is `4f24ce6489a28aa84575e38711f3a318d7ab2a4f`.

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

NX Library is MIT licensed. `NOTICE` retains the MIT copyrights for nxnative and the [rennan101/nxnative_Launcher](https://github.com/rennan101/nxnative_Launcher) GUI baseline; NX2Apple was a reference only and no code from it was copied. The app icon and tones are original.

No games, keys, Nintendo logos, fonts, sounds, or other Nintendo assets are included. NX Library is not affiliated with, endorsed by, or sponsored by Nintendo.

## Known limitations

- The Breath of the Wild sources were removed from this Mac. Its imported app remains playable, but a BotW rebuild is blocked until the XCI base, update 1.9.0 and DLC are restored and attached.
- Super Mario Odyssey 1.4.1 builds with engine `4f24ce6` (27,984 shaders and 32,864 pipeline pairs) and reaches the controller screen; gameplay beyond that is not yet verified.
- No DMG, no iOS/IPA output, no online compatibility database and no automatic engine updates. The upstream changelog check is manual and read-only; only the commit hash is sent to `api.github.com`.
- The engine checkout is never modified; nxnative upgrades are manual and re-pin the engine commit in `AppViewModel.pinnedEngineCommit`.
- A detached-sources game shows no source badge over its tile and keeps its artwork; the detail card shows **Sources detached** with an info tooltip and **Attach Sources…** next to Rebuild.
