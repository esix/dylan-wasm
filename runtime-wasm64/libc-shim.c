/* Freestanding libc + runtime shim for the Dylan→wasm64 MVP.
 *
 * wasi-libc has no wasm64 sysroot, so we supply the small set of C-library and
 * compiler-rt symbols the Dylan runtime actually references. Allocation is a
 * leak/bump allocator (no GC yet); threads/exceptions are single-threaded /
 * no-op stubs. This is also the natural host-shim layer for a browser target.
 */
#include <stddef.h>
#include <stdint.h>

/* host imports (output + diagnostics) */
__attribute__((import_module("env"), import_name("host_write")))
extern long host_write(int fd, const void *buf, unsigned long count);
static unsigned long shim_strlen(const char *s) { unsigned long n = 0; while (s[n]) n++; return n; }
static void report(const char *m) { host_write(2, m, shim_strlen(m)); }

/* ---------- bump allocator (leak; MVP, no collection) ---------- */
extern unsigned char __heap_base;        /* provided by wasm-ld */
static uintptr_t g_bump = 0;

void *malloc(size_t n) {
  if (g_bump == 0) g_bump = (uintptr_t)&__heap_base;
  g_bump = (g_bump + 15u) & ~(uintptr_t)15u;       /* 16-byte align */
  void *p = (void *)g_bump;
  g_bump += n;
  return p;
}
void *calloc(size_t a, size_t b) {
  size_t n = a * b;
  unsigned char *p = (unsigned char *)malloc(n);
  for (size_t i = 0; i < n; i++) p[i] = 0;
  return p;
}
void  free(void *p) { (void)p; }
void *realloc(void *p, size_t n) { (void)p; return malloc(n); }

/* ---------- mem ops (also lowered via -mbulk-memory; provide for explicit calls) ---------- */
void *memcpy(void *d, const void *s, size_t n) {
  unsigned char *dd = d; const unsigned char *ss = s;
  for (size_t i = 0; i < n; i++) dd[i] = ss[i];
  return d;
}
void *memset(void *d, int c, size_t n) {
  unsigned char *dd = d;
  for (size_t i = 0; i < n; i++) dd[i] = (unsigned char)c;
  return d;
}
void *memmove(void *d, const void *s, size_t n) {
  unsigned char *dd = d; const unsigned char *ss = s;
  if (dd < ss) for (size_t i = 0; i < n; i++) dd[i] = ss[i];
  else         for (size_t i = n; i > 0; i--) dd[i-1] = ss[i-1];
  return d;
}

/* ---------- process / misc libc stubs ---------- */
void abort(void)            { report("[trap] abort\n"); __builtin_trap(); }
void exit(int code)         { (void)code; report("[trap] exit\n"); __builtin_trap(); }
int  atexit(void (*fn)(void)) { (void)fn; return 0; }
void *stderr = 0;
void *stdout = 0;
int  fprintf(void *stream, const char *fmt, ...) { (void)stream; (void)fmt; return 0; }

/* ---------- math (refine later; Dylan float) ---------- */
double pow(double x, double y)  { (void)y; return x; }
float  powf(float x, float y)   { (void)y; return x; }

/* ---------- threading: single-threaded no-ops ---------- */
int pthread_mutex_lock(void *m)   { (void)m; return 0; }
int pthread_mutex_unlock(void *m) { (void)m; return 0; }

/* ---------- Dylan runtime symbols from files we didn't compile ---------- */
void  EstablishDylanExceptionHandlers(void)       { }
void  primitive_initialize_thread_variables(void) { }
void  primitive_reset_float_environment(void)     { }
void *get_current_thread_handle(void)             { return 0; }
/* _Unwind_RaiseException is called by primitive_nlx (llvm-nlx.c). On
 * Emscripten EH, we throw a JS exception via the host so it propagates
 * through wasm frames until caught by an invoke_* wrapper. */
__attribute__((import_module("env"), import_name("host_throw")))
extern _Noreturn void host_throw(void *exc);

/* Itanium ABI: returns _Unwind_Reason_Code (int). The host_throw never
 * actually returns, so the trailing `return` is just there to make the
 * wasm signature match what llvm-nlx.c's IR call expects. */
int _Unwind_RaiseException(void *exc) { host_throw(exc); return 0; }

/* ---------- Emscripten-style EH helpers (--enable-emscripten-cxx-exceptions) ----------
 * llc rewrites Itanium `invoke` -> calls to env.invoke_<sig> and `resume` ->
 * __resumeException; landingpad sites read __THREW__/__threwValue and use
 * llvm_eh_typeid_for to match catch clauses against __cxa_find_matching_catch_*.
 * __THREW__ and __threwValue live in linear memory; JS reads/writes them
 * via the exported addresses. */
__attribute__((used)) int __THREW__ = 0;
__attribute__((used)) int __threwValue = 0;

/* getTempRet0 returns the catch typeID that __cxa_find_matching_catch_*
 * wrote into the shared `tempRet0` location; landingpad code reads it
 * to do the type-compare. JS exports tempRet0's address and writes it. */
__attribute__((used)) int tempRet0 = 0;
int  getTempRet0(void)                    { return tempRet0; }
int  llvm_eh_typeid_for(void *typeinfo)   { return (int)(unsigned long)typeinfo; }

/* __resumeException re-raises the previously caught exception (Itanium
 * `resume`). We funnel back through host_throw for the same propagation. */
