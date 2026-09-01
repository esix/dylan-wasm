/* Single-threaded thread-primitive stubs for the Dylan→wasm MVP.
 *
 * wasm-wasi (without the threads proposal) is single-threaded, so locks,
 * semaphores, and notifications are no-ops that always "succeed", and thread
 * creation/joining is unsupported. Signatures track the current run-time.h
 * (note primitive_detach_thread now returns void). Derived from the upstream
 * dummy-threads.c, updated to current declarations.
 */
/* run-time.h's prototypes disagree with the LLVM primitive descriptors: the
   initialize-*-thread pair is declared returning `dylan_value` where the
   descriptors say `=> ()` (void), and the `synchronous?` params are DBOOL
   (unsigned long, i64) where the back-end lowers <raw-boolean> to i32. C
   ignores both for linkage so native tolerates the mismatch; wasm does not —
   wasm-ld routes mismatched calls to an `unreachable` stub. Rename the stale
   prototypes out of the way and define with the descriptor-exact types. */
#define primitive_initialize_special_thread od_stale_iss_proto
#define primitive_initialize_current_thread od_stale_ics_proto
#define primitive_make_thread od_stale_mkt_proto
#include "run-time.h"
#undef primitive_initialize_special_thread
#undef primitive_initialize_current_thread
#undef primitive_make_thread

/* <raw-boolean>: i32 in the emitted bitcode, so `int` here — NOT DBOOL. */
typedef int DRAWBOOL;
#include <stdio.h>
#include <stdlib.h>

#define ignore(x) ((void)(x))
#define THREAD_SUCCESS I(0)

/* The canonical Dylan booleans, defined in the dylan library. */
extern dylan_object KPfalseVKi;
extern dylan_object KPtrueVKi;

/* NB: the TEB machinery (dylan_teb, Pteb, ...) is provided by the generated
   runtime, so we must NOT define dylan_teb/make_teb here. */
static dylan_value one_true_thread = DFALSE;

void threads_get_stuffed(void)
{
  fprintf(stderr, "This implementation does not support real threads\n");
}

/* --- thread lifecycle --- */
dylan_value primitive_make_thread(dylan_value t, dylan_value f, DRAWBOOL s)
{ ignore(t); ignore(f); ignore(s); threads_get_stuffed(); return THREAD_SUCCESS; }
dylan_value primitive_destroy_thread(dylan_value t) { ignore(t); return THREAD_SUCCESS; }
void primitive_detach_thread(dylan_value t) { ignore(t); }
dylan_value primitive_thread_join_single(dylan_value t)
{ ignore(t); threads_get_stuffed(); return THREAD_SUCCESS; }
dylan_value primitive_thread_join_multiple(dylan_value v)
{ ignore(v); threads_get_stuffed(); return THREAD_SUCCESS; }
void primitive_thread_yield(void) { }
void primitive_sleep(dylan_value ms) { ignore(ms); }
/* descriptor: => (thread :: <object>) — must return the thread object set at
   init (one_true_thread), not an integer, or callers fail their type check. */
dylan_value primitive_current_thread(void) { return one_true_thread; }
/* descriptors declare these `=> ()` (void) — must match for wasm call_indirect */
void primitive_initialize_current_thread(dylan_value t, DRAWBOOL s)
{ ignore(s); one_true_thread = t; }
void primitive_initialize_special_thread(dylan_value t)
{ one_true_thread = t; }

/* --- thread variables ---
 * Upstream `dummy-threads.c` returns DFALSE here because in non-threaded
 * builds it's paired with stubbed read/write_thread_variable. But Open
 * Dylan's LLVM back-end emits INLINE TLV access through `Pteb` + the global
 * `Ptlv_initializations` table: it expects this primitive to return a real
 * raw integer offset that's used as a vector index, and the new variable's
 * initial value to live at that offset in `Ptlv_initializations`. The
 * DFALSE-stub bug masquerades as a NULL hash-state during puthash → boot
 * symbol install: NULL ptrtoint'd is a huge offset, off-end-of-vector read
 * returns 0 from wasm linear memory, type-check expects <hash-state>. */
typedef struct dylan_sov { void *wrapper; void *size; void *elems[]; } dylan_sov;
extern dylan_sov *Ptlv_initializations;
extern unsigned long Ptlv_initializations_cursor;
extern char KLsimple_object_vectorGVKdW;     /* wrapper singleton */
extern char KPunboundVKi;                    /* <unbound> singleton */

