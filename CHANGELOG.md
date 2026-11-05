# Changelog

User-visible changes to NX Library are recorded here. Entries are grouped by release, with the newest first. Engine changes also have their own [upgrade notes](docs/upstream-upgrades/README.md).

## Unreleased

### Added

- **Mods.** Put file mods (a folder with `romfs` inside) into a game's mods folder, turn them on in the game's new **Mods** band or in **Game options → Mods**, and play: no rebuild. The order decides which mod wins when two change the same file, and **Remove** moves a mod to the Trash. Mods that patch code (`exefs`, such as 60 fps patches) don't work with the engine.
- **Game app icons follow your Icon choice.** A game whose app has no icon (Switch 2 games and dumps) shows the Icon you choose in **Change artwork** in Finder and the Dock. For a game with its own icon, a question after choosing lets you use yours on the Mac too. The icon stays after a rebuild, and **Automatic** brings back the game's own. Updating a large game's app takes about a minute.

### Changed

- The intro shows only the moving background, without the app icon.

## 0.1.3.3 — 2026-11-05

### Fixed

- Extracted games (dumps) are recognised in every layout the engine accepts. Before, only a folder holding `base/exefs` and `base/romfs` worked, and choosing the `base` folder itself said "No NSP, XCI, NSZ, XCZ or NUP files were found in this folder". Now these work too:
  - a folder with `exefs` and `romfs` directly in it (the `base` folder, or what `nup extract` writes); a `base` folder inside a dump with updates or DLC brings them along;
  - a dump with only an update (`updates/<version>/`), played as the whole game like a NUP without a base game;
  - a `base` with only its code, when an update has the RomFS.
- A folder with no game says what NX Library looks for, extracted folders included.

## 0.1.3.2 — 2026-11-05

### Fixed

