//! Terminal X native-core prototype, deterministic and offline.
//!
//! The Android release workflow compiles and packages this crate for ARM64.
//! Dart remains the persisted UI projection; Rust owns executable Android-
//! worker matching and must pass the parity/audit gate before commit.
//! R36 adds a deterministic command journal + replay test seam. R48 adds
//! post-only, IOC and FOK limit execution policies without changing ABI v2.
//!
//! Integer cents and quantities only. No hidden liquidity, guessed fills,
//! floating-point financial math, wall-clock scheduling or global mutable data.
use std::collections::{BTreeMap, BTreeSet};

const MAX_NOTIONAL: i128 = 9_000_000_000_000_000;
const MAX_QTY: i64 = 100_000_000;
const MAX_PRICE: i64 = 1_000_000_000;
const NULL: i32 = -1;
const INVALID: i32 = -2;
const UNKNOWN: i32 = -3;
const CONFLICT: i32 = -4;
const OPEN: i32 = 0;
const PARTIAL: i32 = 1;
const FILLED: i32 = 2;
const CANCELLED: i32 = 3;
const REJECTED: i32 = 4;
const LIMIT_GTC: u32 = 0;
const MARKET: u32 = 1;
const POST_ONLY: u32 = 2;
const IOC: u32 = 3;
const FOK: u32 = 4;

fn is_limit(kind: u32) -> bool {
    kind == LIMIT_GTC || kind == POST_ONLY || kind == IOC || kind == FOK
}

