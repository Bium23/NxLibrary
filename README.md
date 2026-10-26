# NX Library

Personal, native macOS front-end for [nxnative](https://github.com/seedds/nxnative). It turns the user's own Nintendo Switch dumps into self-contained Mac apps and launches them from a console-style library.

**Status:** design phase. The validated design is in [docs/superpowers/specs/2026-10-26-nxlibrary-design.md](docs/superpowers/specs/2026-10-26-nxlibrary-design.md).

- **Engine:** upstream nxnative, MIT, pinned to commit `06b7b3e56303bc67213a98cae61925f9253bdf89`.
- **UI base:** [NxNative Launcher](https://github.com/rennan101/nxnative_Launcher), MIT, commit `5687d647`; GUI only, no engine fork and no engine patches.
- **Scope:** personal use on one Apple-silicon Mac; no game data, keys, or Nintendo assets are included; not affiliated with Nintendo.
