// Node harness for the Dylan hello showcase (wasm64). Mirrors run-hello.html:
// output via env.host_write, the Emscripten-style EH bridge (host_throw +
// invoke_* + __cxa_find_matching_catch_*), a host clock, and argv wiring.
//
// Needs node >= 24: earlier V8s implement an older memory64 draft and reject
// this module's table64 encoding at compile time.
//
// Run: node run-hello.mjs [path/to/hello.wasm] [program args...]
import { readFileSync } from 'node:fs';

const argv = process.argv.slice(2);
const wasmPath = (argv[0] && !argv[0].startsWith('-')) ? argv.shift()
  : new URL('../opendylan/_build-wasm64/hello.wasm', import.meta.url).pathname;
const args = ['hello', ...(argv.length ? argv : ['50000'])];

let memory, instance;
const dec = new TextDecoder();

// EH bridge state (see run-hello.html for the full story: Dylan conditions
// raise through host_throw -> a JS throw; the lowered invoke_* wrappers catch
// it, set __THREW__, and the landingpad code asks __cxa_find_matching_catch_*
// for the exception + selector).
let threwAddr = 0, tempRet0Addr = 0;
let jsThrewValue = 0n;
class DylanThrow extends Error { constructor(exc) { super('dylan'); this.exc = exc; } }
function makeInvoke(name) {
  const isVoid = (name[7] === 'v');          // invoke_v… returns void
  return function (...all) {
    // wasm64: the function-table index arrives as a BigInt and must stay one.
    const [idx, ...rest] = all;
    try {
      return instance.exports.__indirect_function_table.get(idx)(...rest);
    } catch (e) {
      if (e instanceof DylanThrow) {
        new Int32Array(memory.buffer)[threwAddr >>> 2] = 1;
        jsThrewValue = e.exc;
        return isVoid ? undefined : 0n;
      }
      throw e;
    }
  };
}
function setTempRet0(v) { new Int32Array(memory.buffer)[tempRet0Addr >>> 2] = v | 0; }

const env = {
  host_write(fd, ptr, len) {
    const s = dec.decode(new Uint8Array(memory.buffer, Number(ptr), Number(len)));
    (fd === 2n || fd === 2 ? process.stderr : process.stdout).write(s);
    return BigInt(Number(len));
  },
  host_throw(exc) { throw new DylanThrow(exc); },
  host_now_ns() { return process.hrtime.bigint(); },
  host_epoch_ms() { return BigInt(Date.now()); },
  __cxa_find_matching_catch_2()  { setTempRet0(0); return jsThrewValue; },
  __cxa_find_matching_catch_3(t) {
    if (jsThrewValue !== 0n) {
      const thrownTypeid =
        new BigUint64Array(memory.buffer)[(Number(jsThrewValue) + 40) >>> 3];
      if (thrownTypeid === t) {
        setTempRet0(Number(t) & 0xFFFFFFFF);
        return jsThrewValue;
      }
    }
    setTempRet0(0);
    return jsThrewValue;
  },
};
// libm routed to the host: exact, and float-to-string depends on log/pow
// for digit-count estimates (wrong values make it allocate absurd buffers).
for (const f of ['sin','cos','tan','asin','acos','atan','exp','log','pow','hypot'])
  env['host_' + f] = Math[f];

let module;
try {
  module = await WebAssembly.compile(readFileSync(wasmPath));
} catch (err) {
  if (err instanceof WebAssembly.CompileError) {
    console.error(`[harness] ${err.message}`);
    console.error('[harness] this module needs memory64 + table64: use node >= 24');
    process.exit(1);
  }
  throw err;
}
// Synthesize the invoke_<sig> EH trampolines from the module's own import
// list — llc emits one per invoke arity, so a hardcoded list breaks with a
// LinkError whenever new Dylan code introduces a new arity.
for (const imp of WebAssembly.Module.imports(module)) {
  if (imp.module === 'env' && imp.name.startsWith('invoke_') && !(imp.name in env))
    env[imp.name] = makeInvoke(imp.name);
}
instance = await WebAssembly.instantiate(module, { env });
const e = instance.exports;
memory = e.memory;
threwAddr = Number(e.__THREW__?.value || 0n);
tempRet0Addr = Number(e.tempRet0?.value || 0n);

// Wire argv exactly like the browser harness: argc i64 pointers followed by
// 8-byte-aligned NUL-terminated strings, at 256 MB — above the bump
// allocator's region, below initial memory.
const argvBase = 0x10000000;
const memU8 = new Uint8Array(memory.buffer);
const memU64 = new BigUint64Array(memory.buffer);
const enc = new TextEncoder();
let strAddr = (argvBase + args.length * 8 + 7) & ~7;
args.forEach((a, i) => {
  const bytes = enc.encode(a + '\0');
  memU8.set(bytes, strAddr);
  memU64[(argvBase >>> 3) + i] = BigInt(strAddr);
  strAddr = (strAddr + bytes.length + 7) & ~7;
});

try {
  // main(argc :: i32, argv :: i64): i32 takes a Number, i64 a BigInt.
  const rc = e.main(args.length, BigInt(argvBase));
  console.error('[harness] main returned:', rc);
  process.exitCode = Number(rc) || 0;
} catch (err) {
  console.error('[harness] trap:', err.message);
  console.error(err.stack?.split('\n').slice(0, 12).join('\n'));
  process.exitCode = 1;
}
