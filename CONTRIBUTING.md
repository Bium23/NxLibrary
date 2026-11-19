# Reporting issues and suggestions

Arcane is a macOS game library and launcher. Use [GitHub Issues](https://github.com/Bium23/NxLibrary/issues)
for bug reports, feature suggestions and translation feedback. The maintainer
implements and integrates code changes. Repository collaborators can open
pull requests for maintainer work.

Describe what you expected, what happened, and how to reproduce it. For translation
feedback, include the language, the current wording and a suggested correction.

## Maintainer workflow

Start with [README](README.md), [AGENTS.md](AGENTS.md),
[architecture](docs/how-it-works/architecture.md) and [conventions](docs/working-on-it/conventions.md).

Keep changes small and preserve Play for existing apps. Never patch the user's
nxnative checkout, silently follow upstream main, or bypass the compatibility
gate. Engine upgrades use the [upgrade checklist](docs/history/engine-upgrades/README.md).

Before submitting:

~~~sh
python3 scripts/check_publication.py
python3 -m unittest discover -s Tests/PublicationChecks
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
bash scripts/build_app.sh
codesign --verify --deep --strict "$HOME/Applications/Arcane Dev.app"
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

The shared source is `Sources/NXLibraryCore/Resources/Localizable.xcstrings`. It includes en, it, fr, de, es, pt-BR and zh-Hans. Keep keys stable, preserve every typed placeholder, provide quantity variants, and leave product names, technical identifiers and user-provided content unchanged. Record the language and whether a fluent speaker reviewed the change.

Run `python3 scripts/check_localizations.py` and the publication regressions after editing the catalog. A development build also checks its compiled resources. The initial translations await maintainer validation; no external translation-hosting service is required.
