#!/usr/bin/env bash
# scripts/build_app.sh [destination.app]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$HOME/Applications/NXLibrary.app}"
CONFIG="${NX_BUILD_CONFIG:-release}"
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
rm -rf "$APP"
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
[ -d "$ROOT/Resources/Selene" ] && cp -R "$ROOT/Resources/Selene" "$APP/Contents/Resources/Selene"
# Python and build tools from scripts/bundle_runtime.sh. Without it, a developer
# build falls back to ~/nxnative/.venv and the PATH tools.
if [ -d "$ROOT/work/Runtime" ]; then
  cp -R "$ROOT/work/Runtime" "$APP/Contents/Resources/Runtime"
else
  echo "note: no work/Runtime; this build uses ~/nxnative/.venv (run scripts/bundle_runtime.sh)"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>NX Library</string>
  <key>CFBundleExecutable</key><string>NXLibrary</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>local.nxlibrary</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>NX Library</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSMultipleInstancesProhibited</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 bium. MIT. Not affiliated with Nintendo.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
