#!/bin/bash
# Regenerate patches/opendylan-wasm.patch from the opendylan/ working tree.
#
# A plain `git diff <paths>` misses the patch's NEW files (the wasm jamfiles
# and registries are untracked in the submodule), so this stages them with
# intent-to-add (`git add -N`) first, diffs, then restores the index.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OD="$ROOT/opendylan"
OUT="$ROOT/patches/opendylan-wasm.patch"

# New files carried by the patch (untracked in the submodule).
NEW=(sources/jamfiles/wasm32-wasi-build.jam
     sources/jamfiles/wasm64-wasi-build.jam
     sources/registry/wasm32-wasi
     sources/registry/wasm64-wasi)

# Everything the patch may touch. Deliberately broad (whole directories), so
# a compiler edit in a new file under these roots is never silently dropped.
PATHS=(sources/dfmc
       sources/jamfiles/Makefile.in
       sources/jamfiles/shared-darwin-build.jam
       "${NEW[@]}"
       sources/lib/run-time)

cd "$OD"
git add -N -- "${NEW[@]}"
trap 'git reset -q -- "${NEW[@]}"' EXIT
git diff -- "${PATHS[@]}" > "$OUT"

echo "Wrote $OUT ($(grep -c '^diff --git' "$OUT") files)."
echo "Review with: git -C \"$ROOT\" diff -- patches/opendylan-wasm.patch"
