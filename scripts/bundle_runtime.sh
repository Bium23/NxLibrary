#!/usr/bin/env bash
# scripts/bundle_runtime.sh — maintainer only.
# Builds work/Runtime from runtime.lock: python-build-standalone CPython, the
# engine's wheels (zbic's GPLv2 source beside them), and Homebrew's zstd and glslangValidator with their
# dylibs, relinked to @loader_path and ad-hoc signed. build_app.sh copies it
# into the app. Follows LumaNX's scripts/bundle_runtime.py (MIT).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="$ROOT/runtime.lock"
WORK="$ROOT/work"
CACHE="$WORK/cache"
STAGE="$WORK/Runtime.staging"
OUT="$WORK/Runtime"

lock() { plutil -extract "$1" raw -o - "$LOCK"; }
fail() { echo "bundle_runtime: $*" >&2; exit 1; }
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

command -v brew >/dev/null || fail "Homebrew is needed on the maintainer's Mac for zstd and glslang."

rm -rf "$STAGE"
mkdir -p "$CACHE" "$STAGE/bin" "$STAGE/lib" "$STAGE/licenses"

# 1. Python, checked against the lock.
PY_URL="$(lock python.url)"
PY_SHA="$(lock python.sha256)"
PY_TAR="$CACHE/$(basename "${PY_URL//%2B/+}")"
if [ ! -f "$PY_TAR" ] || [ "$(sha256 "$PY_TAR")" != "$PY_SHA" ]; then
  curl -fL --retry 3 -o "$PY_TAR.part" "$PY_URL"
  mv "$PY_TAR.part" "$PY_TAR"
fi
[ "$(sha256 "$PY_TAR")" = "$PY_SHA" ] || { rm -f "$PY_TAR"; fail "Python tarball does not match runtime.lock."; }

# 2. Extract (the tarball's top folder is python/).
tar -xzf "$PY_TAR" -C "$STAGE"
PY="$STAGE/python/bin/python3"
[ -x "$PY" ] || fail "no python/bin/python3 in the tarball."
STDLIB="$STAGE/python/lib/python3.14"
SITE="$STDLIB/site-packages"

# 3. Trim.
rm -rf "$STDLIB/test" "$STDLIB/idlelib" "$STDLIB/tkinter" "$STDLIB/ensurepip"

# 4. Wheels, by URL and hash only.
REQS="$WORK/requirements.txt"
: > "$REQS"
i=0
while plutil -extract "wheels.$i" json -o /dev/null "$LOCK" 2>/dev/null; do
  echo "$(lock wheels.$i.name) @ $(lock wheels.$i.url) --hash=sha256:$(lock wheels.$i.sha256)" >> "$REQS"
  i=$((i + 1))
done
[ "$i" -gt 0 ] || fail "runtime.lock lists no wheels."
"$PY" -I -m pip install --disable-pip-version-check --no-deps --no-compile --require-hashes \
  --only-binary=:all: --target "$SITE" -r "$REQS"
# The runtime is read-only: no pip inside it.
rm -rf "$SITE"/pip "$SITE"/pip-*.dist-info "$STAGE"/python/bin/pip*

# 4b. Source of the GPL wheels (zbic), shipped beside them as GPLv2 section 3(a) asks.
mkdir -p "$STAGE/sources"
i=0
while plutil -extract "sources.$i" json -o /dev/null "$LOCK" 2>/dev/null; do
  src="$CACHE/$(lock sources.$i.file)"
  if [ ! -f "$src" ] || [ "$(sha256 "$src")" != "$(lock sources.$i.sha256)" ]; then
    curl -fL --retry 3 -o "$src.part" "$(lock sources.$i.url)"
    mv "$src.part" "$src"
  fi
  [ "$(sha256 "$src")" = "$(lock sources.$i.sha256)" ] || { rm -f "$src"; fail "$(lock sources.$i.file) does not match runtime.lock."; }
  cp "$src" "$STAGE/sources/"
  i=$((i + 1))
done

# 5. Homebrew tools, at the locked versions.
rm -f "$WORK/origins.txt.tmp"
i=0
while plutil -extract "brew.$i" json -o /dev/null "$LOCK" 2>/dev/null; do
  formula="$(lock brew.$i.formula)"
  version="$(lock brew.$i.version)"
  binary="$(lock brew.$i.binary)"
  installed="$(brew list --versions "$formula" | awk '{print $2}')"
  case "$installed" in
    "$version"|"$version"_*) ;;
    *) fail "$formula is $installed, runtime.lock wants $version." ;;
  esac
  src="$(brew --prefix "$formula")/bin/$binary"
  [ -e "$src" ] || fail "missing $src"
  cp "$(readlink -f "$src")" "$STAGE/bin/$binary"
  chmod 755 "$STAGE/bin/$binary"
  echo "$binary $(readlink -f "$src")" >> "$WORK/origins.txt.tmp"
  i=$((i + 1))
