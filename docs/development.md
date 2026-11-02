# Development and releases

This guide covers building NX Library itself. For app setup, game preparation and daily use, start with the [user guide](../README.md). Read [AGENTS.md](../AGENTS.md) before changing engine integration or installation behaviour.

## Development prerequisites

- An Apple-silicon Mac running macOS 13 or later.
- Full Xcode selected for the build. The current game toolchain requires Xcode 27.2 or later and the Metal compiler certified for the pinned engine. `Package.swift` declares Swift tools 5.9 and macOS 13 as package minimums; those values do not certify an engine/compiler combination.
- Git and the command-line tools supplied with Xcode.
- Python 3 for the publication checks and packaging helpers.
- Homebrew's `zstd` and `glslang`, at the versions recorded in [runtime.lock](../runtime.lock), when preparing the bundled runtime. The script checks installed versions; it does not install or silently upgrade them.

Building the frontend alone does not need games or keys. Running the game's build workflow also needs the .NET 10 SDK, the pinned nxnative checkout and the user's own authorised sources and keys. Setup explains and prepares the supported prerequisites.

## Build a development app

From the repository root:

~~~sh
bash scripts/bundle_runtime.sh
bash scripts/build_app.sh
codesign --verify --deep --strict "$HOME/Applications/NXLibrary.app"
~~~

The default destination is `~/Applications/NXLibrary.app`. `build_app.sh` compiles the Release configuration, creates the bundle in staging, includes resources and notices, ad-hoc signs and verifies it, then installs it through the same atomic installer used by the application. It does not launch the app.

An alternate destination can be supplied without replacing the installed development copy:

~~~sh
bash scripts/build_app.sh /tmp/NXLibrary-Review.app
~~~

A plain development app uses bundle ID `local.nxlibrary`, defaults to version `0.1.0` and has no release marker. It never installs its own updates.

### Bundled runtime

`bundle_runtime.sh` prepares `work/Runtime/` from the exact downloads and hashes in `runtime.lock`. It includes Python, capstone, lz4, fontTools, `zstd` and `glslangValidator`, their required non-system libraries and licence notices. It relinks the native libraries for the bundle, signs them and checks that the tools run without Homebrew on `PATH`.

Run it again when the lock changes. `build_app.sh` checks the runtime metadata against the lock before copying it. The lock is a reviewed input, not a request to install whichever package versions happen to be newest.

For frontend-only work, `build_app.sh` can run without `work/Runtime/`. That development copy uses the configured engine's virtual environment and tools on `PATH` for game preparation. It is not a self-contained distribution build. A release requires the bundled runtime.

Generated `.build/`, `work/` and `dist/` content stays outside version control. Do not commit the user's engine checkout, game apps, source packages, keys or diagnostics.

### Debug configuration

~~~sh
NX_BUILD_CONFIG=debug bash scripts/build_app.sh /tmp/NXLibrary-Debug.app
~~~

Debug builds recognise `--show-setup` and `--preview-build` for manual inspection of Setup and the simulated porting presentation. These flags are compiled out of Release builds. The preview is UI development data, not evidence that a real game builds or launches.

## Verification

~~~sh
python3 scripts/check_publication.py
python3 -m unittest discover -s Tests/PublicationChecks
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
bash scripts/build_app.sh
codesign --verify --deep --strict "$HOME/Applications/NXLibrary.app"
~~~

To check the prepared runtime as well:

~~~sh
python3 scripts/check_publication.py --runtime work/Runtime
~~~

The Swift suite covers persistence, sources, keys and permissions, CLI contracts, process output and cancellation, compatibility gates, installation and retries, launch configuration, presentation state, artwork, cheats and save recovery. Publication regressions use temporary repositories and synthetic content. Tests must never require copyrighted game content or real keys.

