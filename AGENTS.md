# NX Library — agent guidance

A personal macOS SwiftUI front-end for upstream [nxnative](https://github.com/seedds/nxnative). Read `README.md` and `docs/superpowers/specs/2026-10-26-nxlibrary-design.md` before changing behavior.

## Non-negotiables

- Use upstream nxnative in place. Never patch `~/nxnative`; engine updates are manual and re-pinned in `AppViewModel.pinnedEngineCommit`.
- No Nintendo assets, keys, ROMs, or game content in the repository.
- Sources are symlinked, never copied. Builds install to `~/Applications` and replace the previous app atomically.
- Keys stay mode `0600`; never log key values.
- The Metal gate blocks new builds unless the toolchain is certified or the explicit untested override is enabled. An override records `toolchainVerified=false`.
- Play remains available for an existing app even when a new build is blocked.

## Upstream engine upgrade

Every re-pin is a product decision, not just a hash change. Before changing the pin:

1. Fetch and list the delta:
   ```bash
   git -C ~/nxnative fetch origin
   git -C ~/nxnative log --oneline <pinned>..origin/main
   git -C ~/nxnative diff --stat <pinned>..origin/main
   ```
2. Read the engine's current `scripts/build_ipa_from_nsp.py -h`, `docs/env_switches.tsv`, `dm/games/*/README.md`, and the changed docs.
3. Classify each change: shader/pipeline, host/runtime, input/display/audio, game profiles, build/extraction, CLI/env, docs/tests.
4. For each user-visible capability decide **UI**, **backend only**, or **not adopted**, and say why.
5. Wire any new engine flag that maps to an existing NX Library control. Example: nxnative 4f24ce6 added `--allow-other-metal`; it must be passed when the app's untested-toolchain override is on.
6. If the engine's `dm/gfx/tools/dmsh_chain.lock` certifies a new Metal compiler, add it to `ToolchainRequirements.current.metalAssets` with Apple's asset build from `xcodebuild -showComponent MetalToolchain -json` (`buildVersion`), so the Setup check can download exactly that compiler. Raise `minimumXcode` when the new compiler needs it.
7. Re-pin only after tests, the compatibility gate, a certified build, and a smoke launch. Update `README.md` and the design spec.
8. Write a dated note in `docs/upstream-upgrades/` using the checklist there.

Never follow `main` automatically. A commit that is newer is not automatically a commit that is tested with this Mac's toolchain.

## Verification

```bash
cd ~/Developer/NXLibrary
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
bash scripts/build_app.sh
codesign --verify --deep --strict "$HOME/Applications/NXLibrary.app"
```

Then verify the gate in **Settings → Engine**, build one real game, and launch it to a visible screen. Do not claim a build or game is working from compilation alone.

Releases go through `scripts/release.sh` only: it refuses a dirty tree, so commit or stash local changes first. Never publish (`--publish`) without the user asking.
