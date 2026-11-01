# Contributing

NX Library is an early macOS front-end for a pinned upstream nxnative.
Start with [README](README.md), [architecture](docs/architecture.md) and
[AGENTS.md](AGENTS.md).

Keep changes small and preserve Play for existing apps. Never patch the user's
nxnative checkout, silently follow upstream main, or bypass the compatibility
gate. Engine upgrades use the [upgrade checklist](docs/upstream-upgrades/README.md).

Before submitting:

~~~sh
python3 scripts/check_publication.py
python3 -m unittest discover -s Tests/PublicationChecks
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
bash scripts/build_app.sh
codesign --verify --deep --strict "$HOME/Applications/NXLibrary.app"
~~~

Interactive app and game checks are performed manually. Describe which checks
you performed, including the engine/compiler combination and whether the
untested-toolchain override was used. Compilation alone does not verify a game.

Do not include games, keys, extracted content, personal configuration or raw
diagnostic files. Use synthetic fixtures in tests. Review copied diagnostics
before sharing them, and remove anything personal that remains.

Use scripts/release.sh for packaged releases. Publishing is an explicit
maintainer action; the CI only checks the code and does not publish anything.