dylan_value primitive_allocate_thread_variable(dylan_value v) {
  unsigned long off = Ptlv_initializations_cursor;
  unsigned long cur_size = ((unsigned long)Ptlv_initializations->size) >> 2;
  if (off >= cur_size) {
    unsigned long new_size = cur_size ? cur_size * 2 : 64;
    dylan_sov *nv = malloc(sizeof(dylan_sov) + new_size * sizeof(void *));
    nv->wrapper = &KLsimple_object_vectorGVKdW;
    nv->size = (void *)((new_size << 2) | 1);           /* tagged integer */
    for (unsigned long i = 0; i < off; i++)
      nv->elems[i] = Ptlv_initializations->elems[i];
    for (unsigned long i = off; i < new_size; i++)
      nv->elems[i] = &KPunboundVKi;
    Ptlv_initializations = nv;
  }
  Ptlv_initializations->elems[off] = (void *)v;
  Ptlv_initializations_cursor = off + 1;
  return (dylan_value)off;
}

/* --- simple locks --- */
dylan_value primitive_make_simple_lock(dylan_value l, dylan_value n) { ignore(l); ignore(n); return THREAD_SUCCESS; }
dylan_value primitive_destroy_simple_lock(dylan_value l) { ignore(l); return THREAD_SUCCESS; }
dylan_value primitive_wait_for_simple_lock(dylan_value l) { ignore(l); return THREAD_SUCCESS; }
dylan_value primitive_wait_for_simple_lock_timed(dylan_value l, dylan_value ms) { ignore(l); ignore(ms); return THREAD_SUCCESS; }
dylan_value primitive_release_simple_lock(dylan_value l) { ignore(l); return THREAD_SUCCESS; }
dylan_value primitive_owned_simple_lock(dylan_value l) { ignore(l); return DTRUE; }

/* --- recursive locks --- */
dylan_value primitive_make_recursive_lock(dylan_value l, dylan_value n) { ignore(l); ignore(n); return THREAD_SUCCESS; }
dylan_value primitive_destroy_recursive_lock(dylan_value l) { ignore(l); return THREAD_SUCCESS; }
dylan_value primitive_wait_for_recursive_lock(dylan_value l) { ignore(l); return THREAD_SUCCESS; }
dylan_value primitive_wait_for_recursive_lock_timed(dylan_value l, dylan_value ms) { ignore(l); ignore(ms); return THREAD_SUCCESS; }
dylan_value primitive_release_recursive_lock(dylan_value l) { ignore(l); return THREAD_SUCCESS; }
dylan_value primitive_owned_recursive_lock(dylan_value l) { ignore(l); return DTRUE; }

/* --- semaphores --- */
dylan_value primitive_make_semaphore(dylan_value l, dylan_value n, dylan_value i, dylan_value m) { ignore(l); ignore(n); ignore(i); ignore(m); return THREAD_SUCCESS; }
dylan_value primitive_destroy_semaphore(dylan_value l) { ignore(l); return THREAD_SUCCESS; }
dylan_value primitive_wait_for_semaphore(dylan_value s) { ignore(s); return THREAD_SUCCESS; }
dylan_value primitive_wait_for_semaphore_timed(dylan_value s, dylan_value ms) { ignore(s); ignore(ms); return THREAD_SUCCESS; }
dylan_value primitive_release_semaphore(dylan_value s) { ignore(s); return THREAD_SUCCESS; }

/* --- notifications --- */
dylan_value primitive_make_notification(dylan_value l, dylan_value n) { ignore(l); ignore(n); return THREAD_SUCCESS; }
dylan_value primitive_destroy_notification(dylan_value n) { ignore(n); return THREAD_SUCCESS; }
dylan_value primitive_wait_for_notification(dylan_value n, dylan_value l) { ignore(n); ignore(l); return THREAD_SUCCESS; }
dylan_value primitive_wait_for_notification_timed(dylan_value n, dylan_value l, dylan_value ms) { ignore(n); ignore(l); ignore(ms); return THREAD_SUCCESS; }
dylan_value primitive_release_notification(dylan_value n, dylan_value l) { ignore(n); ignore(l); return THREAD_SUCCESS; }
dylan_value primitive_release_all_notification(dylan_value n, dylan_value l) { ignore(n); ignore(l); return THREAD_SUCCESS; }
