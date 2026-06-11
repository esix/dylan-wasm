# dylan-wasm

Compiling [Dylan](https://opendylan.org/) to WebAssembly via Open Dylan's LLVM
back-end.

**Status:** Dylan programs **run in your browser** via wasm64. The included
`hello` showcase — the **upstream Open Dylan `quicksort` and
`towers-of-hanoi` examples, verbatim** — compiles to a ~5.5 MB `.wasm`,
instantiates in Chrome / Firefox, and prints its output through
`host_write`. Full Dylan runtime (GC, generic dispatch, polymorphic +
limited-type method specialization, streams, `format-out`,
**non-local-exit / conditions** via an Emscripten-style EH bridge,
**`random`** seeded from a host clock, **`timing`** macro backed by
`performance.now`) live in the browser. Open `run-hello.html` for the
dashboard, or `examples.html` for the captured output alongside the source.
Two of the three upstream examples run live; only `factorial-big` is still
native-only (needs big-integer overflow handling).

We target **wasm64 / memory64** (64-bit pointers): wasm32's 32-bit pointers tripped
invalid size-dependent bitcasts in Open Dylan's runtime codegen, and wasm64 reuses
its well-tested 64-bit path. memory64 + table64 run in current browsers (Chrome
133+, Firefox 134+). The wasm32 target is left registered for a future fix.

## Layout

Two repos, by design:

- **this meta-repo** — the wasm runtime shim, build orchestration, harnesses,
  the test project, and the **patch** carrying the Open Dylan compiler changes.
- **[`opendylan/`](opendylan) — a git submodule pointing at upstream**
  `dylan-lang/opendylan`, pinned at commit `3b2b904`. `setup.sh` applies
  `patches/opendylan-wasm.patch` to it during build (idempotently), so the
  submodule stays unmodified upstream while our changes live as a tracked diff.

| Path | What |
|---|---|
| `opendylan/` *(submodule, upstream pinned)* | Vanilla Open Dylan @ `3b2b904`. `setup.sh` patches it at build time. Submodule is configured `ignore = dirty` so the patched working tree doesn't appear as "modified content" in `git status`. |
| `patches/opendylan-wasm.patch` | Our compiler changes: WebAssembly (wasm32/wasm64) LLVM back-end targets, default-sections fix, runtime ABI fixes, Apple-Silicon codesign fix, wasm build scripts + registries. |
| `runtime-wasm64/` | Freestanding wasm64 runtime shim + build scripts: `libc-shim.c`, `wasm-threads.c`, `fakegc/gc/gc.h`, `build-wasm64.sh` (link a runtime `.wasm`), `build-hello.sh` (link an executable), `rebuild-all.sh` (full rebuild), `run-hello.html`/`run-hello.mjs` (browser/node harness). |
| `hello/` | Minimal Dylan test program (sources only). |
| `examples.html` | Showcase of native example programs and their output. |
| `setup.sh` | One-command build (bootstrap + apply patch + stage-1 compiler + wasm runtime). |

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

After `./setup.sh`, the submodule's working tree is the patched compiler. Edit
e.g. `opendylan/sources/dfmc/llvm-back-end/llvm-targets.dylan`, run
`runtime-wasm64/rebuild-all.sh`, reload the browser.

Roll your edits back into the patch:

```sh
( cd opendylan && git diff -- \
    sources/dfmc/llvm-back-end \
    sources/jamfiles \
    sources/registry/wasm32-wasi sources/registry/wasm64-wasi \
    sources/lib/run-time/boehm-collector.c ) > patches/opendylan-wasm.patch
git add patches/opendylan-wasm.patch && git commit
```

If you ever want to bump the upstream pin: `cd opendylan && git fetch && git checkout <new-sha>`, re-base the patch onto the new tree (resolve conflicts in `git apply` output), then commit the new submodule SHA here (`git add opendylan`).
