# Upstream nxnative upgrades

NX Library pins one nxnative commit and never follows `main`. Upgrading is manual because a new engine commit can change the build CLI, the shader/toolchain contract, or game behavior.

This directory records the review that must happen before the pin changes, plus one dated note per upgrade.

## Checklist

1. **Fetch, do not merge or check out yet.**
   ```bash
   git -C ~/nxnative fetch origin
   git -C ~/nxnative log --oneline <pinned>..origin/main
   git -C ~/nxnative diff --stat <pinned>..origin/main
   ```
2. **Read the contract surface**, not only commit subjects. Since `ae031161`, commits carry `Front-ends:` lines (`new`, `interface`, `break`) for what only their author knows; read every one in the range (`docs/frontends.md`, "Following main"):
   ```bash
   git -C ~/nxnative log --grep='^Front-ends:' --format='%h %s%n%b' <pinned>..<candidate>
   ```
   Then:
   - `scripts/build_ipa_from_nsp.py -h`
   - `docs/env_switches.tsv`
   - `dm/gfx/tools/dmsh_chain.lock`
   - changed `dm/games/*/README.md`
   - changed `docs/reference/*.md`
3. **Classify the delta** in a table:

   | Area | Commits / files | Workflow impact | UI or backend | Action |
   |---|---|---|---|---|
   | Shader / pipeline | | Build success, build time, shader cache | | |
   | Host / runtime | | Rendering, audio, services, stability | | |
   | Input / display | | Controllers, rumble, frame pacing | | |
   | Game profiles | | New titles or versions | | |
   | Build / extraction | | CLI, disk use, source formats | | |
   | CLI / env switches | | New flags or `DM_*` settings | | |
   | Docs / tests | | No runtime effect | | |

4. **Decide UI vs backend for every user-visible capability.**
   - **UI** only when the user must choose, see a state, or take an action that the existing screens cannot express.
   - **Backend** when the new behavior is automatic and the current build/launch/settings UI already gives the needed control (for example a shader fix, a new game profile, or a controller rumble fix).
   - **Not adopted** when the feature is diagnostic, game-specific tooling, or conflicts with the app's scope.
5. **Bundle new Python packages.** Compare the README's `pip install` line and any new lazy `import` under `scripts/` and `dm/` with `runtime.lock`. Add every new wheel with its dependencies, rebuild `scripts/bundle_runtime.sh`, update `NOTICE` (a GPL package ships its source in `Runtime/sources/`), and add it to the Setup probe. `EngineRuntimeRequirementsTests` checks the README line and, where the engine has it, `.github/requirements/tools.txt`; zbic (system 22.0.0+ code) and nsz (NSZ / XCZ) reached players missing because nobody did this.
6. **Integrate new engine flags** in `BuildCommandBuilder` (or the relevant service) and add a unit test. Do not leave an engine gate or override without a caller.
7. **Verify**:
   - full unit tests, with `PortingFailureEngineTests` and `EngineRuntimeRequirementsTests` run against the new pin (every engine message the failure table reads is still printed);
   - app rebuilt, signed, installed;
   - compatibility gate green (or an explicit recorded override);
   - one real certified build, including the pipeline archive stage;
   - smoke launch to a visible screen.
8. **Re-pin** `AppViewModel.pinnedEngineCommit`, invalidate the cached upstream status, update `README.md` and the design spec, and write the dated note.
9. **Record** the old and new commit hashes, the reason for the upgrade, what was not adopted, and the verification evidence.

## Dated notes

### Adopted pins

- [2026-10-27 — 06b7b3e → 4f24ce6](2026-10-27-06b7b3e-4f24ce6.md)
- [2026-10-27 — 4f24ce6 → 1963fab](2026-10-27-4f24ce6-1963fab.md)
- [2026-10-29 — 1963fab → ee369f0](2026-10-29-1963fab-ee369f0.md)
- [2026-10-31 — ee369f0 → 2716f78](2026-10-31-ee369f0-2716f78.md) (host cheats; verified with the untested Metal 32023.922 override)
- [2026-11-02 — 2716f78 → 163a9905](2026-11-02-2716f78-163a9905-review.md) (certified Metal 32023.922; real build and manual launch confirmed by the user; EnginePreview launcher retired)

- [2026-11-02 — 163a9905 → 65501fbb](2026-11-02-163a9905-65501fbb-review.md) (Metal 32023.922; AV1, shader/runtime fixes and updated profiles)

- [2026-11-03 — 65501fbb → b64a5ff0](2026-11-03-65501fbb-b64a5ff0-review.md) (certified Wonder build, maintainer-confirmed visible launch and final UI checks)

## Guardrails

- Never patch the engine checkout.
- Never re-pin a commit that has not passed the gate and a real build on this Mac.
- Never expose a diagnostic `DM_*` switch in the main UI just because the engine added it.
- A newer commit is not automatically a tested commit. `4f24ce6` was chosen over `e09ff95` because the latter was a brand-new RomFS streaming feature without SMO validation.

- [2026-11-05 — b64a5ff0 → 4a0551e4](2026-11-05-b64a5ff0-4a0551e4-review.md) (certified Wonder build, maintainer-confirmed visible launch; provisional profiles, build warnings, Home quit)
- [2026-11-06 — 4a0551e4 → 04df08d4](2026-11-06-4a0551e4-04df08d4-review.md) (Ocarina of Time build and play with mods confirmed by the maintainer)
- [2026-11-06 — 04df08d4 → b2d46b86](2026-11-06-04df08d4-b2d46b86-review.md) (Ocarina of Time rebuild and launch confirmed by the maintainer; damaged NUP/dump files mapped to **Some game files are damaged**)
- [2026-11-07 — b2d46b86 → 7fe9fc4d](2026-11-07-b2d46b86-7fe9fc4d-review.md) (0.1.4.1: Ocarina of Time rebuild confirmed by the maintainer without the dotted rows; terrain holes and white blotches fixed upstream)
- [2026-11-07 — 7fe9fc4d → e5f03403](2026-11-07-7fe9fc4d-e5f03403-review.md) (0.1.4.1: Ocarina of Time rebuild confirmed by the maintainer; packages read by their content metas, NSP with keys still to check by hand)
- [2026-11-08 — e5f03403 → bd979ced](2026-11-08-e5f03403-bd979ced-review.md) (0.1.4.1 candidate: Ocarina's foliage no longer flashes white, Pikmin 4 at 60 fps; shaders translate again; awaiting the maintainer's rebuild)

## Maintainer-directed adoption

- [2026-11-09 — bd979ced → 79741184](2026-11-09-bd979ced-79741184-review.md) (0.1.4.2: 71 commits; adopted at the maintainer's explicit request after automated review/gate checks; exact-hash real game build/launch remains unconfirmed).
