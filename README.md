# dylan-wasm

Compiling [Dylan](https://opendylan.org/) to WebAssembly via Open Dylan's LLVM
back-end.

**Status:** the **entire Dylan core runtime links into a complete, self-contained
`wasm64` module** (`dylan-runtime.wasm`, ~4 MB, 7,716 functions, 0 undefined
symbols). The pipeline runs end to end: Dylan source → Open Dylan (our wasm back-end)
→ wasm bitcode → `llc` → wasm objects → `wasm-ld` (+ a freestanding C runtime shim)
→ `.wasm`. Not yet *executing* a hello-world (needs `common-dylan`/`io`, an entry
point, and a host harness). See [`DESIGN.md`](DESIGN.md) for architecture, findings,
the wasm32→wasm64 pivot, and roadmap.

We target **wasm64 / memory64** (64-bit pointers): wasm32's 32-bit pointers tripped
invalid size-dependent bitcasts in Open Dylan's runtime codegen, and wasm64 reuses
its well-tested 64-bit path. memory64 runs in current browsers (Firefox 134+,
Chrome 133+) and in node/wasmtime. The wasm32 target is left registered for a future
cast-emission fix.

## What's in this repo

Only our own work — not the large external trees (the Open Dylan clone, bootstrap
toolchain, and all build outputs are git-ignored):

| Path | What |
|---|---|
| `DESIGN.md` | Architecture, recon findings, phased roadmap, gotchas. |
| `patches/opendylan-wasm.patch` | Changes to Open Dylan: wasm32 + wasm64 LLVM targets, an Apple-Silicon `strip`/codesign fix, wasm build scripts, and registries. Against opendylan `3b2b904`. |
| `runtime-wasm64/` | The freestanding wasm64 runtime shim we wrote: `libc-shim.c` (bump allocator, mem ops, hand-written `__multi3`/`__ashlti3`, libc/thread/exception stubs), `wasm-threads.c` (single-threaded thread-primitive stubs), `fakegc/gc/gc.h` (leak-GC), and `build-wasm64.sh` (compile + link to `.wasm`). |
| `hello/` | A minimal Dylan test project (sources only). |
| `iterate.sh` | Dev loop: rebuild compiler → compile `dylan`→wasm → print next gap. |

## Reproducing

Requires macOS arm64 + Homebrew: `autoconf automake libtool pkg-config bdw-gc
llvm wasi-libc`. (System `llvm` is needed because it has the wasm targets — the
toolchain bundled in the release does not.)

```sh
ROOT=$(pwd)

# 1. Bootstrap compiler (only aarch64-darwin build is the 2026.2pre1 prerelease)
curl -fsSL -o od.tar.bz2 \
  https://github.com/dylan-lang/opendylan/releases/download/2026.2pre1/opendylan-2026.2pre1-aarch64-darwin.tar.bz2
mkdir -p bootstrap && tar xjf od.tar.bz2 -C bootstrap

# 2. Open Dylan sources at the patched commit, with submodules
git clone https://github.com/dylan-lang/opendylan.git
git -C opendylan checkout 3b2b904d6738362863a21a78a9da6ed75246c917
git -C opendylan submodule update --init --depth 1
git -C opendylan apply "$ROOT/patches/opendylan-wasm.patch"

# 3. Configure + build the stage-1 compiler (with our wasm targets)
export PATH="$ROOT/bootstrap/opendylan-2026.2pre1/bin:$PATH"
export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig:$PKG_CONFIG_PATH"
( cd opendylan && ./autogen.sh && ./configure --prefix="$ROOT/install" \
    && make bootstrap-stage-1 DYLAN_JOBS=8 )

# 4. Compile the dylan library to wasm64 + generate the wasm64 runtime bitcode
export OPEN_DYLAN_TARGET_PLATFORM=wasm64-wasi
export OPEN_DYLAN_USER_REGISTRIES="$ROOT/opendylan/sources/registry"
export OPEN_DYLAN_USER_ROOT="$ROOT/opendylan/_build-wasm64"
opendylan/Bootstrap.1/bin/dylan-compiler -compile dylan
mkdir -p opendylan/_build-wasm64/runtime && ( cd opendylan/_build-wasm64/runtime &&
  "$ROOT"/opendylan/Bootstrap.1/bin/llvm-runtime-generator \
    "$ROOT"/opendylan/sources/dylan/dylan.lid wasm64-wasi )

# 5. Link the complete runtime module
runtime-wasm64/build-wasm64.sh           # -> opendylan/_build-wasm64/dylan-runtime.wasm
```

Notes: on Apple Silicon the native bootstrap needs the codesign fix in the patch
(`strip` invalidates ad-hoc signatures → built tools get `Killed: 9`). Bitcode can be
inspected with `llvm-dis`; objects with `llc -mtriple=wasm64-unknown-wasi -filetype=obj`.
