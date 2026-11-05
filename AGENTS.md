# NX Library — agent guidance

A personal macOS SwiftUI front-end for upstream [nxnative](https://github.com/seedds/nxnative). Read `README.md` and `docs/architecture.md` before changing behavior.

## Non-negotiables

- Use upstream nxnative in place. Never patch `~/nxnative`; engine updates are manual and re-pinned in `AppViewModel.pinnedEngineCommit`.
- No Nintendo assets, keys, ROMs, or game content in the repository.
- Sources are symlinked, never copied. New builds install to the selected **Game apps** folder (default `~/Applications`); rebuilds replace the existing app atomically in its current location. Changing the folder never moves installed apps.
- Keys stay mode `0600`; never log key values.
- The Metal gate blocks new builds unless the toolchain is certified or the explicit untested override is enabled. An override records `toolchainVerified=false`.
- Play remains available for an existing app even when a new build is blocked.

## Product value and human validation

These principles apply in every session, including work based on research, community suggestions or competitor features.

- Every feature must address a concrete user need and provide a clear benefit. State the problem, expected value and smallest coherent scope before implementation, with detail proportionate to the change. Improving an existing flow may be the right solution.
- Research and competitor features are inputs to evaluate, not an implementation checklist. Verify capabilities against the official engine and existing app behavior; defer ideas whose value or prerequisites are unproven.
- Give each feature time and attention through the complete user flow: discoverability, visual consistency, concise copy, keyboard/controller navigation, persistence, errors, cancellation and recovery where relevant. Keep the experience simple and preserve existing behavior outside the agreed scope.
- Optimize in response to a demonstrated problem. Establish a baseline and verify the benefit and tradeoffs; passing tests alone does not establish a performance improvement.
- Every added feature requires human review and manual validation by the maintainer (the user). Automated tests, successful compilation and agent reviews support that decision; they do not replace it.
- Complete the implementation and appropriate automated checks, then provide a concrete build and focused manual checks covering the intended behavior, relevant failure triggers and regressions. Until the user confirms the outcome, report the feature as **awaiting human validation**, not complete or release-ready. Preserve that status in handoffs so another session cannot assume approval.
- Finish and evaluate the current feature before expanding its scope or starting unrelated additions. Any research backlog remains a set of proposals until deliberately selected for work.

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
6. If the engine's README `pip install` line names a new package, add its wheel (and its dependencies) to `runtime.lock`, rebuild with `scripts/bundle_runtime.sh`, and update `NOTICE`; a GPL package also ships its source in `Runtime/sources/`. `EngineRuntimeRequirementsTests` fails until it is there.
7. If the engine's `dm/gfx/tools/dmsh_chain.lock` certifies a new Metal compiler, add it to `ToolchainRequirements.current.metalAssets` with Apple's asset build from `xcodebuild -showComponent MetalToolchain -json` (`buildVersion`), so the Setup check can download exactly that compiler. Raise `minimumXcode` when the new compiler needs it.
8. Re-pin only after tests, the compatibility gate, a certified build, and a smoke launch. Update `README.md` and the design spec.
9. Write a dated note in `docs/upstream-upgrades/` using the checklist there.

Never follow `main` automatically. A commit that is newer is not automatically a commit that is tested with this Mac's toolchain.

The only exception is the player's own choice in **Settings → Engine → Newest engine**: it moves the checkout to upstream `main` on request, turns the untested override on and records builds as untested, and is refused when `main` certifies a different Metal compiler. Setup keeps installing the pinned commit and never treats that choice as an error. Do not add any automatic path to `main`.

## Verification

The user performs interactive app and game checks. Never use computer-use tools or other UI automation. Agents run automated tests and build/install the app, then report any manual checks that remain.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
bash scripts/build_app.sh
codesign --verify --deep --strict "$HOME/Applications/NXLibrary Dev.app"
```

Development builds install as **NX Library Dev** (`~/Applications/NXLibrary Dev.app`), the maintainer's only test copy. Never build over, replace or test in the released `~/Applications/NX Library.app`; it is the copy installed from GitHub and updates itself.

Then verify the gate in **Settings → Engine**, build one real game, and launch it to a visible screen. Do not claim a build or game is working from compilation alone.

Releases go through `scripts/release.sh` only: it refuses a dirty tree, so commit or stash local changes first. Never publish (`--publish`) without the user asking.
