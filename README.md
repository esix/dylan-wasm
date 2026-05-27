# dylan-wasm

Compiling [Dylan](https://opendylan.org/) to WebAssembly via Open Dylan's LLVM
back-end.

**Status:** Phase 1 codegen works — the `dylan` core library compiles to wasm32
bitcode (`target triple = wasm32-unknown-wasi`) and lowers via `llc` to a real
WebAssembly object. Not yet runnable (the C runtime still needs cross-compiling —
Phase 2). See [`DESIGN.md`](DESIGN.md) for the full architecture, findings, and
roadmap.

## What's in this repo

This repo holds **only our own work**, not the large external trees:

| Path | What |
|---|---|
| `DESIGN.md` | Architecture, recon findings, phased roadmap, gotchas. |
| `patches/opendylan-wasm32.patch` | Our changes to Open Dylan (the wasm32 target, an Apple-Silicon codesign fix, a wasm build script, and a registry). |
| `hello/` | A minimal Dylan test project (sources only). |
| `iterate.sh` | Dev loop: rebuild compiler → compile `dylan`→wasm → print next gap. |

The Open Dylan source clone (`opendylan/`), the bootstrap release toolchain
(`bootstrap/`), and build outputs are git-ignored.

## Reproducing the build environment

Requires macOS arm64, Homebrew (`autoconf automake libtool pkg-config bdw-gc`),
and an LLVM with wasm targets.

```sh
ROOT=$(pwd)

# 1. Bootstrap compiler (only aarch64-darwin build is the 2026.2pre1 prerelease)
curl -fsSL -o od.tar.bz2 \
  https://github.com/dylan-lang/opendylan/releases/download/2026.2pre1/opendylan-2026.2pre1-aarch64-darwin.tar.bz2
mkdir -p bootstrap && tar xjf od.tar.bz2 -C bootstrap

# 2. Open Dylan sources at the commit our patch targets, with submodules
git clone https://github.com/dylan-lang/opendylan.git
git -C opendylan checkout 3b2b904d6738362863a21a78a9da6ed75246c917
git -C opendylan submodule update --init --depth 1

# 3. Apply our changes
git -C opendylan apply "$ROOT/patches/opendylan-wasm32.patch"

# 4. Configure + build the stage-1 compiler
export PATH="$ROOT/bootstrap/opendylan-2026.2pre1/bin:$PATH"
export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig:$PKG_CONFIG_PATH"
( cd opendylan && ./autogen.sh && ./configure --prefix="$ROOT/install" \
    && make bootstrap-stage-1 DYLAN_JOBS=8 )

# 5. Compile the dylan library to wasm32 (or just run ./iterate.sh)
./iterate.sh
```

The emitted bitcode lands in `opendylan/_build-wasm/build/dylan/*.bc`; verify with
`llvm-dis < file.bc | head` and `llc -mtriple=wasm32-unknown-wasi -filetype=obj`.
