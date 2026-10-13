"""Cheap structural check: it is NOT a substitute for cargo test or ARM64 CI."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent
rs = (root / 'src/lib.rs').read_text(encoding='utf-8')
h = (root / 'terminal_x_core.h').read_text(encoding='utf-8')
ffi = (root.parent.parent / 'lib/engine/tx_native_core_ffi.dart').read_text(encoding='utf-8')
exports = set(re.findall(r'pub\s+(?:unsafe\s+)?extern\s+"C"\s+fn\s+(tx_core_\w+)\s*\(', rs))
header = set(re.findall(r'\b(tx_core_\w+)\s*\(', h))
assert exports == header, (sorted(exports - header), sorted(header - exports))
required = {'tx_core_new','tx_core_free','tx_core_abi_version',
            'tx_core_register','tx_core_place','tx_core_cancel','tx_core_verify',
            'tx_core_cash','tx_core_reserved_cash','tx_core_shares',
            'tx_core_reserved_shares','tx_core_order_remaining',
            'tx_core_fill_count','tx_core_fill_price','tx_core_fill_quantity'}
assert required <= exports
lookup_names = set(re.findall(r"'\s*(tx_core_\w+)\s*'", ffi))
assert lookup_names <= header
assert 'static const int requiredAbiVersion = 2;' in ffi
assert 'fn tx_core_abi_version() -> u32 { 2 }' in rs
assert 'tx_core_rebuild_from_events' in exports
assert 'TxCoreEvent' in h
assert '#[cfg(test)]' in rs
assert 'fn price_then_fifo_and_no_invented_volume' in rs
assert 'fn limit_reserves_cancel_releases_and_balances_conserve' in rs
assert 'fn rejects_self_trades_and_unfunded_orders_without_mutation' in rs
assert 'fn long_lived_market_verifies_after_repeated_fills' in rs
assert 'r36 adds a deterministic command journal + replay test seam'.lower() in rs.lower()
print(f'Rust ABI static contract PASS: {len(header)} header functions = {len(exports)} Rust exports')
print(f'Dart ABI lookups PASS: {len(lookup_names)} exported functions')
print('Rust compile/unit tests: NOT RUN (rustc/cargo unavailable here)')
