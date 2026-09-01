#!/bin/bash
# Cross-check the C runtime/shim ABI against the Dylan bitcode, both ways.
#
# wasm-ld only signature-checks *direct* calls; anything reached through the
# EH lowering's invoke trampolines is a call_indirect, where a mismatch traps
# at RUNTIME with no link-time warning (this is how the 1-arg io_strerror bug
# shipped). This tool closes that gap mechanically: it disassembles every
# built .bc, emits IR for every C file we link, and compares
#   - functions defined in C vs declared in bitcode (and vice versa)
#   - globals defined in bitcode vs declared extern in C
# normalizing for wasm's i8/i16 -> i32 argument legalization.
#
# Run after changing the shim, the C runtime, or the compiler's primitive
# descriptors:  runtime-wasm64/check-abi.sh   (needs a completed wasm64 build)
set -euo pipefail
SHIM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SHIM/.." && pwd)"
OD="$REPO/opendylan"; RT="$OD/sources/lib/run-time"; BUILD="$OD/_build-wasm64"
GEN="$BUILD/runtime"
WASI="$(brew --prefix wasi-libc)/share/wasi-sysroot"
LLVM="$(brew --prefix llvm)/bin"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

echo "## Disassembling bitcode..."
for bc in "$BUILD"/build/*/*.bc "$GEN"/wasm64-wasi-runtime.bc; do
  "$LLVM/llvm-dis" -o - "$bc" 2>/dev/null
done > "$WORK/bitcode.ll"

echo "## Emitting IR for linked C files..."
CFLAGS=(--target=wasm64 -ffreestanding -nostdlib -mbulk-memory
  -isystem "$WASI/include/wasm32-wasi" -isystem "$WASI/include"
  -DOPEN_DYLAN_BACKEND_LLVM -DOPEN_DYLAN_PLATFORM_UNIX -DGC_USE_BOEHM -D_WASI_EMULATED_SIGNAL
  -DOPEN_DYLAN_RUNTIME_HEADER='"llvm-wasm64-wasi-runtime.h"'
  -I"$GEN" -I"$RT" -I"$SHIM/fakegc" -mllvm -wasm-enable-sjlj
  -Wno-unknown-attributes -Wno-implicit-function-declaration -O0 -S -emit-llvm)
for f in "$RT"/collector.c "$RT"/llvm-runtime-init.c "$RT"/llvm-posix-os.c \
         "$RT"/llvm-nlx.c "$SHIM"/wasm-threads.c "$SHIM"/libc-shim.c; do
  "$LLVM/clang" "${CFLAGS[@]}" "$f" -o "$WORK/$(basename "${f%.c}").ll"
done

echo "## Comparing..."
python3 - "$WORK" <<'PY'
import re, glob, sys
WORK = sys.argv[1]

# Known upstream skews, inherited by native too (C int vs bitcode i64 flags;
# little-endian 0/1 reads make them behave). Reported, but not failures.
ALLOW = {'dylan_keyboard_interruptQ', 'Prunning_under_dylan_debuggerQ'}
# Personality functions are conventionally declared varargs; never called
# through that type.
SKIP_FN = {'__opendylan_personality_v0'}

def norm(t):
    # wasm legalizes sub-32-bit integer args/returns to i32
    return 'i32' if t in ('i1', 'i8', 'i16') else t

def parse_fn(line, kw):
    m = re.match(rf'{kw}\s+(.*?)@([\w.$"]+)\((.*?)\)', line)
    if not m: return None
    pre, name, params = m.groups(); name = name.strip('"')
    toks = [t for t in pre.split() if t not in
            ('dso_local','internal','external','hidden','protected','local_unnamed_addr',
             'unnamed_addr','noundef','zeroext','signext','tail','weak') and not t.startswith('#')]
    ret = norm(toks[-1]) if toks else '?'
    plist, depth, cur = [], 0, ''
    for ch in params:
        if ch in '([<{': depth += 1
        if ch in ')]>}': depth -= 1
        if ch == ',' and depth == 0: plist.append(cur); cur = ''
        else: cur += ch
    if cur.strip(): plist.append(cur)
    pt = tuple('...' if p.strip() == '...' else norm(p.split()[0]) for p in (q.strip() for q in plist) if p)
    return name, ret, pt

def parse_gv(line):
    m = re.match(r'@([\w.$"]+)\s*=\s*(.*?)\bglobal\s+(\S+?),?\s', line + ' ')
    if not m: return None
    name, quals, ty = m.groups()
    return name.strip('"'), quals, ty.rstrip(',')

bc_decl, bc_def, bc_gv = {}, {}, {}
for line in open(f'{WORK}/bitcode.ll'):
    if line.startswith('declare') and '@llvm.' not in line:
        r = parse_fn(line.strip(), 'declare')
        if r: bc_decl.setdefault(r[0], set()).add((r[1], r[2]))
    elif line.startswith('define'):
        r = parse_fn(line.rstrip(' {\n'), 'define')
        if r: bc_def.setdefault(r[0], set()).add((r[1], r[2]))
    elif line.startswith('@'):
        r = parse_gv(line)
        if r and 'external' not in r[1]: bc_gv[r[0]] = r[2]

errors, warns, checked = [], [], 0
for ll in glob.glob(f'{WORK}/*.ll'):
    src = ll.rsplit('/', 1)[-1]
    if src == 'bitcode.ll': continue
    for line in open(ll):
        if line.startswith('define'):
            r = parse_fn(line.rstrip(' {\n'), 'define')
            if not r or r[0] in SKIP_FN or r[0] not in bc_decl: continue
            checked += 1
            for sig in bc_decl[r[0]]:
                if sig != (r[1], r[2]):
                    errors.append(f'{r[0]} [{src}]: C defines {r[1]}({",".join(r[2])}), '
                                  f'bitcode declares {sig[0]}({",".join(sig[1])})')
        elif line.startswith('declare') and '@llvm.' not in line:
            r = parse_fn(line.strip(), 'declare')
            if not r or r[0] in SKIP_FN or r[0] not in bc_def: continue
            checked += 1
            for sig in bc_def[r[0]]:
                if sig != (r[1], r[2]):
                    errors.append(f'{r[0]} [{src}]: C declares {r[1]}({",".join(r[2])}), '
                                  f'bitcode defines {sig[0]}({",".join(sig[1])})')
        elif line.startswith('@'):
            r = parse_gv(line)
            if not r or 'external' not in r[1] or r[0] not in bc_gv: continue
            checked += 1
            cty, bty = r[2], bc_gv[r[0]]
            if cty == bty: continue
            # extern char / extern struct used purely for its address vs a
            # Dylan-typed object: the standard idiom, size never dereferenced
            if (cty == 'i8' or cty.startswith('%')) and bty.startswith('%'): continue
            msg = f'{r[0]} [{src.rsplit("/",1)[-1]}]: C declares {cty}, bitcode defines {bty}'
            (warns if r[0] in ALLOW else errors).append(msg)

for w in warns: print(f'  warn (known upstream skew): {w}')
for e in errors: print(f'  ERROR: {e}')
print(f'--- {checked} cross-boundary symbols checked: '
      f'{len(errors)} errors, {len(warns)} known-skew warnings')
sys.exit(1 if errors else 0)
PY
