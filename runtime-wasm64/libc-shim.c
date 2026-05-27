/* Freestanding libc + runtime shim for the Dylan→wasm64 MVP.
 *
 * wasi-libc has no wasm64 sysroot, so we supply the small set of C-library and
 * compiler-rt symbols the Dylan runtime actually references. Allocation is a
 * leak/bump allocator (no GC yet); threads/exceptions are single-threaded /
 * no-op stubs. This is also the natural host-shim layer for a browser target.
 */
#include <stddef.h>
#include <stdint.h>

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
void abort(void)            { __builtin_trap(); }
void exit(int code)         { (void)code; __builtin_trap(); }   /* TODO: clean exit via host */
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
void  _Unwind_RaiseException(void *exc)           { (void)exc; __builtin_trap(); }

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
