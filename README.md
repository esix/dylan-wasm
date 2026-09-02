# dylan-wasm

Compiling [Dylan](https://opendylan.org/) to WebAssembly via Open Dylan's LLVM
back-end.

**Status:** Dylan programs **run in your browser** via wasm64. The included
`hello` showcase — **all three upstream Open Dylan examples
(`quicksort`, `towers-of-hanoi`, `factorial-big`) verbatim**, plus an ASCII
**mandelbrot**, a **sin/cos wave** through the host-bridged libm, and a
**generic-dispatch shapes** demo — compiles to a ~5.7 MB `.wasm`,
instantiates in Chrome / Firefox / node ≥ 24, and prints its output through
`host_write`. Full Dylan runtime (GC, generic dispatch, streams,
`format-out`, **non-local-exit / conditions** via an Emscripten-style EH
bridge, **`random`** seeded from a host clock, **`timing`** macro backed by
`performance.now`, real **128-bit `<double-integer>` arithmetic** with
overflow raising a real `<arithmetic-overflow-error>`) live in the browser.
Open `run-hello.html` for the dashboard, or `examples.html` for the
captured output alongside the source.

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
| `patches/opendylan-wasm.patch` | Our compiler changes: WebAssembly (wasm32/wasm64) LLVM back-end targets, default-sections fix, runtime ABI fixes, Apple-Silicon codesign fix, wasm build scripts + registries. Regenerate after editing the submodule with `patches/regen-patch.sh`. |
| `runtime-wasm64/` | Freestanding wasm64 runtime shim + build scripts: `libc-shim.c`, `wasm-threads.c`, `fakegc/gc/gc.h`, `build-wasm64.sh` (link a runtime `.wasm`), `build-hello.sh` (link an executable), `rebuild-all.sh` (full rebuild), `run-hello.html`/`run-hello.mjs` (browser/node harness), `ff-probe.html` (synchronous harness for `firefox --headless --screenshot` verification), `check-abi.sh` (C↔bitcode signature cross-check). |
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
python3 -m http.server 8731 &                    # serve from the repo root
open http://localhost:8731/examples.html         # showcase incl. the live wasm card
open http://localhost:8731/opendylan/_build-wasm64/run-hello.html   # boot dashboard
```

(Serve from the repo root: `examples.html`'s live card fetches
`opendylan/_build-wasm64/hello.wasm` relative to it, and browsers won't fetch
wasm over `file://`.)

Or without a browser (**node ≥ 24**; older V8s implement an earlier memory64
draft and reject the module's table64 encoding):

```sh
node runtime-wasm64/run-hello.mjs
```

Dev loop after editing the compiler (`opendylan/sources/...`): `runtime-wasm64/rebuild-all.sh`.

## Modifying the compiler

After `./setup.sh`, the submodule's working tree is the patched compiler. Edit
e.g. `opendylan/sources/dfmc/llvm-back-end/llvm-targets.dylan`, run
`runtime-wasm64/rebuild-all.sh`, reload the browser.

After touching the C shim, the C runtime, or primitive descriptors, also run
`runtime-wasm64/check-abi.sh`: it cross-checks every C↔bitcode function and
global signature. This matters because wasm-ld only checks *direct* calls —
anything reached via the EH lowering's `invoke_*` trampolines is a
`call_indirect`, where a signature mismatch traps at runtime with no
link-time warning.

Roll your edits back into the patch:

```sh
patches/regen-patch.sh        # regenerates patches/opendylan-wasm.patch
git add patches/opendylan-wasm.patch && git commit
```

(Don't hand-roll a `git diff` for this: the patch also carries files that are
*untracked* in the submodule — the wasm jamfiles and registries — which a plain
`git diff <paths>` silently drops. The script stages them with `git add -N`
first, and covers every path the patch touches, including
`sources/dfmc/modeling/objects.dylan`.)

If you ever want to bump the upstream pin: `cd opendylan && git fetch && git checkout <new-sha>`, re-base the patch onto the new tree (resolve conflicts in `git apply` output), then commit the new submodule SHA here (`git add opendylan`).
