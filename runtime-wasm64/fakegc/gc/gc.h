/* Minimal leak-GC shim for the Dylan→wasm MVP.
 *
 * Maps the Boehm GC API surface used by boehm-collector.c onto wasi-libc's
 * calloc, with NO collection (everything leaks). Correct for short-lived
 * programs; real GC on wasm is future work.
 */
#ifndef DYLAN_WASM_FAKE_GC_H
#define DYLAN_WASM_FAKE_GC_H

#include <stddef.h>
#include <stdlib.h>

typedef void (*GC_finalization_proc)(void *obj, void *client_data);

static inline void  *GC_malloc(size_t n)               { return calloc(1, n); }
static inline void  *GC_malloc_atomic(size_t n)        { return calloc(1, n); }
static inline void  *GC_malloc_uncollectable(size_t n) { return calloc(1, n); }
static inline void   GC_init(void)                     { }
static inline void   GC_gcollect(void)                 { }
static inline size_t GC_get_heap_size(void)            { return 0; }
static inline void   GC_enable_incremental(void)       { }
static inline void   GC_register_finalizer(void *obj, GC_finalization_proc fn,
                                           void *cd, GC_finalization_proc *ofn,
                                           void **ocd) {
  (void)obj; (void)fn; (void)cd;
  if (ofn) *ofn = 0;
  if (ocd) *ocd = 0;
}

#define GC_INIT()                  GC_init()
#define GC_MALLOC(n)               GC_malloc(n)
#define GC_MALLOC_ATOMIC(n)        GC_malloc_atomic(n)
#define GC_MALLOC_UNCOLLECTABLE(n) GC_malloc_uncollectable(n)
#define GC_FREE(p)                 ((void)(p))

#endif
