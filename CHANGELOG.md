# Changelog

User-visible changes to NX Library are recorded here. Entries are grouped by release, with the newest first. Engine changes also have their own [upgrade notes](docs/upstream-upgrades/README.md).

## Unreleased

### Added

- **Check for Updates…** in the macOS app menu, using the same dialog as About: checking, release notes, up-to-date results, errors and download progress, with keyboard/controller support.
- **Start in fullscreen** in Start-up settings, applied at the next launch and kept separate from game display options.

### Changed

- Native menus wait until they close before opening screens and keep the library selection still while active. Game Details follows Spotlight’s existing page, Game Options uses its normal overlay, and unavailable commands are disabled. The upstream changelog stays in Engine settings; the duplicate native View menu is removed.
- The launcher uses one window; File → Add Game replaces the unsupported New Window command.

- Existing nxnative apps are discovered inside subfolders of the selected Game apps folder. Scans have depth and directory limits, skip app contents and explain skipped folders in Library settings while retaining the saved library.
- The pointer hides after three seconds without movement in the fullscreen launcher. Moving the mouse reveals it; keyboard/controller navigation keeps it hidden. Native system panels and leaving fullscreen or the app restore it.

### Fixed

- When multiple builds of a title are discovered, library refresh keeps the installed app and its own metadata together. Existing references outside the newly selected folder remain intact while the app exists.

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
