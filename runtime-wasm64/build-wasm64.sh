#!/bin/bash
# Link the Dylan runtime into a wasm64 module.
#
# Compiles the C runtime (freestanding) + our shim, lowers all Dylan/runtime
# bitcode to wasm64 objects, and links with wasm-ld into dylan-runtime.wasm.
# Prereqs: ./iterate-style build already produced the wasm64 bitcode under
# opendylan/_build-wasm64/ (compile the `dylan` library for wasm64-wasi and run
# llvm-runtime-generator dylan.lid wasm64-wasi). See DESIGN.md / README.md.
#
# Pass "probe" to link with --allow-undefined and list missing symbols.
set -e
SHIM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SHIM/.." && pwd)"
OD="$REPO/opendylan"
RT="$OD/sources/lib/run-time"
BUILD="$OD/_build-wasm64"                 # generated bitcode + object output (git-ignored)
GEN="$BUILD/runtime"                       # holds wasm64-wasi-runtime.bc + header
WASI="$(brew --prefix wasi-libc)/share/wasi-sysroot"
LLVM="$(brew --prefix llvm)/bin"           # needs wasm targets (the bundled clang lacks them)
WLD="$REPO/bootstrap/opendylan-2026.2pre1/llvm/bin/wasm-ld"
OBJ="$BUILD/link-obj"
mkdir -p "$OBJ"

# Freestanding wasm64: reuse wasm32-wasi headers for declarations only (-nostdlib);
# wasm64 runtime header; bulk-memory lowers memcpy/memset to wasm instructions.
CFLAGS=(--target=wasm64 -ffreestanding -nostdlib -mbulk-memory
  -isystem "$WASI/include/wasm32-wasi" -isystem "$WASI/include"
  -DOPEN_DYLAN_BACKEND_LLVM -DOPEN_DYLAN_PLATFORM_UNIX -DGC_USE_BOEHM -D_WASI_EMULATED_SIGNAL
  -DOPEN_DYLAN_RUNTIME_HEADER='"llvm-wasm64-wasi-runtime.h"'
  -I"$GEN" -I"$RT" -I"$SHIM/fakegc" -mllvm -wasm-enable-sjlj
  -Wno-unknown-attributes -Wno-implicit-function-declaration -O1 -c)

echo "## Compiling C runtime (wasm64, freestanding)..."
for f in collector llvm-runtime-init llvm-posix-os llvm-nlx; do
  "$LLVM/clang" "${CFLAGS[@]}" "$RT/$f.c" -o "$OBJ/$f.o"
done
"$LLVM/clang" "${CFLAGS[@]}" "$SHIM/wasm-threads.c" -o "$OBJ/wasm-threads.o"
"$LLVM/clang" "${CFLAGS[@]}" "$SHIM/libc-shim.c"    -o "$OBJ/libc-shim.o"

echo "## Lowering Dylan + generated-runtime bitcode to wasm64 objects..."
for bc in "$BUILD"/build/dylan/*.bc "$GEN"/wasm64-wasi-runtime.bc; do
  "$LLVM/llc" -mtriple=wasm64-unknown-wasi -filetype=obj -O2 "$bc" -o "$OBJ/$(basename "${bc%.bc}").o"
done

echo "## Linking with wasm-ld (-mwasm64)..."
LDFLAGS=(-mwasm64 --no-entry --export-dynamic --initial-memory=268435456)
[ "$1" = "probe" ] && LDFLAGS+=(--allow-undefined)
"$WLD" "${LDFLAGS[@]}" "$OBJ"/*.o -o "$BUILD/dylan-runtime.wasm" 2>"$OBJ/wld-err.log" || {
  echo "   LINK FAILED — diagnostics:"
  grep -iE "undefined|error" "$OBJ/wld-err.log" | sort -u | head -60
  exit 1
}
echo "   *** LINKED: $BUILD/dylan-runtime.wasm ($(stat -f%z "$BUILD/dylan-runtime.wasm") bytes) ***"

if [ "${1:-}" = "probe" ]; then
  "$LLVM/llvm-nm" --undefined-only "$BUILD/dylan-runtime.wasm" 2>/dev/null | awk '{print $NF}' | sort -u
fi
