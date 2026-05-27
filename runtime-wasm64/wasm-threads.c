/* Single-threaded thread-primitive stubs for the Dylan→wasm32 MVP.
 *
 * wasm32-wasi (without the threads proposal) is single-threaded, so locks,
 * semaphores, and notifications are no-ops that always "succeed", and thread
 * creation/joining is unsupported. Signatures track the current run-time.h
 * (note primitive_detach_thread now returns void). Derived from the upstream
 * dummy-threads.c, updated to current declarations.
 */
/* run-time.h's prototypes for these two declare a `dylan_value` return, but the
   LLVM primitive descriptors declare `=> ()` (void). C ignores return type for
   linkage so native tolerates the mismatch; wasm call_indirect does not, so we
   must compile them as void. Rename the stale prototypes out of the way. */
#define primitive_initialize_special_thread od_stale_iss_proto
#define primitive_initialize_current_thread od_stale_ics_proto
#include "run-time.h"
#undef primitive_initialize_special_thread
#undef primitive_initialize_current_thread
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
dylan_value primitive_make_thread(dylan_value t, dylan_value f, DBOOL s)
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
void primitive_initialize_current_thread(dylan_value t, DBOOL s)
{ ignore(s); one_true_thread = t; }
void primitive_initialize_special_thread(dylan_value t)
{ one_true_thread = t; }

/* --- thread variables --- */
dylan_value primitive_allocate_thread_variable(dylan_value i) { ignore(i); return DFALSE; }

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
