#!/bin/bash
# Full wasm64 rebuild after a backend change: recompile the compiler, then
# re-emit all libraries + the runtime, then relink hello.wasm.
set -e
SHIM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SHIM/.." && pwd)"
OD="$REPO/opendylan"; REL="$REPO/bootstrap/opendylan-2026.2pre1"
export PATH="$OD/Bootstrap.1/bin:$REL/bin:$PATH"
export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig:$PKG_CONFIG_PATH"

echo "## [1/4] Rebuilding compiler..."
( cd "$OD" && make bootstrap-stage-1 DYLAN_JOBS=8 ) > "$OD/_build/rebuild-tls.log" 2>&1 || { tail -20 "$OD/_build/rebuild-tls.log"; exit 1; }
echo "    ok"

export OPEN_DYLAN_TARGET_PLATFORM=wasm64-wasi
export OPEN_DYLAN_USER_REGISTRIES="$OD/sources/registry:$REPO/hello/registry"
export OPEN_DYLAN_USER_ROOT="$OD/_build-wasm64"

echo "## [2/4] Recompiling dylan, common-dylan, io, hello -> wasm64..."
for L in dylan common-dylan io hello; do
  dylan-compiler -compile "$L" > "$OD/_build-wasm64/recompile-$L.log" 2>&1
  echo "    $L: $(tail -1 "$OD/_build-wasm64/recompile-$L.log")"
done

echo "## [3/4] Regenerating wasm64 runtime bitcode..."
( cd "$OD/_build-wasm64/runtime" &&
  "$OD/Bootstrap.1/bin/llvm-runtime-generator" "$OD/sources/dylan/dylan.lid" wasm64-wasi ) >/dev/null 2>&1
echo "    regenerated"

echo "## [4/4] Linking hello.wasm..."
"$SHIM/build-hello.sh" | tail -2
