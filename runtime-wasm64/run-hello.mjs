// Host harness to run the Dylan hello-world wasm64 module under node.
// Provides the env.host_write import (output path) and drives the init sequence.
// Run: node --experimental-wasm-memory64 run-hello.mjs <hello.wasm>
import { readFileSync } from 'node:fs';

const path = process.argv[2] ||
  new URL('../opendylan/_build-wasm64/hello.wasm', import.meta.url).pathname;
const bytes = readFileSync(path);

let memory;
const dec = new TextDecoder();

const imports = {
  env: {
    // long host_write(int fd, const void *buf, unsigned long count)
    // memory64: pointer/size args arrive as BigInt; return BigInt (i64).
    host_write(fd, ptr, len) {
      const p = Number(ptr), n = Number(len);
      const s = dec.decode(new Uint8Array(memory.buffer, p, n));
      (fd === 2 ? process.stderr : process.stdout).write(s);
      return BigInt(n);
    },
  },
};

const { instance } = await WebAssembly.instantiate(bytes, imports);
const e = instance.exports;
memory = e.memory;

console.error('[harness] exports:', Object.keys(e).filter(k =>
  /^(memory|main|_Init_Run_Time|__wasm_call_ctors)$/.test(k)).join(', '));

try {
  e.__wasm_call_ctors?.();
  e._Init_Run_Time?.();
  const rc = e.main?.(0, 0n);
  console.error('[harness] main returned:', rc);
} catch (err) {
  console.error('[harness] trap:', err.message);
  process.exitCode = 1;
}