done
mv "$WORK/origins.txt.tmp" "$WORK/origins.txt"

# 6–7. Relink every non-system dependency into lib/, then ad-hoc sign.
"$PY" -I "$ROOT/scripts/relink_macho.py" "$STAGE" "$WORK/origins.txt"
rm -f "$WORK/origins.txt"

# 8. Licences.
cp "$STAGE/python/lib/python3.14/LICENSE.txt" "$STAGE/licenses/python-PSF.txt" 2>/dev/null \
  || cp "$STAGE/python/LICENSE"* "$STAGE/licenses/python-PSF.txt" 2>/dev/null \
  || fail "no Python licence in the tarball."
for dist in "$SITE"/*.dist-info; do
  name="$(basename "$dist" .dist-info)"
  for file in "$dist"/LICENSE* "$dist"/licenses/*; do
    [ -f "$file" ] && cp "$file" "$STAGE/licenses/$name-$(basename "$file")"
  done
done
for formula in zstd glslang spirv-tools xz lz4; do
  prefix="$(brew --prefix "$formula")"
  for file in "$prefix"/LICENSE* "$prefix"/COPYING*; do
    [ -f "$file" ] && cp "$file" "$STAGE/licenses/$formula-$(basename "$file")"
  done
done

cat > "$STAGE/versions.json" <<JSON
{
  "python": "$(lock python.version)",
  "capstone": "$(lock wheels.0.version)",
  "lz4": "$(lock wheels.1.version)",
  "fonttools": "$(lock wheels.2.version)",
  "zbic": "$(lock wheels.3.version)",
  "zstd": "$(lock brew.0.version)",
  "glslang": "$(lock brew.1.version)",
  "lock": "$(sha256 "$LOCK")"
}
JSON

# 9. Audit.
STAMP="$WORK/audit.stamp"
touch "$STAMP"
sleep 1
while IFS= read -r -d '' file; do
  if file -b "$file" | grep -q "Mach-O"; then
    if otool -L "$file" | tail -n +2 | grep -qE "/opt/homebrew|/usr/local"; then
      fail "audit: $file still links Homebrew."
    fi
  fi
done < <(find "$STAGE" -type f -print0)
"$PY" -I -B -c "import capstone, lz4.block, fontTools, zbic; assert capstone.cs_version()[0] == 5; assert zbic.decompress(zbic.compress(b'nx')) == b'nx'" \
  || fail "audit: the Python packages do not import."
env -i PATH=/usr/bin:/bin "$STAGE/bin/zstd" --version >/dev/null || fail "audit: zstd does not run."
env -i PATH=/usr/bin:/bin "$STAGE/bin/glslangValidator" --version >/dev/null || fail "audit: glslangValidator does not run."
[ -z "$(find "$STAGE" -name '*.pyc' -newer "$STAMP")" ] || fail "audit: the import wrote .pyc files."
rm -f "$STAMP"

# 10. Swap in.
rm -rf "$OUT.old"
[ -d "$OUT" ] && mv "$OUT" "$OUT.old"
mv "$STAGE" "$OUT"
rm -rf "$OUT.old"
echo "Runtime ready: $OUT ($(du -sh "$OUT" | awk '{print $1}'))"