The latest complete Swift verification on 2 November 2026 passed **755 tests**, including chosen-folder installation/discovery, rebuilds after a folder change and preserving ready builds when their destination disconnects. The earlier publication verification passed **15 Python checks**; the development-app bundle passed signature verification, and a headless check exercised a real public GitHub download, its redirect and rejection of a mismatched size. These checks do not establish that the interactive update or a game worked. This is dated evidence, not a promise about future changes. See the [test catalog](file-map.md#test-e-fixture).

### Continuous integration

The [Checks workflow](../.github/workflows/ci.yml) runs publication checks and their regressions, Swift tests, Release compilation, development-app packaging and signature verification on the `xcode-27` runner. Pull requests from forks stay off that runner and receive the hosted publication checks instead. The checkout action is pinned, repository permissions are read-only and credentials are not retained by checkout. It does not publish releases or run the UI, games or engine builds.

The engine-log-fragment test skips when `~/nxnative` is absent. A private CI run completed with **703 Swift tests reported: 702 passed and one skipped**, plus five Python checks. It verifies frontend packaging without the bundled game runtime; it does not replace the runtime check or the engine compatibility gate.

### Manual checks

Interactive app and game checks are performed by the user. Agents must not use computer-use or other UI automation. Compilation, unit tests and signature verification cannot establish that the interface or a game works.

Before a game/toolchain combination is described as working, the user checks **Settings → Engine**, builds a real game and launches it to a visible screen. Record the engine and Metal versions and whether the untested override was used.

## Engine upgrades

Never patch `~/nxnative` or follow its `main` branch automatically. The app's pin is in `AppViewModel.pinnedEngineCommit`; `ToolchainRequirements.current` describes the supported setup requirements and downloadable Metal assets.

An upgrade requires reviewing the upstream delta and CLI, deciding which capabilities to adopt, wiring applicable flags, updating certification data and verifying tests, the gate, a real build and a visible launch. Follow the [upgrade checklist](upstream-upgrades/README.md), write a dated note and update the README, design spec and changelog. A newer engine commit alone is not sufficient evidence.

## Release packaging

Use `scripts/release.sh` for releases. It requires a clean working tree, an unused version tag and a runtime that matches the lock. Commit or deliberately stash local work first; do not discard changes to satisfy the check.

For example, to prepare version 0.1.0 locally when it is ready:

~~~sh
bash scripts/release.sh 0.1.0
~~~

This example does not mean that 0.1.0 has been released. The script builds a release-marked app, verifies its version and signature, and produces a ZIP and DMG in `work/release/`. Without `--publish`, it does not push a tag or create a GitHub release.

Publishing requires an explicit maintainer decision and the script's `--publish --notes <file>` options. Prepare reviewed notes from [CHANGELOG.md](../CHANGELOG.md), then date the version when it is actually published. The script adds engine/Xcode requirement metadata to release notes for the updater. Never publish automatically as part of an agent's verification.

### Distribution work still open

No downloadable release has been published. Public binary distribution still needs a final app identity and signing policy, signing-identity verification for a future Developer ID release, and the first-installation/update test. Current copies are ad-hoc signed and not notarised. Updates verify GitHub's SHA-256 digest and the sealed app signature; ad-hoc signatures do not independently identify the publisher.

The updater uses `Bium23/NxLibrary` directly, with anonymous public access. No separate download repository or login is needed for users. Release copies update themselves; source builds remain excluded. `release.sh --publish` requires the configured repository to be public. ZIP downloads are limited to 512 MiB, restricted to GitHub's HTTPS download hosts and checked against the published size and digest. The bundled Python checks paths, symlinks, duplicates, special files and a 30,000-entry limit, then extracts using bounded raw decompression with a 2 GiB total limit. It verifies actual output size and CRC rather than trusting ZIP size fields. Release packaging uses this same extraction path and verifies the extracted bundle signature; ZIPs omit Finder metadata sidecars.

### First installation and A → B update test

Use a new macOS account without copying NX Library preferences or data. Xcode, Metal and .NET may remain available system-wide; this tests first use and updates, not installation of every prerequisite on a clean Mac. For any new engine pin, complete a certified game build and manual launch before adoption or distributing a package as ready.

1. Publish only release A initially. Download its DMG from GitHub in the new account, install normally, eject the DMG and complete Setup. Check whether the installation folder is writable by that account; updates must not require changing permissions silently.
2. Build and launch one supported game using the user's own files. Save progress, set a favourite and change one preference. Create a save backup, then close the game and app.
3. Back in the development account, prepare B with a higher numeric version and clear test notes, keeping the same bundle ID, data paths and engine pin. No artificial feature is required to exercise replacement.
4. Publish B through `scripts/release.sh`. Return to the test account and open A. Automatic checks run at most once per 24 hours; use **Settings → About → Check now** for an immediate check. The manual check exposes availability in About; the launch popup is a separate check after the interval.
5. Update from inside A. Verify B reopens, reports its version and retains the library, favourite, preference, keys, backups and game progress. Test the automatic launch offer separately. Record actual results; compilation does not establish that this interactive flow worked.

The updater reads `releases/latest`, which excludes draft and prerelease entries. Keep both A's DMG and ZIP when preparing B: `release.sh` replaces its local `work/release` output. Do not alter the Mac's clock to exercise the interval.

These are distribution decisions. Do not bypass the dirty-tree check, change the engine pin or weaken the Metal gate to make packaging succeed.

## Repository areas

| Path | Responsibility |
|---|---|
| `Sources/NXLibraryCore/` | Models, persistence, source catalog, keys, workspaces, build/install/launch services, settings, saves, cheats and media services. |
| `Sources/NXLibrary/` | App entry, coordination, SwiftUI screens, theme and macOS integration. |
| `Tests/NXLibraryCoreTests/` | Automated application/core regressions and synthetic fixtures. |
| `Tests/PublicationChecks/` | Publication-guard regressions. |
| `Resources/` | App icon, fonts, interface media and their notices. |
| `scripts/` | Runtime preparation, app packaging, installation helpers, release packaging and publication checks. |
| `docs/` | Current guides, audits, dated designs and engine-adoption evidence. |

For component interactions, read the [architecture guide](architecture.md). For the role of every individual file, use the [file catalog](file-map.md). Screenshots and demo placement are described in the [media guide](media/README.md).
