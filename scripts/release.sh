#!/usr/bin/env bash
# scripts/release.sh <version> [--publish --notes <file>]
#
# Builds a release copy of NX Library (version in its plist, NXLibraryRelease marker, bundled
# runtime), verifies its signature and zips it as work/release/NXLibrary-<version>.zip, the asset
# the app's updater looks for, plus work/release/NXLibrary-<version>.dmg for a first install (the
# DMG must hold the release copy, or that install would never update itself). Nothing leaves
# this Mac unless --publish is given: then the tag v<version> is pushed and a GitHub release is
# created with both files (GitHub computes the zip's digest, which the app checks).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

usage() { echo "usage: scripts/release.sh <version> [--publish --notes <file>]" >&2; exit 2; }

VERSION="${1:-}"
[ -n "$VERSION" ] || usage
shift
PUBLISH=0
NOTES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --publish) PUBLISH=1 ;;
    --notes) shift; NOTES="${1:-}" ;;
    *) usage ;;
  esac
  shift
done

fail() { echo "error: $*" >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || fail "the version must be dotted numbers, like 0.2.0"
TAG="v$VERSION"
if [ "$PUBLISH" = "1" ]; then
  [ -n "$NOTES" ] && [ -f "$NOTES" ] || fail "--publish needs --notes <file> with the release notes"
  command -v gh >/dev/null || fail "--publish needs the GitHub CLI (gh)"
fi
[ -z "$(git status --porcelain)" ] || fail "the working tree has changes; commit or stash them first"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then fail "the tag $TAG already exists"; fi
[ -d "$ROOT/work/Runtime" ] || fail "no work/Runtime: run scripts/bundle_runtime.sh first (a release carries its Python and tools)"

# What this release needs on a player's Mac, as a hidden line in its notes (AppUpdate.requirements(in:)): the
# update dialog warns about an Xcode to update first and the engine Setup downloads after the restart.
MIN_XCODE="$(sed -n 's/.*minimumXcode: "\([0-9.]*\)".*/\1/p' "$ROOT/Sources/NXLibraryCore/Models/ToolchainRequirements.swift" | head -1)"
ENGINE="$(sed -n 's/.*public let pinnedEngineCommit = "\([0-9a-f]\{40\}\)".*/\1/p' "$ROOT/Sources/NXLibrary/ViewModels/AppViewModel.swift" | head -1)"
[ -n "$MIN_XCODE" ] && [ -n "$ENGINE" ] || fail "could not read minimumXcode or pinnedEngineCommit from the sources"
REQUIRES="<!-- nxlibrary-requires xcode=$MIN_XCODE engine=$ENGINE -->"
echo "Requires: Xcode $MIN_XCODE, nxnative ${ENGINE:0:7}"

OUT="$ROOT/work/release"
APP="$OUT/NXLibrary.app"
ZIP="$OUT/NXLibrary-$VERSION.zip"
rm -rf "$OUT"
mkdir -p "$OUT"

NX_VERSION="$VERSION" NX_RELEASE=1 bash "$ROOT/scripts/build_app.sh" "$APP"
codesign --verify --deep --strict "$APP"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$VERSION" ] \
  || fail "the built app does not carry version $VERSION"
[ "$(/usr/libexec/PlistBuddy -c 'Print :NXLibraryRelease' "$APP/Contents/Info.plist")" = "true" ] \
  || fail "the built app is not marked as a release"

ditto -c -k --keepParent "$APP" "$ZIP"
echo "Zip: $ZIP"
echo "SHA-256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
DMG="$OUT/NXLibrary-$VERSION.dmg"
bash "$ROOT/scripts/build_dmg.sh" "$APP"
mv "$ROOT/dist/NXLibrary.dmg" "$DMG"
echo "DMG: $DMG"

if [ "$PUBLISH" = "1" ]; then
  git tag "$TAG"
  git push origin "$TAG"
  { cat "$NOTES"; printf '\n\n%s\n' "$REQUIRES"; } > "$OUT/notes.md"
  gh release create "$TAG" "$ZIP" "$DMG" --title "NX Library $VERSION" --notes-file "$OUT/notes.md"
  echo "Published $TAG"
else
  echo "Not published (add --publish --notes <file> to create the GitHub release)."
fi
