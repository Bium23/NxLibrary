#!/usr/bin/env bash
# scripts/build_dmg.sh [app] — packs a built NX Library into dist/NXLibrary.dmg.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$HOME/Applications/NXLibrary.app}"
OUT="$ROOT/dist/NXLibrary.dmg"

[ -d "$APP" ] || { echo "build_dmg: no app at $APP (run scripts/build_app.sh)" >&2; exit 1; }
[ -d "$APP/Contents/Resources/Runtime" ] || echo "warning: $APP has no bundled runtime" >&2
codesign --verify --deep --strict "$APP"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/nxlibrary-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/NX Library.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$ROOT/dist"
hdiutil create -volname "NX Library" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
echo "Built $OUT ($(du -h "$OUT" | awk '{print $1}'))"
