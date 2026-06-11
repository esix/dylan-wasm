#!/bin/bash
# Link the `hello` Dylan program into an executable wasm64 module (hello.wasm).
# Lowers each library's bitcode with per-library prefixes (basenames collide
# across libraries), includes only hello's main, and links with the freestanding
# C runtime + shim. Output: opendylan/_build-wasm64/hello.wasm
set -e
SHIM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SHIM/.." && pwd)"
OD="$REPO/opendylan"; RT="$OD/sources/lib/run-time"; BUILD="$OD/_build-wasm64"
GEN="$BUILD/runtime"
WASI="$(brew --prefix wasi-libc)/share/wasi-sysroot"
LLVM="$(brew --prefix llvm)/bin"
WLD="$REPO/bootstrap/opendylan-2026.2pre1/llvm/bin/wasm-ld"
OBJ="$BUILD/exe-obj"; rm -rf "$OBJ"; mkdir -p "$OBJ"

CFLAGS=(--target=wasm64 -ffreestanding -nostdlib -mbulk-memory
  -isystem "$WASI/include/wasm32-wasi" -isystem "$WASI/include"
  -DOPEN_DYLAN_BACKEND_LLVM -DOPEN_DYLAN_PLATFORM_UNIX -DGC_USE_BOEHM -D_WASI_EMULATED_SIGNAL
  -DOPEN_DYLAN_RUNTIME_HEADER='"llvm-wasm64-wasi-runtime.h"'
  -I"$GEN" -I"$RT" -I"$SHIM/fakegc" -mllvm -wasm-enable-sjlj
  -Wno-unknown-attributes -Wno-implicit-function-declaration -O1 -c)

echo "## C runtime + shim (wasm64, freestanding)..."
for f in collector llvm-runtime-init llvm-posix-os llvm-nlx; do
  "$LLVM/clang" "${CFLAGS[@]}" "$RT/$f.c" -o "$OBJ/c__$f.o"
done
"$LLVM/clang" "${CFLAGS[@]}" "$SHIM/wasm-threads.c" -o "$OBJ/c__wasm-threads.o"
"$LLVM/clang" "${CFLAGS[@]}" "$SHIM/libc-shim.c"    -o "$OBJ/c__libc-shim.o"

echo "## Lowering Dylan bitcode (per-library prefix; only hello keeps its main)..."
for L in dylan common-dylan io generic-arithmetic big-integers hello; do
  for bc in "$BUILD"/build/$L/*.bc; do
    base=$(basename "${bc%.bc}")
    # skip the library-level main for everything except the executable (hello)
    if [ "$base" = "_main" ] && [ "$L" != "hello" ]; then continue; fi
    "$LLVM/llc" -mtriple=wasm64-unknown-wasi --enable-emscripten-cxx-exceptions -filetype=obj -O2 "$bc" -o "$OBJ/${L}__${base}.o"
  done
done
"$LLVM/llc" -mtriple=wasm64-unknown-wasi --enable-emscripten-cxx-exceptions -filetype=obj -O2 "$GEN/wasm64-wasi-runtime.bc" -o "$OBJ/generated-runtime.o"

echo "## Linking hello.wasm..."
# 64KB default shadow stack is far too small for the Dylan runtime; give it 32MB.
"$WLD" -mwasm64 --no-entry --export-dynamic --initial-memory=536870912 --max-memory=1073741824 \
  --export=__THREW__ --export=__threwValue --export=tempRet0 --export-table \
  -z stack-size=33554432 \
  "$OBJ"/*.o -o "$BUILD/hello.wasm" 2>/tmp/hello-wld && {
  echo "   *** LINKED: $BUILD/hello.wasm ($(ls -la "$BUILD/hello.wasm"|awk '{print $5}') bytes) ***"
  # Stage the browser harness next to hello.wasm so the user can just serve $BUILD.
  cp "$SHIM/run-hello.html" "$BUILD/run-hello.html"
} || { echo "   diagnostics:"; grep -iE "undefined|error|duplicate" /tmp/hello-wld | sort -u | head -40; }
