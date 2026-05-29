#!/bin/bash
# One-command setup for the dylan-wasm toolchain.
#
#   1. fetch the bootstrap Open Dylan release (+ patch its Apple-Silicon codesign step)
#   2. init Open Dylan's own submodules
#   3. build the wasm-enabled stage-1 compiler from ./opendylan
#   4. build the wasm64 runtime + hello.wasm
#
# Prereqs (macOS arm64): Homebrew + `brew install autoconf automake libtool
# pkg-config bdw-gc llvm wasi-libc`, and the ./opendylan submodule populated
# (`git submodule update --init --recursive`).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOT_VER=2026.2pre1
PLAT=aarch64-darwin                     # only arm64-darwin prebuilt exists for this prerelease
REL="$ROOT/bootstrap/opendylan-$BOOT_VER"

[ -e "$ROOT/opendylan/configure.ac" ] || {
  echo "ERROR: ./opendylan is empty. Run: git submodule update --init --recursive"; exit 1; }

echo "## [1/4] Bootstrap compiler ($BOOT_VER, $PLAT)..."
if [ ! -x "$REL/bin/dylan-compiler" ]; then
  curl -fsSL -o "$ROOT/od-boot.tar.bz2" \
    "https://github.com/dylan-lang/opendylan/releases/download/$BOOT_VER/opendylan-$BOOT_VER-$PLAT.tar.bz2"
  mkdir -p "$ROOT/bootstrap"; tar xjf "$ROOT/od-boot.tar.bz2" -C "$ROOT/bootstrap"; rm "$ROOT/od-boot.tar.bz2"
fi
# The release's darwin build script runs `strip`, which invalidates the linker's
# ad-hoc signature on Apple Silicon -> freshly built tools are Killed:9 during
# bootstrap. Re-sign after strip. (Same fix is in the source jamfiles on wasm64.)
JAM="$REL/share/opendylan/build-scripts/shared-darwin-build.jam"
if ! grep -q codesign "$JAM"; then
  python3 - "$JAM" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "$(STRIP) -S $(<:Q)\n}"
new = "$(STRIP) -S $(<:Q) &&\n  /usr/bin/codesign -s - -f $(<:Q)\n}"
open(p, "w").write(s.replace(old, new))
PY
  echo "   patched bootstrap codesign step"
fi

echo "## [2/4] Open Dylan submodules..."
git -C "$ROOT/opendylan" submodule update --init --depth 1 >/dev/null

echo "## [3/4] Building stage-1 compiler (with wasm targets)..."
export PATH="$REL/bin:$PATH"
export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
( cd "$ROOT/opendylan" && ./autogen.sh && ./configure --prefix="$ROOT/install" \
    && make bootstrap-stage-1 DYLAN_JOBS="$(sysctl -n hw.ncpu)" )

echo "## [4/4] Building wasm64 runtime + hello.wasm..."
"$ROOT/runtime-wasm64/rebuild-all.sh"

cat <<EOF

Done. To run it:
  ( cd opendylan/_build-wasm64 && python3 -m http.server 8731 ) &
  open http://localhost:8731/run-hello.html      # live wasm dashboard
  open examples.html                              # native examples showcase
EOF
