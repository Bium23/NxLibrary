# Changelog

User-visible changes to NX Library are recorded here. Entries are grouped by release, with the newest first. Engine changes also have their own [upgrade notes](docs/upstream-upgrades/README.md).

## Unreleased

The current source preview identifies itself as **0.1.0 alpha**. No tagged or downloadable release has been published yet. This section describes the work included in the preview; it is not a history of published versions.

### Added

- Public GitHub app-update channel on `Bium23/NxLibrary`, without a separate user login. Packaged release copies can offer, download, verify and install newer versions; the first downloadable release and interactive A → B check are still pending.

- Candidate integration for nxnative `163a9905`: extracted-folder inputs without keys, registered-profile checks, multi-title package selection, bundled-content review and unique source-size accounting. The stable engine pin is unchanged pending a real certified build and manual launch.

- A native macOS library with Spotlight, Collection, search, favourites, hidden games and game details.
- Guided Setup and local nxnative builds from user-supplied sources, with base/update/DLC review, progress, logs and cancellation. Existing game apps can be imported and played without their sources.
- Per-game launch options, artwork and metadata; library themes, wallpapers, interface sounds and keyboard/controller navigation.
- Local save backups, folder-import previews and restores, including recovery after an interrupted replacement.
- Cheat-file import and per-cheat switches, with changes applied at the next launch.
- Selene-style setup and error dialogs, separate Library and In game controls guides, and a brief **Imported successfully** notice after verified save imports.
- A user guide, architecture guide, file catalog, contribution and security policies, publication checks and continuous integration.

### Changed

- New-game defaults and each game's **Next launch** settings have explicit scopes. Rebuild review retains the selected title's saved options; **Use new game defaults** copies defaults once.
- The Saves page keeps one **Backup folder** row showing the latest backup's date and time. Imports use a centred From → To preview with outlined paths and a subtle directional animation.
- The engine is pinned to `2716f78`. Adoption and toolchain verification are recorded in the [2026-10-31 upgrade note](docs/upstream-upgrades/2026-10-31-ee369f0-2716f78.md); newer upstream commits are not adopted automatically.
- App-update preparation and background snapshot preparation run outside the main UI work. Source builds do not update themselves; packaged releases use the project's public GitHub release channel.

### Fixed

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
