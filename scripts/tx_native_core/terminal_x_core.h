#ifndef TERMINAL_X_CORE_H
#define TERMINAL_X_CORE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* ABI v2; opaque engine, never cross DLL boundary with Rust-owned allocations. */
/* Symbol IDs are extensible: 0=SIM-A01, 1=SIM-A02. Sides 0=buy,1=sell;
 * order kinds: 0=limit/GTC, 1=market, 2=post-only, 3=IOC, 4=FOK. */
/* Place results: 0=open,1=partial,2=filled,3=cancelled,4=rejected. */
/* Error results: -1=null handle, -2=invalid input, -3=unknown ID, -4=conflict. */
void* tx_core_new(void);
void tx_core_free(void* core);
uint32_t tx_core_abi_version(void);
int32_t tx_core_register(void* core, uint64_t account_id, int64_t cash_cents,
                          int64_t sim_a01_shares, int64_t sim_a02_shares);
/* Optional opening inventory for any new symbol, before first order. */
int32_t tx_core_add_initial_shares(void* core, uint64_t account_id, uint32_t symbol, int64_t quantity);
int32_t tx_core_place(void* core, uint64_t order_id, uint64_t owner_id,
                      uint32_t symbol, uint32_t side, uint32_t kind,
                      int64_t quantity, int64_t limit_price_cents);
int32_t tx_core_cancel(void* core, uint64_t order_id, uint64_t owner_id);
int64_t tx_core_cash(const void* core, uint64_t account_id);
int64_t tx_core_reserved_cash(const void* core, uint64_t account_id);
int64_t tx_core_shares(const void* core, uint64_t account_id, uint32_t symbol);
int64_t tx_core_reserved_shares(const void* core, uint64_t account_id, uint32_t symbol);
int64_t tx_core_order_remaining(const void* core, uint64_t order_id);
int64_t tx_core_fill_count(const void* core);
int64_t tx_core_fill_price(const void* core, uint64_t fill_index);
int64_t tx_core_fill_quantity(const void* core, uint64_t fill_index);
uint64_t tx_core_fill_buy_order(const void* core, uint64_t fill_index);
uint64_t tx_core_fill_sell_order(const void* core, uint64_t fill_index);
int32_t tx_core_verify(const void* core);
/* ABI v2, fixed-size, copyable event. No Rust allocation escapes the ABI. */
typedef struct TxCoreEvent {
    uint32_t action, side, order_kind, symbol;
    uint64_t order_id, owner_id;
    int64_t quantity, price_cents, cash_cents, shares_a, shares_b;
    int32_t expected_result, reserved;
} TxCoreEvent;
/* Event ptr is borrowed, valid ONLY until the next mutation/free. */
uint64_t tx_core_event_count(const void* core);
const TxCoreEvent* tx_core_event_at(const void* core, uint64_t index);
int32_t tx_core_replay_event(void* core, const TxCoreEvent* event);
void* tx_core_rebuild_from_events(const void* core);
int32_t tx_core_order_status(const void* core, uint64_t order_id);
uint64_t tx_core_active_order_count(const void* core);
#ifdef __cplusplus
}
#endif
#endif
