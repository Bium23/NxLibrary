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
2. **Read the contract surface**, not only commit subjects:
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
5. **Integrate new engine flags** in `BuildCommandBuilder` (or the relevant service) and add a unit test. Do not leave an engine gate or override without a caller.
6. **Verify**:
   - full unit tests;
   - app rebuilt, signed, installed;
   - compatibility gate green (or an explicit recorded override);
   - one real certified build, including the pipeline archive stage;
   - smoke launch to a visible screen.
7. **Re-pin** `AppViewModel.pinnedEngineCommit`, invalidate the cached upstream status, update `README.md` and the design spec, and write the dated note.
8. **Record** the old and new commit hashes, the reason for the upgrade, what was not adopted, and the verification evidence.

## Dated notes

- [2026-10-27 — 06b7b3e → 4f24ce6](2026-10-27-06b7b3e-4f24ce6.md)

## Guardrails

- Never patch the engine checkout.
- Never re-pin a commit that has not passed the gate and a real build on this Mac.
- Never expose a diagnostic `DM_*` switch in the main UI just because the engine added it.
- A newer commit is not automatically a tested commit. `4f24ce6` was chosen over `e09ff95` because the latter was a brand-new RomFS streaming feature without SMO validation.
