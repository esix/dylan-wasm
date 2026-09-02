#!/bin/bash
# Verify every harness satisfies the module's env imports.
#
# There are FOUR harnesses (run-hello.html, run-hello.mjs, ff-probe.html, and
# examples.html's inline live card). A host import added to the shim but not
# to every harness is an instantiation-time LinkError only on the pages that
# were missed — twice now a harness went stale this way. This parses the
# import section of the linked .wasm and checks each harness names every
# import. invoke_* trampolines are exempt per-name, but each harness must
# contain the dynamic-synthesis loop that provides them.
#
# Usage: check-harness-imports.sh [hello.wasm]   (default: the built one)
set -euo pipefail
SHIM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SHIM/.." && pwd)"
WASM="${1:-$REPO/opendylan/_build-wasm64/hello.wasm}"

python3 - "$WASM" "$SHIM/run-hello.html" "$SHIM/run-hello.mjs" \
            "$SHIM/ff-probe.html" "$REPO/examples.html" <<'PY'
import sys

def leb(buf, i):
    r = s = 0
    while True:
        b = buf[i]; i += 1
        r |= (b & 0x7f) << s; s += 7
        if not b & 0x80: return r, i

def imports(path):
    buf = open(path, 'rb').read()
    assert buf[:4] == b'\0asm', 'not a wasm module'
    i, names = 8, []
    while i < len(buf):
        sid = buf[i]; i += 1
        size, i = leb(buf, i)
        if sid != 2:
            i += size; continue
        count, j = leb(buf, i)
        for _ in range(count):
            n, j = leb(buf, j); mod  = buf[j:j+n].decode(); j += n
            n, j = leb(buf, j); name = buf[j:j+n].decode(); j += n
            kind = buf[j]; j += 1
            if kind == 0:                       # func: typeidx
                _, j = leb(buf, j)
            elif kind == 1:                     # table: reftype + limits
                j += 1; flags = buf[j]; j += 1
                _, j = leb(buf, j)
                if flags & 1: _, j = leb(buf, j)
            elif kind == 2:                     # memory: limits
                flags = buf[j]; j += 1
                _, j = leb(buf, j)
                if flags & 1: _, j = leb(buf, j)
            elif kind == 3:                     # global: valtype + mut
                j += 2
            if mod == 'env': names.append(name)
        i += size
    return names

wasm, *harnesses = sys.argv[1:]
need = imports(wasm)
fixed = [n for n in need if not n.startswith('invoke_')]

def provides(src, name):
    if name in src: return True
    # the math-import idiom constructs names: for (f of ['sin',...]) env['host_'+f]=Math[f]
    if name.startswith('host_') and "host_' + f" in src and f"'{name[5:]}'" in src:
        return True
    return False

bad = False
for h in harnesses:
    src = open(h).read()
    missing = [n for n in fixed if not provides(src, n)]
    if any(n.startswith('invoke_') for n in need) and "startsWith('invoke_')" not in src:
        missing.append('<dynamic invoke_* synthesis loop>')
    if missing:
        bad = True
        print(f"  ERROR {h.rsplit('/',1)[-1]}: missing {', '.join(missing)}")
print(f"--- {len(need)} env imports ({len(fixed)} named + invoke_*) "
      f"checked against {len(harnesses)} harnesses: {'FAIL' if bad else 'ok'}")
sys.exit(1 if bad else 0)
PY
