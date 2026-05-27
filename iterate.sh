#!/bin/bash
# Dylan→WASM dev loop: rebuild the compiler with backend changes, then try
# compiling the `dylan` library to wasm32 bitcode. Reports the next gap.
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OD=$ROOT/opendylan
REL=$ROOT/bootstrap/opendylan-2026.2pre1
export PATH="$OD/Bootstrap.1/bin:$REL/bin:$PATH"
export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig:$PKG_CONFIG_PATH"
cd "$OD"

echo "### [1/2] Rebuilding compiler (incremental)..."
if ! make bootstrap-stage-1 DYLAN_JOBS=8 > _build/rebuild.log 2>&1; then
  echo "COMPILER REBUILD FAILED:"; tail -20 _build/rebuild.log; exit 1
fi
echo "    compiler rebuilt OK ($(grep -c '^Compiling' _build/rebuild.log) libs touched)"

echo "### [2/2] Compiling 'dylan' library -> wasm32-wasi..."
export OPEN_DYLAN_TARGET_PLATFORM=wasm32-wasi
export OPEN_DYLAN_USER_REGISTRIES="$OD/sources/registry"
export OPEN_DYLAN_USER_ROOT="$OD/_build-wasm"
mkdir -p _build-wasm
dylan-compiler -compile dylan > _build-wasm/compile-dylan.log 2>&1 || true
echo "--- result ---"
tail -20 _build-wasm/compile-dylan.log
