#!/usr/bin/env bash
# scripts/build_app.sh [destination.app]
# NX_VERSION sets the app version (default: the version in progress, from the VERSION file); NX_RELEASE=1
# marks a release copy, the only kind that updates itself. scripts/release.sh sets both; a plain build sets
# neither, so a development copy carries the version being worked on and says it is a development build.
# A development copy is "NX Library Dev" (default ~/Applications/NXLibrary Dev.app), the maintainer's test copy,
# beside the released "NX Library" that updates itself. Both keep the bundle ID local.nxlibrary, so they share the
# library, keys and settings, and macOS runs only one of them at a time.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ "${NX_RELEASE:-0}" = "1" ]; then
  NAME="NX Library"
  APP="${1:-$HOME/Applications/NX Library.app}"
else
  NAME="NX Library Dev"
  APP="${1:-$HOME/Applications/NXLibrary Dev.app}"
fi
CONFIG="${NX_BUILD_CONFIG:-release}"
VERSION="${NX_VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
if ! [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]]; then
  echo "error: NX_VERSION must be dotted numbers, got '$VERSION'" >&2
  exit 1
fi
RELEASE_KEY=""
[ "${NX_RELEASE:-0}" = "1" ] && RELEASE_KEY="  <key>NXLibraryRelease</key><true/>"
if [ -z "${DEVELOPER_DIR:-}" ]; then
  if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  elif [ -d "/Applications/Xcode-beta.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
  fi
fi

cd "$ROOT"
swift build -c "$CONFIG" --product NXLibrary

BIN="$ROOT/.build/$CONFIG/NXLibrary"
DESTINATION="$APP"
STAGE="$(mktemp -d "${TMPDIR:-/tmp/}nxlibrary-build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/NXLibrary.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/NXLibrary"

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
for icon in "$ROOT"/Resources/AppIcon-*.png; do
  [ -f "$icon" ] && cp "$icon" "$APP/Contents/Resources/"
done
[ -f "$ROOT/LICENSE" ] && cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
[ -f "$ROOT/NOTICE" ] && cp "$ROOT/NOTICE" "$APP/Contents/Resources/NOTICE"
cp "$ROOT/scripts/validate_update.py" "$APP/Contents/Resources/validate_update.py"
[ -d "$ROOT/Resources/Selene" ] && cp -R "$ROOT/Resources/Selene" "$APP/Contents/Resources/Selene"
# Python and build tools from scripts/bundle_runtime.sh. Without it, a developer
# build falls back to ~/nxnative/.venv and the PATH tools.
if [ -d "$ROOT/work/Runtime" ]; then
  python3 "$ROOT/scripts/check_publication.py" --runtime "$ROOT/work/Runtime"
  cp -R "$ROOT/work/Runtime" "$APP/Contents/Resources/Runtime"
else
  echo "note: no work/Runtime; this build uses ~/nxnative/.venv (run scripts/bundle_runtime.sh)"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>NXLibrary</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>local.nxlibrary</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>LSSupportsGameMode</key><false/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSMultipleInstancesProhibited</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 bium. MIT. Not affiliated with Nintendo.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
$RELEASE_KEY
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
swiftc -I "$ROOT/.build/$CONFIG" "$ROOT/scripts/install_built_app.swift" \
  "$ROOT/.build/$CONFIG/NXLibraryCore.o" -o "$STAGE/install-app"
"$STAGE/install-app" "$APP" "$DESTINATION"
echo "Built $DESTINATION"
