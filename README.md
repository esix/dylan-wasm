# dylan-wasm

Compiling [Dylan](https://opendylan.org/) to WebAssembly via Open Dylan's LLVM
back-end.

**Status:** the Dylan runtime **compiles to wasm64 and boots in a browser** — a
`hello` module (~5.4 MB) instantiates and executes its own runtime (GC, library
init, generic dispatch) up to one remaining blocker in base-runtime init
(`_Init_dylan_`, boot-symbol setup). Open it with `run-hello.html` for a live
status dashboard. Native builds of real programs (quicksort, factorial,
towers-of-hanoi) run fully — see `examples.html`. Full story, the wasm32→wasm64
pivot, and the remaining blocker are in [`DESIGN.md`](DESIGN.md).

We target **wasm64 / memory64** (64-bit pointers): wasm32's 32-bit pointers tripped
invalid size-dependent bitcasts in Open Dylan's runtime codegen, and wasm64 reuses
its well-tested 64-bit path. memory64 + table64 run in current browsers (Chrome
133+, Firefox 134+). The wasm32 target is left registered for a future fix.

## Layout

Two repos, by design:

- **this meta-repo** — the wasm runtime shim, build orchestration, harnesses,
  docs, and a test project. It does *not* vendor Open Dylan.
- **[`opendylan/`](opendylan) — a git submodule** pointing at our **fork** of
  Open Dylan on the `wasm64` branch, which carries the compiler changes (the
  WebAssembly LLVM targets + runtime/build support) as real commits on top of
  upstream `3b2b904`. This is what you edit to modify the compiler.

| Path | What |
|---|---|
| `opendylan/` *(submodule)* | Open Dylan fork, `wasm64` branch — the compiler. Edit here to change codegen. |
| `runtime-wasm64/` | Freestanding wasm64 runtime shim + build scripts: `libc-shim.c`, `wasm-threads.c`, `fakegc/gc/gc.h`, `build-wasm64.sh` (link a runtime `.wasm`), `build-hello.sh` (link an executable), `rebuild-all.sh` (full rebuild), `run-hello.html`/`run-hello.mjs` (browser/node harness). |
| `hello/` | Minimal Dylan test program (sources only). |
| `examples.html` | Showcase of native example programs and their output. |
| `setup.sh` | One-command build (bootstrap + stage-1 compiler + wasm runtime). |
| `patches/opendylan-wasm.patch` | The compiler changes as a flat diff (generated from the fork) for review / non-submodule use. |
| `DESIGN.md` | Architecture, findings, gotchas, roadmap. |

Git-ignored: `bootstrap/` (downloaded toolchain), `*.tar.bz2`, all `_build*` outputs.

## Build it

Prereqs (macOS arm64) + Homebrew:
`brew install autoconf automake libtool pkg-config bdw-gc llvm wasi-libc`.
(System `llvm` is required — it has the wasm targets; the bundled toolchain doesn't.)

```sh
git clone --recursive <this-repo-url> dylan-wasm
cd dylan-wasm
./setup.sh          # downloads bootstrap, builds the stage-1 compiler + wasm runtime
```

Then:

```sh
( cd opendylan/_build-wasm64 && python3 -m http.server 8731 ) &
open http://localhost:8731/run-hello.html
```

Dev loop after editing the compiler (`opendylan/sources/...`): `runtime-wasm64/rebuild-all.sh`.

## Modifying the compiler

The compiler lives in the `opendylan/` submodule on the `wasm64` branch. Edit
e.g. `opendylan/sources/dfmc/llvm-back-end/llvm-targets.dylan`, run
`runtime-wasm64/rebuild-all.sh`, reload the browser. Commit inside `opendylan/`
to your fork; then `git add opendylan` here to record the new submodule commit.

### One-time fork + submodule setup (maintainer)

The submodule must point at a fork (upstream can't hold our commits). To create it:

```sh
# 1. fork dylan-lang/opendylan on GitHub (web UI or: gh repo fork dylan-lang/opendylan)
# 2. push our prepared wasm64 branch (already committed in ./opendylan):
git -C opendylan remote add fork git@github.com:<you>/opendylan.git
git -C opendylan push fork wasm64
# 3. wire it as the submodule of this repo (-f overrides the placeholder
#    /opendylan/ .gitignore entry; remove that line afterwards):
git submodule add -f -b wasm64 git@github.com:<you>/opendylan.git opendylan
git commit -m "Add opendylan fork (wasm64) as submodule"
```
