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

Record user-visible changes under **Unreleased** in [CHANGELOG.md](CHANGELOG.md).
Keep the description focused on the resulting behaviour. Move entries into a
dated version section when that release is actually published; unreleased work
must not appear as an already available release.

## Interface translations

The shared source is `Sources/NXLibraryCore/Resources/Localizable.xcstrings`. It includes en, it, fr, de, es and pt-BR. Keep keys stable, preserve every typed placeholder, provide quantity variants, and leave product names, technical identifiers and user-provided content unchanged. Translation-only PRs should identify their language and whether a fluent speaker reviewed them.

Run `python3 scripts/check_localizations.py` and the publication regressions after editing the catalog. A development build also checks its compiled resources. The initial translations await maintainer validation; no external translation-hosting service is required.
