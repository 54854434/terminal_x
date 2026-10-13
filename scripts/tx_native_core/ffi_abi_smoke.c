/* Compile-time header/ABI shape check: clang -std=c11 -fsyntax-only ffi_abi_smoke.c */
#include "terminal_x_core.h"
#include <stddef.h>
_Static_assert(sizeof(int64_t) == 8, "C ABI requires 64-bit signed cents");
_Static_assert(sizeof(uint64_t) == 8, "C ABI requires 64-bit IDs");
_Static_assert(sizeof(uint32_t) == 4, "C ABI requires 32-bit enum tags");
_Static_assert(sizeof(TxCoreEvent) == 80, "Event ABI size must remain fixed");
_Static_assert(offsetof(TxCoreEvent, expected_result) == 72,
               "Event result ABI offset must remain fixed");
void tx_core_ffi_signature_check(void) {
  void* (*allocate)(void) = tx_core_new;
  void (*dispose)(void*) = tx_core_free;
  int32_t (*place)(void*,uint64_t,uint64_t,uint32_t,uint32_t,uint32_t,int64_t,int64_t) = tx_core_place;
  const TxCoreEvent* (*event_at)(const void*, uint64_t) = tx_core_event_at;
  void* (*rebuild)(const void*) = tx_core_rebuild_from_events;
  (void)allocate; (void)dispose; (void)place;
  (void)event_at; (void)rebuild;
}