- Games and updates for system 22.0.0 and later, whose code Nintendo compresses with ZBIC (its own zstd variant), now build. Before, the porting stopped with "The engine needs the zbic package to read this game's code", even after `pip install zbic`: NX Library uses only its built-in Python, which lacked the package. The built-in Python now includes zbic 1.0.1.post1 (GPLv2; its source ships in `Runtime/sources/`), and Setup checks it with the other modules.
- NSZ and XCZ files build without a separate nsz install. The engine converts them with the nsz tool, which the built-in Python lacked, so they worked only where nsz happened to be installed. The built-in Python now includes nsz 5.0.0 and its dependencies.
- Setup and the build check test every package and tool the engine needs (zbic, nsz and `make` too), so **All set** no longer appears when one is missing.
- A game built with a Language it does not have explains it and points to Game options (Game Default or one of the game's languages), instead of "The porting stopped".
- A package too damaged for Port anyway (cut off, or its own tables fail their hash check) asks for a new dump or download and no longer offers Port anyway.

## 0.1.3.1 — 2026-11-05

### Fixed

- Add Game accepts Switch 2 NUP files that hold only updates, as the engine does. Before, such a file stopped with "The NUP file could not be read: AttributeError: 'NoneType' object has no attribute 'meta'". Review lists the file's updates (the newest is selected; one always stays selected) and its DLC, and notes **No base game in this NUP**: the selected update is played as the whole game, and if the game stops on missing files, a NUP that includes the base game is needed.

## 0.1.3 — 2026-11-05

### Changed

- **Game options follow each game's build.** For games built with a current engine, NX Library keeps your choices where the game itself keeps them (its saved choices), so a change made in the game's own settings window, opened from Finder, shows in NX Library, and NX Library's choices apply from Finder too. Only choices that differ from the game's tested default are kept, so a rebuild with better defaults reaches you. Rows appear only when the game offers them: Frame rate (with 120 fps where a game supports it) replaces the 60 FPS switch, a new Game's upscaler row appears where available, and the other settings a game offers are under **More settings**. Your existing choices are moved over automatically; lines you wrote yourself in `env.txt` stay and are shown as fixed. Games built with an older engine keep working as before until rebuilt. Thanks to PR #1 for showing that Game options should read the game's own settings list.
- Switch 2 games get their description, genres, background and cover automatically: the Nintendo store's Switch 2 pages are used, and a cover GameTDB lacks is taken from TheGamesDB.
- Switch 2 games show **Nintendo Switch 2** as their platform.
- Updated the pinned nxnative engine to `4a0551e4`: fixes and updated profiles for games such as Super Mario Odyssey, Breath of the Wild, Tears of the Kingdom and Donkey Kong Bananza, new Switch 2 profiles, Mac apps no longer held at low GPU clocks by Game Mode, and work folders that stop growing. Certified Metal `32023.922` and Xcode 27.2 remain the requirements. Existing apps receive the new runtime only when rebuilt, and every game rebuilds its shaders at its next build. After a game is rebuilt and played with this engine, an older build of that game may not read some of its saves.
- A build stage that finishes with a warning shows ⚠ instead of ✓, and **Ready to play** explains it. The engine uses it when a game's pipeline archive cannot be made: the app is still built, and the game prepares its shaders when it first needs them.
- NUP files and extracted folders for a game the engine has no profile for are accepted: the engine makes a provisional one. Review shows **Not tested with this engine yet** for any source without a profile, NSP included, because the porting may stop or the game may not start. A folder without a profile is named after itself.
- The controls guide lists quitting a game with the controller: hold Home for 2 seconds, then A, in games built with the current engine.
- Release notes in the update dialog are easier to read: section headings, and each item with a dot and aligned wrapped lines. Updates after 0.1.3 show their notes this way.
- Development builds show the version in progress, marked **(development build)**, instead of 0.1.0. They never offer app updates.

### Added

- **Newest engine.** Settings → Engine can switch to nxnative's newest `main` before NX Library has tested it, for players who want new engine fixes early. It is your choice, never automatic: an orange dot and one sentence say it is not yet tested by NX Library, it usually works but something may not, and its new features reach NX Library in a future version. The untested-toolchain override stays on and builds are recorded as untested; **Back to tested** returns to the tested engine (also from Setup), and games you built keep playing. It is not offered when `main` needs a different Metal compiler, which needs a newer NX Library. Setup still installs the tested engine and shows your choice without treating it as a problem.
- **Switch 2 NUP files.** Add Game accepts a `.nup` file, chosen on its own or as the only one in a folder. Review lists its base game, updates and DLC: one update is chosen at a time, and every DLC in the file is included, as the engine builds it. A NUP that carries the game's icon gives the app that icon; a plain dump folder still builds without one.
- **Browse LaunchBox and SteamGridDB in Change artwork.** Two **Browse online** tiles, right after Automatic, open a source's own grid, as the Theme screen browses wallpaper sites: the search starts with the game's name and can be changed, results follow the open tab (Cover, Background, Icon, Logo), each image shows its kind and region (LaunchBox) or its author (SteamGridDB) and its full size, and X opens the game's page on the source. The grid loads small previews; the full image is downloaded only when you choose it. SteamGridDB needs your free API key: without one, its tile asks for it first (it can also be added in Settings → Look). The key stays on this Mac in a private file and is sent only to SteamGridDB; only still images are listed, and art tagged NSFW, humor or epilepsy is left out.
- **Screenshots for Switch 2 games.** When Title DB has no screenshots for a game, LaunchBox's gameplay screenshots are used at full size, in Spotlight and Details (credited there as **Screenshots · LaunchBox**). They are looked up with the game's other details, when you select or open it, once per game; the answer is kept for 30 days. Library scans never ask.

### Fixed

- Refreshing the library no longer takes minutes for large game apps on an external drive: app sizes are measured the way `du` does, and each measured size is kept even if you quit during the scan (issue #2).
- The Cheats switch and **All off** no longer show an error for a game that has no cheat file yet.
- The Collection card in Spotlight now says "in one row": Collection is a single row of covers, not a grid (issue #3).

## 0.1.2 — 2026-11-03

### Added

- **Check for Updates…** in the macOS app menu, using the same dialog as About: checking, release notes, up-to-date results, errors and download progress, with keyboard/controller support.
- **Start in fullscreen** in Start-up settings, applied at the next launch and kept separate from game display options.

### Changed

- Updated the pinned nxnative engine to `b64a5ff0`: audio-start and memory-alignment fixes, renderer/shader corrections, updated game profiles and lower shader-build memory use. Certified Metal `32023.922` and Xcode 27.2 remain the requirements. Existing apps receive the new runtime only when rebuilt.
- Native menus wait until they close before opening screens and keep the library selection still while active. Game Details follows Spotlight’s existing page, Game Options uses its normal overlay, and unavailable commands are disabled. The upstream changelog stays in Engine settings; the duplicate native View menu is removed.
- The launcher uses one window; File → Add Game replaces the unsupported New Window command.
- **Scan game apps** in Library settings combines existing-build discovery and library refresh into one action.
- Shader-cache cleanup is shown as an activity without an estimated remaining time.

- Existing nxnative apps are discovered inside subfolders of the selected Game apps folder. Scans have depth and directory limits, skip app contents and explain skipped folders in Library settings while retaining the saved library.
- The pointer hides after three seconds without movement in the fullscreen launcher. Moving the mouse reveals it; keyboard/controller navigation keeps it hidden. Native system panels and leaving fullscreen or the app restore it.

### Fixed

- When multiple builds of a title are discovered, library refresh keeps the installed app and its own metadata together. Existing references outside the newly selected folder remain intact while the app exists.
- New engine diagnostics explain outdated keys with the required firmware when known, and distinguish a missing package ticket from a key-file problem.

## 0.1.1 — 2026-11-02

### Changed

- Updated the pinned nxnative engine to `65501fbb`, including AV1 movie decoding with an automatic dav1d fallback, shader-cache and texture-lifetime fixes, more robust rewriting and updated game profiles. Xcode 27.2 and certified Metal `32023.922` remain the requirements.
- Existing game apps remain playable. Setup prepares the new engine; rebuilding a game applies it to that game. No new everyday settings are required.

## 0.1.0 — 2026-11-02

First public alpha for Apple-silicon Macs, with a DMG for installation and a ZIP for app updates. See the [release notes and downloads](https://github.com/Bium23/NxLibrary/releases/tag/v0.1.0).

### Added

- Two-step setup: **Get ready** for tools and keys, then **Your games** for the app folder, existing games and a first source-file or folder choice. **Skip for now** is remembered; interrupted setup resumes, and both steps can be reopened from Settings without resetting the library.

- Public GitHub app-update channel on `Bium23/NxLibrary`, without a separate user login. Packaged release copies can offer, download, verify and install newer versions.

- Integration for nxnative `163a9905`: extracted-folder inputs without keys, registered-profile checks, multi-title package selection, bundled-content review and unique source-size accounting.

- A native macOS library with Spotlight, Collection, search, favourites, hidden games and game details.
- Guided Setup and local nxnative builds from user-supplied sources, with base/update/DLC review, progress, logs and cancellation. Existing game apps can be imported and played without their sources.
- Per-game launch options, artwork and metadata; library themes, wallpapers, interface sounds and keyboard/controller navigation.
- Local save backups, folder-import previews and restores, including recovery after an interrupted replacement.
- Cheat-file import and per-cheat switches, with changes applied at the next launch.
- Selene-style setup and error dialogs, separate Library and In game controls guides, and a brief **Imported successfully** notice after verified save imports.
- An illustrated user guide with screenshots and planned next steps, an architecture guide, a file catalog, contribution and security policies, publication checks and continuous integration.

### Changed

- Add Game accepts individual NSP/XCI/NSZ/XCZ files as well as folders. File picks stage only the selected packages and preserve the global Game files folder. A first single-title selection opens Review; multi-title scans require an explicit choice. Key rescans retain update/DLC selections, and cancelling or discarding a draft preserves folder preferences.
- An empty Spotlight initially focuses Add Game; Collection keeps an **Add your first game** prompt after setup is skipped.

- **Game apps** is the single folder for existing nxnative apps and new builds, chosen in Setup or Settings → Library (default `~/Applications`). Changing it does not move installed games; rebuilds update the existing app where it is. Review and disk checks use the actual destination, and disconnected or read-only folders stop installation while preserving a ready build for retry. **Game files** remains separate and optional.
- Unavailable games keep their library entry and use the existing blurred, locked artwork with a short reason. Missing apps no longer send the primary action to Attach sources; missing inputs disable rebuilding while existing apps remain playable.

- New-game defaults and each game's **Next launch** settings have explicit scopes. Rebuild review retains the selected title's saved options; **Use new game defaults** copies defaults once.
- The Saves page keeps one **Backup folder** row showing the latest backup's date and time. Imports use a centred From → To preview with outlined paths and a subtle directional animation.
- The engine is pinned to `163a9905`, with Xcode 27.2 and certified Metal `32023.922`. Adoption and verification are recorded in the [2026-11-02 upgrade note](docs/upstream-upgrades/2026-11-02-2716f78-163a9905-review.md); newer upstream commits are not adopted automatically. The main app replaces the separate EnginePreview launcher.
- App-update preparation and background snapshot preparation run outside the main UI work. Source builds do not update themselves; packaged releases use the project's public GitHub release channel.

### Fixed

- Automatic controller prompts discard shape-only variants such as `capsule.portrait` and use the controller brand's readable symbols. Collection/Menu prompts no longer accept those shapes as black filled badges; meaningful PlayStation face-button glyphs remain unchanged.

- Missing configured folders remain remembered, and a folder selected during the startup scan is scanned before results are published. Unbuilt workspaces and active portings are no longer mistaken for missing installed apps during refresh.

- A saved untested-toolchain override can be turned off after the gate becomes certified. Restaged source workspaces discard deselected links and empty DLC containers while preserving their build cache. Sources that require new engine capabilities cannot silently rebuild through an older engine.

- Library scans preserve pending installations and previous build failures. Ready builds can be installed again after an installation failure without recompiling.
- Game apps and development app builds are installed through a staged, atomic replacement. A running game delays replacement of its app.
- Ryujinx save imports recognise the complete committed save tree even when a nested folder was selected, validate title metadata and retain all save slots. The import flow is shared across titles; game/version compatibility still applies.
- Save snapshots preserve guest-name metadata, and interrupted imports recover before Play. Import previews and refresh status no longer add shifting rows to the page.
- Cloud sync set to Off is reapplied before launch. Settings writes report failures with Retry; unreadable preferences are preserved before defaults are saved.
- Build events containing UTF-8 characters split across pipe reads are retained, including the final line at end of output.
- Settings rows with identical labels remain independently reachable. Intro, controls, dialogs and Reduce Motion handling have been aligned with the shared interface components.

### Security

- Updates require a GitHub-hosted asset with a valid digest and bounded size, reject unsafe paths and bound actual decompressed output while extracting to staging. The sealed app signature is verified before replacement. Failed update checks do not suppress retries for a full day.

- Managed key replacement preserves the existing file on failure and enforces private `0600` permissions. Key values are never included in diagnostics.
- Cheat title IDs and downloaded background filenames are validated. Custom cheat destinations require confirmation.
- .NET installer downloads verify their expected hash and restrict download hosts and redirects.
- App updates and save operations exclude each other. Publication checks reject recognised private/game-content paths and secret patterns; bundled runtime metadata is checked against `runtime.lock` before packaging.

Verification details and remaining distribution checks are recorded in the [development guide](docs/development.md). Automated checks do not certify game compatibility, visual behaviour or a first installation on another Mac.

<!-- When the first release is actually published, move the relevant entries under
     a heading such as "## [0.1.0] - YYYY-MM-DD", add its real release link, and
     leave a fresh Unreleased section above it. Do not date a release in advance. -->