fn can_rest(kind: u32) -> bool {
    kind == LIMIT_GTC || kind == POST_ONLY
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Account {
    cash: i64,
    reserved_cash: i64,
    shares: BTreeMap<u32, i64>,
    reserved_shares: BTreeMap<u32, i64>,
}

impl Account {
    fn free_cash(&self) -> i64 { self.cash - self.reserved_cash }
    fn free_shares(&self, symbol: u32) -> i64 {
        self.shares.get(&symbol).copied().unwrap_or(0)
            - self.reserved_shares.get(&symbol).copied().unwrap_or(0)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Order {
    id: u64,
    owner: u64,
    symbol: u32,
    side: u32,
    kind: u32,
    quantity: i64,
    remaining: i64,
    price: i64,
    sequence: u64,
    status: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Fill { buy: u64, sell: u64, price: i64, quantity: i64 }

// A price-time priority index. Only ACTIVE orders live here: historical
// fills/cancels must not make a new trade slower as game history grows.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
struct RestingKey {
    price_priority: i64,
    sequence: u64,
    index: usize,
}

impl RestingKey {
    fn new(order: &Order, index: usize) -> Self {
        Self {
            price_priority: if order.side == 0 { -order.price } else { order.price },
            sequence: order.sequence,
            index,
        }
    }
}

/// Stable ABI v2 fixed-size event. Never export Rust collection pointers.
/// Values that are not used by the selected action must be zero.
/// 1=register, 2=opening shares, 3=place order, 4=cancel order.
#[repr(C)]
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct TxCoreEvent {
    pub action: u32,
    pub side: u32,
    pub order_kind: u32,
    pub symbol: u32,
    pub order_id: u64,
    pub owner_id: u64,
    pub quantity: i64,
    pub price_cents: i64,
    pub cash_cents: i64,
    pub shares_a: i64,
    pub shares_b: i64,
    pub expected_result: i32,
    pub reserved: i32,
}

#[derive(Default, Debug, Clone, PartialEq, Eq)]
pub struct Engine {
    accounts: BTreeMap<u64, Account>,
    initial: BTreeMap<u64, (i64, BTreeMap<u32, i64>)>,
    orders: Vec<Order>,
    order_index: BTreeMap<u64, usize>,
    resting: BTreeMap<(u32, u32), BTreeSet<RestingKey>>,
    fills: Vec<Fill>,
    journal: Vec<TxCoreEvent>,
    next_sequence: u64,
}

impl Engine {
    fn register(&mut self, id: u64, cash: i64, a: i64, b: i64) -> i32 {
        if id == 0 || cash < 0 || i128::from(cash) > MAX_NOTIONAL ||
            a < 0 || b < 0 || a > MAX_QTY || b > MAX_QTY { return INVALID; }
        if self.accounts.contains_key(&id) { return CONFLICT; }
        let balances = BTreeMap::from([(0, a), (1, b)]);
        self.accounts.insert(id, Account {
            cash, reserved_cash: 0, shares: balances.clone(),
            reserved_shares: BTreeMap::new(),
        });
        self.initial.insert(id, (cash, balances));
        self.journal.push(TxCoreEvent {
            action: 1, owner_id: id, cash_cents: cash,
            shares_a: a, shares_b: b, expected_result: 0,
            ..TxCoreEvent::default()
        });
        0
    }

    /// Future symbols can be funded without increasing ABI version or
    /// changing the account struct. Opening positions may be added only
    /// before the first submitted order; never mint assets mid-session.
    fn add_opening_shares(&mut self, owner: u64, symbol: u32, qty: i64) -> i32 {
        if qty < 0 || qty > MAX_QTY || !self.orders.is_empty() { return INVALID; }
        let Some(account) = self.accounts.get_mut(&owner) else { return UNKNOWN; };
        let Some(initial) = self.initial.get_mut(&owner) else { return UNKNOWN; };
        if account.shares.contains_key(&symbol) || initial.1.contains_key(&symbol) {
            return CONFLICT;
        }
        account.shares.insert(symbol, qty);
        initial.1.insert(symbol, qty);
        self.journal.push(TxCoreEvent {
            action: 2, owner_id: owner, symbol, quantity: qty,
            expected_result: 0, ..TxCoreEvent::default()
        });
        0
    }

    fn insert_resting(&mut self, idx: usize) {
        let o = &self.orders[idx];
        if can_rest(o.kind) && o.remaining > 0 &&
           (o.status == OPEN || o.status == PARTIAL) {
            self.resting.entry((o.symbol, o.side)).or_default()
                .insert(RestingKey::new(o, idx));
        }
    }

    fn place(&mut self, id: u64, owner: u64, symbol: u32, side: u32,
             kind: u32, quantity: i64, price: i64) -> i32 {
        if id == 0 || owner == 0 || side > 1 || kind > FOK ||
           quantity <= 0 || quantity > MAX_QTY ||
           (is_limit(kind) && (price <= 0 || price > MAX_PRICE ||
              i128::from(price) * i128::from(quantity) > MAX_NOTIONAL)) ||
           (kind == MARKET && price != 0) { return INVALID; }
        if let Some(&i) = self.order_index.get(&id) {
            let o = &self.orders[i];
            return if o.owner == owner && o.symbol == symbol &&
                o.side == side && o.kind == kind && o.quantity == quantity &&
                o.price == price { o.status } else { CONFLICT };
        }
        if !self.accounts.contains_key(&owner) { return UNKNOWN; }
        let mut incoming = Order {
            id, owner, symbol, side, kind, quantity,
            remaining: quantity, price, sequence: self.next_sequence + 1,
            status: OPEN,
        };
        // The opposite book is already best-price-then-FIFO ordered.
        // This scans *active* counterparties only, never archived orders.
        let mut matches: Vec<usize> = Vec::new();
        if let Some(book) = self.resting.get(&(symbol, 1 - side)) {
            for key in book {
                let maker = &self.orders[key.index];
                if is_limit(kind) && ((side == 0 && maker.price > price) ||
                                 (side == 1 && maker.price < price)) { break; }
                matches.push(key.index);
            }
        }
        let mut needed = quantity;
        let mut market_cost: i128 = 0;
        let mut fill_plan: Vec<(usize, i64)> = Vec::new();
        if kind == POST_ONLY && !matches.is_empty() {
            incoming.status = REJECTED;
        }
        for i in matches {
            if needed == 0 { break; }
            let maker = &self.orders[i];
            let take = needed.min(maker.remaining);
            if maker.owner == owner { incoming.status = REJECTED; break; }
            if kind == MARKET && side == 0 {
                market_cost += i128::from(take) * i128::from(maker.price);
                if market_cost > MAX_NOTIONAL { incoming.status = REJECTED; break; }
            }
            fill_plan.push((i, take));
            needed -= take;
        }
        if kind == FOK && needed > 0 { incoming.status = REJECTED; }
        let actor = &self.accounts[&owner];
        if incoming.status != REJECTED {
            let cash_required = if side == 0 {
                if is_limit(kind) { i128::from(quantity) * i128::from(price) }
                else { market_cost }
            } else { 0 };
            if cash_required > i128::from(actor.free_cash()) ||
                (side == 1 && quantity > actor.free_shares(symbol)) {
                incoming.status = REJECTED;
            }
        }
        // Preflight all payees, to avoid overflow before the first fill.
        let mut buyer_proceeds: BTreeMap<u64, i128> = BTreeMap::new();
        let mut seller_proceeds: BTreeMap<u64, i128> = BTreeMap::new();
        if incoming.status != REJECTED {
            for &(i, take) in &fill_plan {
                let maker = &self.orders[i];
                let buyer = if side == 0 { owner } else { maker.owner };
                let seller = if side == 1 { owner } else { maker.owner };
                let notional = i128::from(take) * i128::from(maker.price);
                *buyer_proceeds.entry(buyer).or_default() += notional;
                *seller_proceeds.entry(seller).or_default() += notional;
            }
            for (&seller, &cash_in) in &seller_proceeds {
                let cash_out = buyer_proceeds.get(&seller).copied().unwrap_or(0);
                let future = i128::from(self.accounts[&seller].cash) + cash_in - cash_out;
                if future < 0 || future > MAX_NOTIONAL { incoming.status = REJECTED; break; }
            }
        }
        self.next_sequence += 1;
        let mut event = TxCoreEvent {
            action: 3, owner_id: owner, order_id: id, symbol,
            side, order_kind: kind, quantity, price_cents: price,
            ..TxCoreEvent::default()
        };
        if incoming.status == REJECTED {
            let idx = self.orders.len();
            self.order_index.insert(id, idx);
            self.orders.push(incoming);
            event.expected_result = REJECTED;
            self.journal.push(event);
            return REJECTED;
        }
        if is_limit(kind) {
            let actor = self.accounts.get_mut(&owner).expect("preflighted actor");
            if side == 0 { actor.reserved_cash += quantity * price; }
            else { *actor.reserved_shares.entry(symbol).or_default() += quantity; }
        }
        for (i, take) in fill_plan {
            let maker = &mut self.orders[i];
            let maker_owner = maker.owner;
            let maker_side = maker.side;
            let execution_price = maker.price;
            let notional = take * execution_price; // bounded <= MAX_NOTIONAL
            maker.remaining -= take;
            maker.status = if maker.remaining == 0 { FILLED } else { PARTIAL };
            let maker_closed = maker.remaining == 0;
            let maker_key = RestingKey::new(maker, i);
            incoming.remaining -= take;
            let buy_owner = if side == 0 { owner } else { maker_owner };
            let sell_owner = if side == 1 { owner } else { maker_owner };
            {
                let buyer = self.accounts.get_mut(&buy_owner).expect("known buyer");
                buyer.cash -= notional;
                *buyer.shares.entry(symbol).or_default() += take;
                if buy_owner == owner && is_limit(kind) {
                    buyer.reserved_cash -= take * price;
                } else if buy_owner == maker_owner && maker_side == 0 {
                    buyer.reserved_cash -= take * execution_price;
                }
            }
            {
                let seller = self.accounts.get_mut(&sell_owner).expect("known seller");
                seller.cash += notional;
                *seller.shares.entry(symbol).or_default() -= take;
                if sell_owner == owner && is_limit(kind) {
                    *seller.reserved_shares.entry(symbol).or_default() -= take;
                } else if sell_owner == maker_owner && maker_side == 1 {
                    *seller.reserved_shares.entry(symbol).or_default() -= take;
                }
            }
            self.fills.push(Fill {
                buy: if side == 0 { id } else { maker.id },
                sell: if side == 1 { id } else { maker.id },
                price: execution_price, quantity: take,
            });
            if maker_closed {
                if let Some(book) = self.resting.get_mut(&(symbol, maker_side)) {
                    book.remove(&maker_key);
                }
            }
        }
        if incoming.remaining > 0 && kind == IOC {
            let actor = self.accounts.get_mut(&owner).expect("known owner");
            if side == 0 {
                actor.reserved_cash -= incoming.remaining * price;
            } else {
                *actor.reserved_shares.entry(symbol).or_default() -=
                    incoming.remaining;
            }
        }
        incoming.status = if incoming.remaining == 0 { FILLED }
            else if kind == MARKET || kind == IOC { CANCELLED }
            else if incoming.remaining == quantity { OPEN }
            else { PARTIAL };
        let idx = self.orders.len();
        self.order_index.insert(id, idx);
        let result = incoming.status;
        self.orders.push(incoming);
        self.insert_resting(idx);
        event.expected_result = result;
        self.journal.push(event);
        result
    }

    fn cancel(&mut self, id: u64, owner: u64) -> i32 {
        let Some(&index) = self.order_index.get(&id) else { return UNKNOWN; };
        let order = &mut self.orders[index];
        if order.owner != owner { return CONFLICT; }
        if order.status != OPEN && order.status != PARTIAL { return order.status; }
        let actor = self.accounts.get_mut(&owner).expect("active owner exists");
        if order.side == 0 { actor.reserved_cash -= order.remaining * order.price; }
        else { *actor.reserved_shares.entry(order.symbol).or_default() -= order.remaining; }
        order.status = CANCELLED;
        let key = RestingKey::new(order, index);
        if let Some(book) = self.resting.get_mut(&(order.symbol, order.side)) {
            book.remove(&key);
        }
        self.journal.push(TxCoreEvent {
            action: 4, owner_id: owner, order_id: id,
            expected_result: CANCELLED, ..TxCoreEvent::default()
        });
        CANCELLED
    }

    /// Replay commands on a fresh engine; a result mismatch is fatal.
    /// A failed replay engine must be discarded by its caller.
    fn replay_event(&mut self, event: &TxCoreEvent) -> i32 {
        if event.reserved != 0 { return INVALID; }
        let result = match event.action {
            1 => self.register(event.owner_id, event.cash_cents,
                 event.shares_a, event.shares_b),
            2 => self.add_opening_shares(event.owner_id, event.symbol,
                 event.quantity),
            3 => self.place(event.order_id, event.owner_id, event.symbol,
                 event.side, event.order_kind, event.quantity, event.price_cents),
            4 => self.cancel(event.order_id, event.owner_id),
            _ => return INVALID,
        };
        if result == event.expected_result { 0 } else { -5 }
    }

    fn verify(&self) -> bool {
        if self.orders.len() != self.order_index.len() ||
            self.accounts.len() != self.initial.len() { return false; }
        let mut account_cash_total: i128 = 0;
        let mut initial_cash_total: i128 = 0;
        let mut account_shares_total: BTreeMap<u32, i128> = BTreeMap::new();
        let mut initial_shares_total: BTreeMap<u32, i128> = BTreeMap::new();
        let mut expected_cash: BTreeMap<u64, i128> = BTreeMap::new();
        let mut expected_shares: BTreeMap<(u64, u32), i128> = BTreeMap::new();
        let mut resting_count = 0usize;
        // Order IDs are arbitrary, but order sequence is append-only and
        // starts at 1 even for rejected orders. Checking index+1 verifies
        // uniqueness AND continuity without a historical BTreeSet allocation.
        if self.next_sequence != self.orders.len() as u64 { return false; }
        for (i, order) in self.orders.iter().enumerate() {
            if self.order_index.get(&order.id) != Some(&i) ||
                order.sequence != (i as u64) + 1 ||
                order.remaining < 0 || order.remaining > order.quantity ||
                !self.accounts.contains_key(&order.owner) { return false; }
            match order.status {
                OPEN | PARTIAL => {
                    if !can_rest(order.kind) || order.remaining == 0 ||
                       (order.status == OPEN && order.remaining != order.quantity) ||
                       (order.status == PARTIAL && order.remaining == order.quantity) {
                        return false;
                    }
                    let key = RestingKey::new(order, i);
                    if !self.resting.get(&(order.symbol, order.side))
                          .map(|book| book.contains(&key)).unwrap_or(false) { return false; }
                    resting_count += 1;
                    if order.side == 0 {
                        *expected_cash.entry(order.owner).or_default() +=
                            i128::from(order.remaining) * i128::from(order.price);
                    } else {
                        *expected_shares.entry((order.owner, order.symbol)).or_default() +=
                            i128::from(order.remaining);
                    }
                }
                FILLED => if order.remaining != 0 { return false; },
                CANCELLED | REJECTED => (),
                _ => return false,
            }
        }
        // Every active index entry must refer to exactly one active order.
        let mut indexed = 0usize;
        for ((symbol, side), book) in &self.resting {
            for key in book {
                let Some(order) = self.orders.get(key.index) else { return false; };
                if order.symbol != *symbol || order.side != *side ||
                    !can_rest(order.kind) || order.remaining <= 0 ||
                    (order.status != OPEN && order.status != PARTIAL) ||
                    RestingKey::new(order, key.index) != *key { return false; }
                indexed += 1;
            }
        }
        if indexed != resting_count { return false; }
        for (id, account) in &self.accounts {
            let Some((initial_cash, initial_shares)) = self.initial.get(id) else { return false; };
            if account.cash < 0 || account.reserved_cash < 0 ||
                account.reserved_cash > account.cash ||
                i128::from(account.reserved_cash) != expected_cash.get(id).copied().unwrap_or(0) {
                return false;
            }
            account_cash_total += i128::from(account.cash);
            initial_cash_total += i128::from(*initial_cash);
            let mut symbols = BTreeSet::new();
            symbols.extend(account.shares.keys().copied());
            symbols.extend(account.reserved_shares.keys().copied());
            symbols.extend(initial_shares.keys().copied());
            for &(owner, symbol) in expected_shares.keys() {
                if owner == *id { symbols.insert(symbol); }
            }
            for symbol in symbols {
                let owned = account.shares.get(&symbol).copied().unwrap_or(0);
                let reserved = account.reserved_shares.get(&symbol).copied().unwrap_or(0);
                if owned < 0 || reserved < 0 || reserved > owned ||
                   i128::from(reserved) != expected_shares.get(&(*id, symbol)).copied().unwrap_or(0) {
                    return false;
                }
                *account_shares_total.entry(symbol).or_default() += i128::from(owned);
                *initial_shares_total.entry(symbol).or_default() +=
                    i128::from(initial_shares.get(&symbol).copied().unwrap_or(0));
            }
        }
        if account_cash_total != initial_cash_total ||
            account_shares_total != initial_shares_total { return false; }
        self.fills.iter().all(|f| {
            if f.quantity <= 0 || f.price <= 0 ||
               i128::from(f.quantity) * i128::from(f.price) > MAX_NOTIONAL { return false; }
            let Some(&bi) = self.order_index.get(&f.buy) else { return false; };
            let Some(&si) = self.order_index.get(&f.sell) else { return false; };
            let b = &self.orders[bi]; let s = &self.orders[si];
            b.side == 0 && s.side == 1 && b.owner != s.owner && b.symbol == s.symbol
        })
    }
}

#[no_mangle]
pub extern "C" fn tx_core_abi_version() -> u32 { 2 }
#[no_mangle]
pub extern "C" fn tx_core_new() -> *mut Engine { Box::into_raw(Box::new(Engine::default())) }
/// Safety: `ptr` must be an owned tx_core_new handle, freed exactly once.
#[no_mangle]
pub unsafe extern "C" fn tx_core_free(ptr: *mut Engine) {
    if !ptr.is_null() { drop(Box::from_raw(ptr)); }
}
#[no_mangle]
pub unsafe extern "C" fn tx_core_register(ptr: *mut Engine, id: u64, cash: i64,
                                              a: i64, b: i64) -> i32 {
    match ptr.as_mut() { Some(e) => e.register(id, cash, a, b), None => NULL }
}
#[no_mangle]
pub unsafe extern "C" fn tx_core_add_initial_shares(ptr: *mut Engine,
    owner: u64, symbol: u32, quantity: i64) -> i32 {
    match ptr.as_mut() {
        Some(e) => e.add_opening_shares(owner, symbol, quantity),
        None => NULL,
    }
}
#[no_mangle]
pub unsafe extern "C" fn tx_core_place(ptr: *mut Engine, id: u64, owner: u64,
    symbol: u32, side: u32, kind: u32, quantity: i64, price: i64) -> i32 {
    match ptr.as_mut() {
        Some(e) => e.place(id, owner, symbol, side, kind, quantity, price),
        None => NULL,
    }
}
#[no_mangle]
pub unsafe extern "C" fn tx_core_cancel(ptr: *mut Engine, id: u64, owner: u64) -> i32 {
    match ptr.as_mut() { Some(e) => e.cancel(id, owner), None => NULL }
}
#[no_mangle]
pub unsafe extern "C" fn tx_core_cash(ptr: *const Engine, owner: u64) -> i64 {
    ptr.as_ref().and_then(|e| e.accounts.get(&owner).map(|a| a.cash)).unwrap_or(-1)
}
#[no_mangle]
pub unsafe extern "C" fn tx_core_reserved_cash(ptr: *const Engine, owner: u64) -> i64 {
    ptr.as_ref().and_then(|e| e.accounts.get(&owner).map(|a| a.reserved_cash)).unwrap_or(-1)
}
#[no_mangle]
pub unsafe extern "C" fn tx_core_shares(ptr: *const Engine, owner: u64, symbol: u32) -> i64 {
    ptr.as_ref().and_then(|e| e.accounts.get(&owner)
        .map(|a| a.shares.get(&symbol).copied().unwrap_or(0))).unwrap_or(-1)
}
#[no_mangle]
pub unsafe extern "C" fn tx_core_reserved_shares(ptr: *const Engine, owner: u64, symbol: u32) -> i64 {
    ptr.as_ref().and_then(|e| e.accounts.get(&owner)
        .map(|a| a.reserved_shares.get(&symbol).copied().unwrap_or(0))).unwrap_or(-1)
}
#[no_mangle]
pub unsafe extern "C" fn tx_core_order_remaining(ptr: *const Engine, id: u64) -> i64 {
    ptr.as_ref().and_then(|e| e.order_index.get(&id).map(|&i| e.orders[i].remaining)).unwrap_or(-1)
}
#[no_mangle]
pub unsafe extern "C" fn tx_core_fill_count(ptr: *const Engine) -> i64 {
    ptr.as_ref().map(|e| e.fills.len() as i64).unwrap_or(-1)
}
#[no_mangle]
pub unsafe extern "C" fn tx_core_fill_price(ptr: *const Engine, index: u64) -> i64 {
    ptr.as_ref().and_then(|e| e.fills.get(index as usize).map(|f| f.price)).unwrap_or(-1)
}
#[no_mangle]
pub unsafe extern "C" fn tx_core_fill_quantity(ptr: *const Engine, index: u64) -> i64 {
    ptr.as_ref().and_then(|e| e.fills.get(index as usize).map(|f| f.quantity)).unwrap_or(-1)
}
#[no_mangle]
pub unsafe extern "C" fn tx_core_fill_buy_order(ptr: *const Engine, index: u64) -> u64 {
    ptr.as_ref().and_then(|e| e.fills.get(index as usize).map(|f| f.buy)).unwrap_or(0)
}
#[no_mangle]
pub unsafe extern "C" fn tx_core_fill_sell_order(ptr: *const Engine, index: u64) -> u64 {
    ptr.as_ref().and_then(|e| e.fills.get(index as usize).map(|f| f.sell)).unwrap_or(0)
}
#[no_mangle]
pub unsafe extern "C" fn tx_core_verify(ptr: *const Engine) -> i32 {
    match ptr.as_ref() { Some(e) => if e.verify() { 1 } else { 0 }, None => NULL }
}

/// The journal contains only actual state-mutating commands.
/// Same-order idempotent retries are not duplicated.
#[no_mangle]
pub unsafe extern "C" fn tx_core_event_count(ptr: *const Engine) -> u64 {
    ptr.as_ref().map(|e| e.journal.len() as u64).unwrap_or(0)
}

/// Returns a pointer borrowed from the native engine. It becomes invalid on
/// the NEXT mutation or tx_core_free. Copy its fields immediately in Dart.
#[no_mangle]
pub unsafe extern "C" fn tx_core_event_at(
    ptr: *const Engine, index: u64) -> *const TxCoreEvent {
    ptr.as_ref().and_then(|e| e.journal.get(index as usize))
        .map(|ev| ev as *const TxCoreEvent).unwrap_or(std::ptr::null())
}

/// Replay a copied event. Returns 0 when its expected result was reproduced,
/// -5 on a parity mismatch. The caller must discard the engine on failure.
#[no_mangle]
pub unsafe extern "C" fn tx_core_replay_event(
    ptr: *mut Engine, event: *const TxCoreEvent) -> i32 {
    if event.is_null() { return NULL; }
    // Copy BEFORE borrowing the engine mutably. The caller may pass a
    // borrowed event from this same engine's journal: pushing a replayed
    // event can reallocate that Vec and invalidate the original pointer.
    let copied = std::ptr::read(event);
    match ptr.as_mut() {
        Some(engine) => engine.replay_event(&copied),
        None => NULL,
    }
}

/// Rebuild a new engine from the current journal (test oracle, not a snapshot).
/// The caller owns the returned handle; null means a deterministic replay
/// mismatch and no partial engine is returned.
#[no_mangle]
pub unsafe extern "C" fn tx_core_rebuild_from_events(
    ptr: *const Engine) -> *mut Engine {
    let Some(source) = ptr.as_ref() else { return std::ptr::null_mut(); };
    let mut rebuilt = Engine::default();
    for event in &source.journal {
        if rebuilt.replay_event(event) != 0 {
            return std::ptr::null_mut();
        }
    }
    if !rebuilt.verify() { return std::ptr::null_mut(); }
    Box::into_raw(Box::new(rebuilt))
}

#[no_mangle]
pub unsafe extern "C" fn tx_core_order_status(
    ptr: *const Engine, id: u64) -> i32 {
    ptr.as_ref().and_then(|e| e.order_index.get(&id)
        .map(|&i| e.orders[i].status)).unwrap_or(UNKNOWN)
}

#[no_mangle]
pub unsafe extern "C" fn tx_core_active_order_count(
    ptr: *const Engine) -> u64 {
    ptr.as_ref().map(|e| e.resting.values()
        .map(|book| book.len() as u64).sum()).unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn funded() -> Engine {
        let mut e = Engine::default();
        assert_eq!(e.register(1, 10_000, 0, 0), 0);
        assert_eq!(e.register(2, 0, 20, 0), 0);
        e
    }
    #[test]
    fn limit_reserves_cancel_releases_and_balances_conserve() {
        let mut e = funded();
        assert_eq!(e.place(10, 1, 0, 0, 0, 5, 100), OPEN);
        assert_eq!(e.accounts[&1].reserved_cash, 500);
        assert_eq!(e.place(11, 2, 0, 1, 0, 3, 100), FILLED);
        assert_eq!(e.fills.len(), 1);
        assert_eq!(e.fills[0].buy, 10);
        assert_eq!(e.accounts[&1].cash, 9700);
        assert_eq!(e.accounts[&1].reserved_cash, 200);
        assert_eq!(e.accounts[&1].shares[&0], 3);
        assert_eq!(e.cancel(10, 1), CANCELLED);
        assert_eq!(e.accounts[&1].reserved_cash, 0);
        assert!(e.verify());
    }
    #[test]
    fn price_then_fifo_and_no_invented_volume() {
        let mut e = funded();
        e.register(3, 0, 20, 0);
        e.place(20, 2, 0, 1, 0, 4, 102);
        e.place(21, 3, 0, 1, 0, 4, 101);
        e.place(22, 2, 0, 1, 0, 4, 101);
        assert_eq!(e.place(23, 1, 0, 0, 1, 9, 0), FILLED);
        let ids: Vec<_> = e.fills.iter().map(|f| f.sell).collect();
        assert_eq!(ids, vec![21, 22, 20]);
        assert_eq!(e.fills.iter().map(|f| f.quantity).sum::<i64>(), 9);
        assert!(e.verify());
    }
    #[test]
    fn rejects_self_trades_and_unfunded_orders_without_mutation() {
        let mut e = funded();
        e.accounts.get_mut(&1).unwrap().shares.insert(0, 2);
        e.initial.get_mut(&1).unwrap().1.insert(0, 2);
        assert_eq!(e.place(1, 1, 0, 1, 0, 1, 102), OPEN);
        assert_eq!(e.place(2, 1, 0, 0, 1, 1, 0), REJECTED);
        assert_eq!(e.place(3, 2, 0, 0, 0, 1, 100), REJECTED);
        assert_eq!(e.fills.len(), 0);
        assert!(e.verify());
    }
    #[test]
    fn rejects_conflicting_order_ids_and_preserves_idempotent_retries() {
        let mut e = funded();
        assert_eq!(e.place(1, 1, 0, 0, 0, 4, 100), OPEN);
        assert_eq!(e.place(1, 1, 0, 0, 0, 4, 100), OPEN);
        assert_eq!(e.place(1, 1, 0, 0, 0, 5, 100), CONFLICT);
        assert_eq!(e.orders.len(), 1);
        assert!(e.verify());
    }
    #[test]
    fn all_market_unmatched_remainder_is_cancelled() {
        let mut e = funded();
        assert_eq!(e.place(1, 1, 0, 0, 1, 10, 0), CANCELLED);
        assert_eq!(e.fills.len(), 0);
        assert!(e.verify());
    }

    #[test]
    fn post_only_rejects_a_cross_without_reserving_or_filling() {
        let mut e = funded();
        assert_eq!(e.place(80, 2, 0, 1, LIMIT_GTC, 5, 100), OPEN);
        assert_eq!(e.place(81, 1, 0, 0, POST_ONLY, 2, 101), REJECTED);
        assert_eq!(e.fills.len(), 0);
        assert_eq!(e.accounts[&1].reserved_cash, 0);
        assert_eq!(e.orders[e.order_index[&80]].remaining, 5);
        assert_eq!(e.resting.get(&(0, 1)).unwrap().len(), 1);
        assert!(e.verify());
    }

    #[test]
    fn ioc_releases_unfilled_limit_reservation_after_partial_fill() {
        let mut e = funded();
        assert_eq!(e.place(82, 2, 0, 1, LIMIT_GTC, 3, 100), OPEN);
        assert_eq!(e.place(83, 1, 0, 0, IOC, 5, 110), CANCELLED);
        assert_eq!(e.orders[e.order_index[&83]].remaining, 2);
        assert_eq!(e.accounts[&1].cash, 9_700);
        assert_eq!(e.accounts[&1].reserved_cash, 0);
        assert_eq!(e.accounts[&1].shares[&0], 3);
        assert_eq!(e.fills.len(), 1);
        assert_eq!(e.fills[0].quantity, 3);
        assert!(e.verify());
    }

    #[test]
    fn fok_is_atomic_until_all_visible_depth_is_available() {
        let mut e = funded();
        assert_eq!(e.place(84, 2, 0, 1, LIMIT_GTC, 2, 100), OPEN);
        assert_eq!(e.place(85, 1, 0, 0, FOK, 3, 100), REJECTED);
        assert_eq!(e.fills.len(), 0);
        assert_eq!(e.accounts[&1].reserved_cash, 0);
        assert_eq!(e.place(86, 2, 0, 1, LIMIT_GTC, 3, 101), OPEN);
        assert_eq!(e.place(87, 1, 0, 0, FOK, 5, 110), FILLED);
        assert_eq!(e.fills.iter().map(|f| f.quantity).collect::<Vec<_>>(),
                   vec![2, 3]);
        assert_eq!(e.accounts[&1].reserved_cash, 0);
        assert!(e.verify());
    }
    #[test]
    fn new_symbol_can_trade_without_changing_ffi_abi() {
        let mut e = funded();
        assert_eq!(e.add_opening_shares(2, 280, 7), 0);
        assert_eq!(e.place(71, 2, 280, 1, 0, 3, 80), OPEN);
        assert_eq!(e.place(72, 1, 280, 0, 1, 3, 0), FILLED);
        assert_eq!(e.accounts[&1].shares.get(&280), Some(&3));
        assert_eq!(e.accounts[&2].shares.get(&280), Some(&4));
        assert!(e.verify());
    }
    #[test]
    fn historical_orders_are_absent_from_the_live_book() {
        let mut e = funded();
        for n in 0..10u64 {
            assert_eq!(e.place(100 + 2*n, 2, 0, 1, 0, 1, 100), OPEN);
            assert_eq!(e.place(101 + 2*n, 1, 0, 0, 1, 1, 0), FILLED);
        }
        assert!(e.resting.values().all(|book| book.is_empty()));
        assert_eq!(e.orders.len(), 20);
        assert!(e.verify());
    }
    #[test]
    fn long_lived_market_verifies_after_repeated_fills() {
        let mut e = funded();
        for i in 0..250u64 {
            // Reserve, fill, account for available shares and capital.
            assert_eq!(e.place(2*i+1, 2, 0, 1, 0, 1, 1), OPEN);
            assert_eq!(e.place(2*i+2, 1, 0, 0, 1, 1, 0), FILLED);
            if i >= 19 { break; } // seller has only 20 shares
        }
        assert_eq!(e.fills.len(), 20);
        assert!(e.verify());
    }
    #[test]
    fn event_journal_cold_replay_matches_full_economic_state() {
        let mut engine = funded();
        engine.register(3, 0, 8, 0);
        engine.add_opening_shares(3, 9001, 5);
        assert_eq!(engine.place(100, 1, 0, 0, 0, 5, 100), OPEN);
        assert_eq!(engine.place(101, 2, 0, 1, 0, 3, 100), FILLED);
        assert_eq!(engine.cancel(100, 1), CANCELLED);
        assert_eq!(engine.place(102, 2, 0, 1, 0, 3, 102), OPEN);
        assert_eq!(engine.place(103, 1, 0, 0, 1, 8, 0), CANCELLED);
        assert_eq!(engine.place(104, 3, 9001, 1, 0, 2, 300), OPEN);
        assert_eq!(engine.place(105, 1, 9001, 0, 1, 2, 0), FILLED);
        assert!(engine.verify());
        let mut restored = Engine::default();
        for event in &engine.journal {
            assert_eq!(restored.replay_event(event), 0);
        }
        assert_eq!(restored, engine);
        assert!(restored.verify());
    }

    #[test]
    fn event_journal_skips_idempotent_and_rejected_preflight_actions() {
        let mut e = funded();
        let base = e.journal.len();
        assert_eq!(e.place(200, 1, 0, 0, 0, 2, 100), OPEN);
        assert_eq!(e.journal.len(), base + 1);
        assert_eq!(e.place(200, 1, 0, 0, 0, 2, 100), OPEN);
        assert_eq!(e.place(201, 9, 0, 0, 0, 2, 100), UNKNOWN);
        assert_eq!(e.cancel(200, 9), CONFLICT);
        assert_eq!(e.journal.len(), base + 1);
        assert!(e.verify());
    }

    #[test]
    fn event_replay_detects_tampered_execution_result() {
        let mut e = funded();
        e.place(30, 1, 0, 0, 0, 1, 100);
        let mut corrupted = e.journal.last().copied().unwrap();
        corrupted.expected_result = FILLED;
        let mut rebuilt = Engine::default();
        for event in e.journal.iter().take(2) {
            assert_eq!(rebuilt.replay_event(event), 0);
        }
        assert_eq!(rebuilt.replay_event(&corrupted), -5);
    }

    #[test]
    fn r43_append_only_sequence_audit_rejects_reorder_and_gaps() {
        let mut e = funded();
        // IOC-without-liquidity creates historical cancelled orders, not
        // hidden fills or reservations. All remain auditable after growth.
        for id in 1..=512_u64 {
            assert_eq!(e.place(id, 1, 0, 0, 1, 1, 0), CANCELLED);
        }
        assert_eq!(e.orders.len(), 512);
        assert_eq!(e.next_sequence, 512);
        assert!(e.verify());
        assert!(e.resting.values().all(|book| book.is_empty()));
        // ID maps and balances can remain intact even if chronology is
        // corrupt; rejecting this state must NOT depend on an unordered Set.
        e.orders[101].sequence = 101;
        assert!(!e.verify());
        e.orders[101].sequence = 102;
        assert!(e.verify());
        // A simple uniqueness Set would accept this out-of-order swap; the
        // contiguous chronological audit must reject it, too.
        e.orders[101].sequence = 103;
        e.orders[102].sequence = 102;
        assert!(!e.verify());
        e.orders[101].sequence = 102;
        e.orders[102].sequence = 103;
        assert!(e.verify());
        e.next_sequence += 1;
        assert!(!e.verify());
    }

    #[test]
    fn native_abi_rebuilds_the_same_order_book() {
        let mut e = funded();
        e.place(41, 2, 0, 1, 0, 5, 101);
        e.place(42, 2, 0, 1, 0, 5, 102);
        let pointer = &e as *const Engine;
        let recreated = unsafe { tx_core_rebuild_from_events(pointer) };
        assert!(!recreated.is_null());
        let other = unsafe { Box::from_raw(recreated) };
        assert_eq!(*other, e);
        assert_eq!(other.resting.values().map(|v| v.len()).sum::<usize>(), 2);
    }

}
