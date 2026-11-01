# NX Library

A personal, native macOS front-end for [nxnative](https://github.com/seedds/nxnative). It builds your own Switch dumps into self-contained Mac apps and launches them from a console-style library. No emulator is involved.

**Status:** v0.1.0, implemented and verified on this Apple-silicon Mac. Current architecture and file responsibilities are documented in the [technical guide](docs/architecture.md) and [file catalog](docs/file-map.md). Dated designs and plans are in [`docs/superpowers/`](docs/superpowers/).

## What it does

- Imports existing nxnative Mac apps (including the current 18.17 GB Breath of the Wild build) and keeps Play available when sources are missing.
- Imports `prod.keys` once into Application Support with mode `0600`; the original file is untouched and key values are never shown or logged.
- Detects NSP/XCI/NSZ/XCZ base, update and DLC files, including files reached through symlinks, and groups them by title ID.
- Creates a symlinked workspace or uses a source folder in place; sources are never copied into the library.
- Builds a Mac `.app` in `~/Applications` through the pinned nxnative CLI with JSON progress, stages, ETA, a live log and cancellation.
- Installs validated game builds with an atomic swap, keeping the installed app at its normal path throughout replacement. Builds on another volume are prepared beside the destination first; interrupted installs can be retried safely. If only installation fails, the ready build is kept and a Selene dialog offers **Retry** or **Close**. Retry installs that build without running the porting again.
- Stores the library in `~/Library/Application Support/NXLibrary/library.json` with a backup copy.
- Keeps runtime settings per game (FPS target, docked mode, render scale, MetalFX spatial upscale, Metal HUD, language, rumble, fullscreen). It reads the app's `launcher.json` to show only the settings the game supports, writes nxnative's `env.txt`, and passes the chosen values in the launch environment as well.
- Shows storage usage and can delete only caches and logs; apps and sources require explicit action. **Remove Sources & Build Cache** deletes the original NSP/XCI files and the app-owned workspace for one game, keeping the installed app, saves and logs; sources can be attached again later.
- Checks the upstream `seedds/nxnative` commit history on demand in **Settings → Engine**. The check is read-only: it contacts the GitHub API, shows new commits and a compare link, never fetches, merges, checks out or re-pins the engine. The engine gate keeps blocking builds until an update is manually re-pinned and re-tested.
- Includes synthesized UI tones, controller prompts, and keyboard shortcuts. The theme and symbols are original; no Nintendo assets are included.

## Interface

NX Library follows the [Selene](https://github.com/mattxslv/Selene) Playnite theme (MIT) as closely as a SwiftUI app can: the same 1920×1080 canvas units, palettes, Material Icons glyphs, hint rows and motion. Only the button prompts differ: they show Apple's SF Symbols glyphs for the connected Switch, Xbox or PlayStation controller, as the controller itself reports them (System Settings remapping included; a generic controller gets Xbox's); on a Switch controller, confirm is the button printed A. With no controller they show the Mac keys instead. It does not include Sony or Nintendo branding, fonts, sounds or artwork.

- **Spotlight:** Selene's home row of square tiles (each game's own app icon) with cards (Collection, Surprise me, Activity, Add game), filter pill, info block with Play / Options / Favorite, screenshot strip and a full-screen screenshot viewer. Below the stats it is one page: genres, screenshots, description, Build & Sources with Your activity, More like this. Down glides the whole screen up as the row fades; the trackpad scrolls the page freely. Hold A to lift and move a tile.
- **Collection:** a single row of covers over the selected game's art.
- **Details:** banded page (Play / Options / Favorite, Build & Sources, screenshots, More like this) with Selene's scrim masks.
- **Game options:** Selene's 1040u panel with runtime settings, favorite, hide and move, and confirm dialogs.
- **Cheats:** Game Options → **Cheats** (the third row) installs a cheat file (drop it, or choose it) into the folder the game's engine reads, `~/Library/Application Support/nxnative/<title ID>/cheats/<build ID>.txt`, and switches each cheat and the master switch. A new file starts with every cheat off; changes apply at the next Play, and the in-game panel (⌘⇧C) shows the same files. Files are written only while the game is not running. An app built with an engine older than nxnative `ef9f9bb` shows **Rebuild**. The detail page shows CHEATS · On when at least one is on. Arrows, the wheel and the trackpad drive it; the pointer alone never moves the focus. Hidden games come back from **Settings → Games → Hidden games**.
- **Saves:** Game Options → **Saves**, directly below Cheats, manages local saves, verified backups, folder imports and restores. Import uses a centered From → To preview and shows **Imported successfully** for three seconds after verified completion. The same import path handles each game's own file structure. [Save actions and workflow](#save-backups-and-imports).
- **Control center:** Menu/Start or `⌘K` opens Selene's menu with Resume and Close Game for a running game, and Power (quit, relaunch).
- **Launch screen:** on Play, the game's art and logo (per Settings → Games) stay up until the game's window appears.
- **Find a game:** hold View or press `⌘F` for a search over the whole library.
- **Settings:** Selene's two-column layout with Search and Changed, then Start-up, Navigation, Spotlight, Sound & music, Look, Games, Controllers, Library, Storage, Engine and About. Value rows step with Left/Right; X resets a group.
- **Look:** 23 palettes, wallpaper per theme or none (Fill/Fit/Stretch), Wallpaper brightness (Like Selene's even 0.6, Bright on the right — the default, dim only under the text — or Bright) and an optional animated backdrop. Menu → Theme → background has two tabs, **Wallpapers** and **Live** (LB/RB or Q/E): your own pictures and looping videos (mp4, mov, m4v, played muted), online stills from **Wallhaven** (safe for work only) and **Danbooru** (general rating only), 16:9 and 2560 wide or more, and online live backgrounds from **MotionBGs** (4K and HD loops) and **Steam** (the Points Shop's animated profile backgrounds), browsed by category or search without leaving the app. A chosen online item is downloaded into `Application Support/NXLibrary/SeleneImports/Wallpapers/online/` (stills) or `live/` (videos) with its credit (uploader, artist or game, and page) in `credits.json`; X opens its page, Y removes it.
- **Sounds:** Selene's cues. Four MIT cues ship with the app; **Settings → Sound & music → Import sounds and wallpapers from Selene** copies the rest from a Selene folder you own into Application Support.
- **Intro:** the app mark with the boot cue on a cold launch (Settings → Start-up). Any input skips it.
- **Add game:** a Game options-style column over the blurred home, opening like Game options and the console, three steps (Choose, Review, Porting); Esc steps back or closes, and during a porting closes while the porting goes on.
- **Porting on the home:** the game being ported leads Spotlight's row. Its tile is black and white with a thin "k/n" step bar and the engine's step before the shaders, then colours from the bottom with one honest percentage (shaders 90%, the final stages the last 10%). The pills read Porting with the time left; a failed porting with no app shows a lock and Try again / Open log / Delete, and survives a relaunch.
- **Key check before porting:** the Review step reads the first kilobyte of each NCA in the selected NSP/NSZ files and checks it against your `prod.keys`. Keys too old for the game (with the firmware it needs) or a `header_key` that opens nothing disable **Add and port** before the engine starts; an XCI is noted as not checked. Only key names and counts are ever used, never values.
- **Explained failures:** a failed porting is recognised from the engine's own messages (Intel Python, shader translator, Command Line Tools selected, uncertified Metal compiler, shader regressions, damaged files, 32-bit games, keys, several games in a folder, disk space, a disconnected drive, iCloud folders, no game profile). The Porting step titles it, says what stopped it and offers one next step: **Port anyway** (shader regressions and damaged files only, once), Engine settings, Setup, Import prod.keys or Storage. Spotlight and Details show the reason under the pills, after a relaunch too.
- **Copy diagnostics:** a Markdown report for an issue (versions, engine pin and checkout, toolchain, setup, keys present, the last porting's command and log tail), from Settings → About, the Console and a failed Porting step. The home folder becomes `~`, key-like lines keep only the name, and no environment is included.
- **Notifications:** "<Game> is ready" or "<Game> did not port" only when NX Library is in the background, never for a cancel; clicking lands on the game or on the failure. Settings → Library → **Notify when a porting ends**.
- **Updates:** a release copy looks for a newer NX Library on GitHub at launch (at most once a day; Settings → Start-up → **Check for app updates**) and in Settings → About. Update downloads the release, checks its SHA-256 against GitHub's digest, its bundle ID, version and release marker, then swaps the app (the old one goes to the Trash) and relaunches. It waits for a porting or a running game. Builds from source never update themselves.
- **Setup, Console:** the first-run checklist and log share the canvas units. Console's **Copy log** copies the last 200 log lines and the latest build log's tail; **Copy diagnostics** copies the scrubbed report.
- **Controller and keyboard:** A/Return confirms or plays, B/Esc goes back, LB/RB switch filters, View/Tab flips Spotlight and Collection, Menu/Start opens the control center, holding Menu or `⌘,` opens Settings.
- **Artwork:** Store descriptions and artwork are cached locally under Application Support. Nothing is written to the repository. Change artwork offers GameTDB, Title DB and the Nintendo store, then every online source for a game with the same name (or an edition of it): Steam (transparent logo, cover, background, screenshots), the Xbox Store (poster, hero, screenshots, square icon), GOG (logo, covers, screenshots), Nintendo Europe (banner, square), TheGamesDB (clear logo, box front, fan art, screenshots), Wikidata and Wikimedia Commons logos, Nintendo fan wiki logos and Wallhaven wallpapers. Wikidata also links a game to its Steam page when the names differ. The automatic logo falls back to these sources in the same order.

The [technical guide](docs/architecture.md) describes the current implementation. Dated specifications and plans live in [`docs/superpowers/`](docs/superpowers/). The user performs interactive app and game checks. The automated suite covers the data, build and presentation-state layers.

## Requirements

- Apple-silicon Mac, macOS 13 or newer.
- Xcode 27.1 or newer, with the matching Metal toolchain.
- The .NET 10 SDK (the engine builds its extractor with `dotnet build`).
- The nxnative checkout at `~/nxnative`, pinned to `2716f78f01e90a9f9bbf0d09e7a798903525962f`. A checkout elsewhere can be chosen in Settings → Engine; NX Library remembers it while the folder exists.

Python 3.14 (with `capstone` 5, `lz4` and `fontTools`), `zstd` and `glslangValidator` ship inside the app. No Homebrew or pip is needed to use it. The Setup check installs the Metal toolchain, downloads Microsoft's .NET 10 SDK installer and clones the engine; Xcode itself comes from the App Store.

## Install

1. Download `NXLibrary-<version>.dmg` from the latest GitHub release, open it and drag **NX Library** to Applications. Later versions install from inside the app.
2. The app is ad-hoc signed, not notarized. On first open, macOS blocks it: open **System Settings → Privacy & Security** and choose **Open Anyway**.
3. The **Setup check** opens. It shows what is ready and what is missing: Xcode, the Metal compiler, the .NET 10 SDK, the engine, the bundled Python and tools, your `prod.keys` and the library folder. **Install all** does what it can by itself; the rest each card explains. When every card is ready, **Continue** opens the library.

NX Library never runs `sudo`, never accepts the Xcode licence and never changes `xcode-select`. The .NET installer asks for your password in Apple's own Installer.

## Building from source

```bash
cd ~/Developer/NXLibrary
bash scripts/bundle_runtime.sh   # once, and after runtime.lock changes
bash scripts/build_app.sh
bash scripts/build_dmg.sh        # optional: dist/NXLibrary.dmg
open "$HOME/Applications/NXLibrary.app"
```

`bundle_runtime.sh` is for the maintainer: it downloads the Python build and wheels pinned in `runtime.lock`, checks their hashes, copies Homebrew's `zstd` and `glslang` (the locked versions must be installed) with their libraries, relinks them to `@loader_path`, signs them ad hoc and audits the result into `work/Runtime`. Without `work/Runtime`, `build_app.sh` makes a developer build that uses `~/nxnative/.venv` and the tools on `PATH`.

The app is ad-hoc signed and installed as `NXLibrary.app` (bundle ID `local.nxlibrary`). Set `NX_BUILD_CONFIG=debug` to package the debug binary:

```bash
NX_BUILD_CONFIG=debug bash scripts/build_app.sh /tmp/NXLibrary-Debug.app
/tmp/NXLibrary-Debug.app/Contents/MacOS/NXLibrary --preview-build   # DEBUG only
```

`--show-setup` (DEBUG only) reopens the Setup check.

### Making a release

```bash
bash scripts/release.sh 0.2.0                                   # build, verify, zip and DMG in work/release/
bash scripts/release.sh 0.2.0 --publish --notes notes-0.2.0.md  # also tag v0.2.0 and create the GitHub release
```

It refuses a dirty tree, a version that is not dotted numbers, an existing tag or a missing `work/Runtime`. The app it builds carries the version and the `NXLibraryRelease` marker, the only kind of copy that updates itself; `build_app.sh` alone takes `NX_VERSION` and `NX_RELEASE=1` but sets neither by default. It also appends a hidden `<!-- nxlibrary-requires xcode=… engine=… -->` line to the notes, read from `ToolchainRequirements.minimumXcode` and `pinnedEngineCommit`: the update dialog warns about an Xcode to update first and says Setup brings the new engine after the restart, in one step. Players never update the engine on its own; a new engine always comes with a tested NX Library release. Before the first release, set `AppUpdate.defaultRepository` to the GitHub `owner/name`; until then the update feature is hidden (`defaults write local.nxlibrary NXLibrary_UpdateRepository owner/name` turns it on for testing).

## First run

The Setup check opens on the first start, and later when something that was ready breaks or falls out of step with the engine; **Settings → Start-up → Open Setup** opens it at any time. Each time it opens, NX Library fixes by itself what the engine requires: it clones or updates the engine to the pinned commit (never over local changes), downloads the certified Metal compiler by its Apple asset build, and downloads Microsoft's .NET 10 SDK installer. Every running card shows a progress bar. **Install all** also installs a newer .NET 10 patch when Microsoft has one. It rechecks every few seconds, so a card turns ready as soon as an installer finishes.

What NX Library is tested with lives in one table, `ToolchainRequirements.current` (minimum Xcode, .NET major, certified Metal and its asset build); the engine commit stays in `AppViewModel.pinnedEngineCommit`. Imported apps are playable immediately; their rebuilds stay disabled until sources are located.

## Adding a game

1. Open **Add Game**, drop a folder or file, or use **Choose Folder**.
2. Review the detected base/update/DLC sources. The base is locked; the newest update and non-empty DLC are selected by default.
3. Review the destination and disk estimate (twice the selected sources plus 10 GB).
4. Choose **Add and port** or **Add to library only**. An existing title offers **Rebuild** or **Save changes** and opens Review with its own saved options.

Builds go to `~/Applications/<game>.app`. Sources stay where they are; a staged workspace uses symlinks.

## Settings and artwork

- **Settings → Games → New games** supplies starting values for newly added titles. Existing games keep their own choices.
- **Game Options → Next launch** changes one title. **Use new game defaults** copies the current defaults once. Review shows and saves that title's actual options; rebuilds use its saved language.
- **Cloud saves** is reapplied before every launch, including Off. Advanced save-sync overrides in configuration files remain reported in Saves.
- **Settings → Look → Wallpaper** controls the app background. **Game backgrounds** shows game artwork in Spotlight and Collection when On, and the wallpaper when Off. Details keeps the game's artwork; launch-screen style is separate.
- **Change artwork** saves choices for one title, with manual picks ahead of automatic images. Its status line indicates where the selected kind is used. **Wallpaper sizing** fits wallpapers; **Library shade** shades library text areas.
- **Controllers → Library controls** affects navigation in NX Library. Its **New games** group supplies starting rumble values. Search and Changed point rumble settings to Controllers.

## Save backups and imports

Open **Game Options → Saves** with the game closed. NX Library manages the committed local save under `~/Library/Application Support/nxnative/<title ID>/`.

| Action | Purpose |
|---|---|
| **Open folder** | Open the current local save in Finder. |
| **Back up now** | Create a dated, verified copy of the current account and device saves. |
| **Save type** | Choose the destination for an import. **User save** is the usual choice. **Device save** selects a separate device save for games that use both. |
| **Import save…** | Preview an emulator/console export folder or restore a dated NX Library backup. |
| **Refresh** | Read the current save and backup information again. |
| **Backup folder** | Open this game's backup directory. The row shows the date and time of the latest copy. |

For Ryujinx, choose the numbered game folder under `bis/user/save/`. A selection inside it is recognized too. NX Library checks the title ID in Ryujinx's metadata and imports the complete committed `0` tree, including every slot. Other exports should be selected at the folder containing the complete game save. Files retain their relative paths through the common import flow for all titles.

After confirmation, import and restore first create and verify a full backup of the current saves. Import replaces the selected destination. Restoring a dated backup restores both recorded destinations, including their presence or absence. The preview shows the paths, file count, size and installed version. Every completed import displays a Selene **Imported successfully** card that fades away after three seconds.

Backups preserve file contents and guest-name extended attributes. They live under `~/Library/Application Support/NXLibrary/SaveBackups/<title ID>/<timestamp>-<UUID>/`. Manual copies and copies made before import or restore appear in the same directory. To restore one, select its dated folder in **Import save…**. Backup retention is managed by the user in Finder.

Import and restore require cloud sync to be off in the effective configuration, including the game's own preferences and env files. Keep the game closed until completion. The panel accepts default save paths and refuses symlinks or redirected destinations. An interrupted replacement is recovered before Play. Save compatibility depends on the game and version, and turning cloud sync on later can replace the imported local save.

Ryujinx imports have been exercised with Prince of Persia and Breath of the Wild. The user confirmed the imported Breath of the Wild progress works in-game. Automated tests also cover unrelated synthetic title IDs, different directory layouts and both destination types.

## Compatibility gate

New builds are blocked unless the installed engine commit, working tree, Metal compiler and nxnative CLI match the certified combination. The current pin certifies Metal `32023.921` (`metalfe-32023.921.6`), available as Apple's `27A266a` asset. The gate is visible under **Settings → Engine**.

The [2026-10-31 upgrade note](docs/upstream-upgrades/2026-10-31-ee369f0-2716f78.md) records the user's explicit choice to verify Prince of Persia with Xcode 27.2 and Metal `32023.922` through the untested-toolchain override. That build records `toolchainVerified=false`.

An explicit **Build anyway with an untested toolchain** override exists. It requires confirmation, persists in `UserDefaults`, passes `--allow-other-metal` to the engine, and records every build made under it as **untested**. Corrupted graphics are a documented upstream risk; the existing BotW build is left untouched.

## Updating the engine

Engine upgrades are manual and never follow `main`. Before changing the pin, review the commits and decide what belongs in the UI and what stays backend-only. The checklist and dated notes are in [`docs/upstream-upgrades/`](docs/upstream-upgrades/); the current pin is `2716f78f01e90a9f9bbf0d09e7a798903525962f`.

## Tests

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

The suite covers models and persistence, source parsing (including a regression for `*.cnmt.nca` vs `*.cnmt.xml`), symlink workspaces, key import/permissions, the compatibility gate, build-command construction, atomic installation and interrupted retries, process cancellation, launch environment writing, import, storage, cheats, save snapshots and interrupted save recovery. Scans preserve pending installs and the last porting failure. The last code verification on 2026-11-01 passed **676 tests**, including retrying a ready build without recompiling, per-title Review settings and language, explicit source replacement, cloud Off at launch and controller-setting search. The [file catalog](docs/file-map.md#test-e-fixture) describes each test file's scope.

## Repository layout

- `Sources/NXLibraryCore/` — models, library store, source catalog, key store, workspace, build/launch/import/storage/compatibility services.
- `Sources/NXLibrary/` — SwiftUI app, view model, views and theme.
- `Tests/NXLibraryCoreTests/` — core tests with synthetic PFS0 fixtures; no copyrighted game data.
- `Resources/` — original app icon and appearance variants.
- `scripts/build_app.sh` — release/debug app bundling and ad-hoc signing.
- `scripts/release.sh` — a release copy, its zip and DMG, and optionally the GitHub release.
- `docs/superpowers/` — design spec and implementation plan.

## Documentation

- [Technical guide](docs/architecture.md) — current architecture, dependencies, feature flows, persistence and verification, written in Italian.
- [File catalog](docs/file-map.md) — every versioned file and its responsibility, grouped by area, written in Italian.
- [2026-11-01 audit review](docs/2026-11-01-audit-review.md) — verified findings, reproduced installation conflicts and measured performance costs, written in Italian.
- [Dated designs and plans](docs/superpowers/) — original design, feature specifications and implementation records.
- [Engine upgrade notes](docs/upstream-upgrades/README.md) — adoption checklist, pin changes and verification evidence.

## Licenses and attribution

NX Library is MIT licensed. `NOTICE` retains the MIT copyrights for nxnative and the [rennan101/nxnative_Launcher](https://github.com/rennan101/nxnative_Launcher) GUI baseline; NX2Apple was a reference only and no code from it was copied. The app icon is original.

Bundled media and their licenses are listed in `Resources/Selene/NOTICE.txt` and `NOTICE-palettes.txt`: Material Icons (Apache 2.0), Selene's four synthesized sounds (MIT), the Selene palettes (MIT) and five public-domain wallpapers. Other Selene sounds and wallpapers are never bundled; the import action copies them from the user's own checkout. Online wallpapers are never bundled or committed: they are fetched from Wallhaven, Danbooru, MotionBGs and Steam only when the player browses, belong to their owners, and are credited under the preview.

No games, keys, Nintendo logos, fonts, sounds, or other Nintendo assets are included. NX Library is not affiliated with, endorsed by, or sponsored by Nintendo.

## Known limitations

- The Breath of the Wild sources were removed from this Mac. Its imported app remains playable, but a BotW rebuild is blocked until the XCI base, update 1.9.0 and DLC are restored and attached.
- Super Mario Odyssey 1.4.1 builds with engine `4f24ce6` (27,984 shaders and 32,864 pipeline pairs) and reaches the controller screen; gameplay beyond that is not yet verified.
- Native 1440p/4K rendering is not supported. The window or fullscreen display sets output resolution; render scale is 50–100% and only changes the internal 3D resolution. MetalFX improves the upscale. BotW supports the render-scale stub; the current SMO build does not, so its render-scale card is hidden.
- No notarization, no iOS/IPA output, no online compatibility database and no automatic engine updates. The upstream changelog check is manual and read-only; only the commit hash is sent to `api.github.com`.
- The engine checkout is never modified; nxnative upgrades are manual and re-pin the engine commit in `AppViewModel.pinnedEngineCommit`.
- A detached-sources game shows no source badge over its tile and keeps its artwork; the detail card shows **Sources detached** with an info tooltip and **Attach Sources…** next to Rebuild.