void __resumeException(void *exc)         { host_throw(exc); }

/* ---------- compiler-rt 128-bit builtins (no wasm compiler-rt available) ----------
   Standard algorithms; union access only (never multiply/shift __int128 directly,
   which would recurse back into these routines). Little-endian layout. */
typedef unsigned long long du_int;
typedef union { __int128 all; struct { du_int low; du_int high; } s; } twords;

__int128 __ashlti3(__int128 a, int b) {
  twords in, r;
  in.all = a;
  if (b & 64) {                 /* b >= 64 */
    r.s.low  = 0;
    r.s.high = in.s.low << (b - 64);
  } else {
    if (b == 0) return a;
    r.s.low  = in.s.low << b;
    r.s.high = (in.s.high << b) | (in.s.low >> (64 - b));
  }
  return r.all;
}

/* 64x64 -> 128 unsigned multiply via 32-bit partial products */
static void mul_u64(du_int a, du_int b, du_int *lo, du_int *hi) {
  du_int al = (du_int)(uint32_t)a, ah = a >> 32;
  du_int bl = (du_int)(uint32_t)b, bh = b >> 32;
  du_int t  = al * bl;
  du_int w0 = (du_int)(uint32_t)t;
  du_int k  = t >> 32;
  t = ah * bl + k;
  du_int w1 = (du_int)(uint32_t)t;
  du_int w2 = t >> 32;
  t = al * bh + w1;
  k = t >> 32;
  *hi = ah * bh + w2 + k;
  *lo = (t << 32) + w0;
}

__int128 __multi3(__int128 a, __int128 b) {
  twords aa, bb, r;
  aa.all = a; bb.all = b;
  du_int lo, hi;
  mul_u64(aa.s.low, bb.s.low, &lo, &hi);
  r.s.low  = lo;
  r.s.high = hi + aa.s.low * bb.s.high + aa.s.high * bb.s.low;   /* low 128 bits */
  return r.all;
}

/* 128-bit divide/shift-right builtins. Hello-world prints a literal string and
   never exercises integer formatting, so these only need to *exist* to link;
   they trap if actually called. Replace with real long-division when integer
   formatting is needed. */
__int128 __udivti3(__int128 a, __int128 b) { (void)a;(void)b; report("[trap] __udivti3\n"); __builtin_trap(); }
__int128 __umodti3(__int128 a, __int128 b) { (void)a;(void)b; report("[trap] __umodti3\n"); __builtin_trap(); }
__int128 __divti3 (__int128 a, __int128 b) { (void)a;(void)b; report("[trap] __divti3\n");  __builtin_trap(); }
__int128 __modti3 (__int128 a, __int128 b) { (void)a;(void)b; report("[trap] __modti3\n");  __builtin_trap(); }
__int128 __lshrti3(__int128 a, int b)      { (void)a;(void)b; report("[trap] __lshrti3\n"); __builtin_trap(); }

/* ---------- transcendental math: stubs (hello doesn't use them) ---------- */
double acos(double x){return x;}  float acosf(float x){return x;}
double asin(double x){return x;}  float asinf(float x){return x;}
double atan(double x){return x;}  float atanf(float x){return x;}
double cos(double x){return x;}   float cosf(float x){return x;}
double sin(double x){return x;}   float sinf(float x){return x;}
double tan(double x){return x;}   float tanf(float x){return x;}
double exp(double x){return x;}   float expf(float x){return x;}
double log(double x){return x;}   float logf(float x){return x;}
double hypot(double x,double y){(void)y;return x;} float hypotf(float x,float y){(void)y;return x;}

/* ---------- output path: route POSIX write() through the host import ---------- */
long write(int fd, const void *buf, unsigned long count) {
  return host_write(fd, buf, count);
}

/* ---------- file-descriptor / OS stubs (hello only writes stdout) ---------- */
long  read(int fd, void *buf, unsigned long n) { (void)fd;(void)buf;(void)n; return 0; }
int   close(int fd)            { (void)fd; return 0; }
int   fsync(int fd)            { (void)fd; return 0; }
int   isatty(int fd)           { (void)fd; return 1; }   /* claim a tty: unbuffered, no seeking */
long  lseek(int fd, long off, int whence) { (void)fd;(void)off;(void)whence; return -1; }
long  readlink(const char *p, char *b, unsigned long n) { (void)p;(void)b;(void)n; return -1; }
/* time() and timer_get_point_in_time() use a host clock so simple-random
 * gets a real seed and simple-profiling reports real elapsed time. */
__attribute__((import_module("env"), import_name("host_now_ns")))
extern uint64_t host_now_ns(void);
long  time(long *t)            { uint64_t s = host_now_ns() / 1000000000ULL; if (t) *t = (long)s; return (long)s; }

/* ---------- Dylan io syscall wrappers (stubs; stdout is non-seekable) ---------- */
int   io_errno(void)                 { return 0; }
char *io_strerror(int e)             { (void)e; return ""; }
long  io_lseek(int fd, long off, int whence) { (void)fd;(void)off;(void)whence; return -1; }
int   io_fd_positionable(int fd)     { (void)fd; return 0; }   /* false: stdout not positionable */
void  timer_get_point_in_time(uint32_t t[2]) {
  uint64_t now_ns = host_now_ns();
  t[0] = (uint32_t)(now_ns / 1000000000ULL);  /* seconds */
  t[1] = (uint32_t)(now_ns % 1000000000ULL);  /* nanoseconds */
}
