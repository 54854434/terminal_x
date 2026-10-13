# Terminal X v0.3.0 R31 performance handoff

Release candidate: v0.3.0+30, unchanged Android application ID `com.terminalx.game.terminal_x`, unchanged stable release signing chain. Import one `terminal_x_batch.zip` to GitHub main root through existing validated Actions workflow. All 40 active tests remain included.

## Changes

- Long-lived `TxPersistentMarketWorker` processes consecutive market operations on a dedicated Dart Isolate. Before publishing any user-visible account or minute, `TxTradingService` still commits and validates the SQLite revision. After commit it sends a lightweight journal-reset acknowledgment. An invalid player action resynchronizes the worker from the last committed state; unexpected tick failures remain fail-closed.
- `TxEngine` increments a private economic mutation serial on modifications and stamps only after a successful full release-mode invariant audit. A source with an unchanged audit stamp avoids one redundant complete scan during snapshot preparation. Full minute-end audits, TXD1 replay-equivalence, previous snapshot digest/CAS checks, and atomic rollback remain.
- `TxSqliteStore` prepares canonical JSON once from a typed, already-audited proposed session rather than export/import/export. The replay proof and compression logic are preserved. Additional historical retrieval avoids duplicate audits following full `TxSession.importJson`.
- Bounded 96-bar per-symbol chart read model in existing `storage_metadata`, atomically refreshed with committed revisions. It is bound to revision/head SHA-256 and a separate cache checksum. Corruption or stale revisions force the original verified-history fallback. It never supplies fills, account balances, or settlement values.
- `scripts/tx_r31_perf_benchmark.dart` compares persistent vs legacy per-minute latency distributions without real market data.

## Safety requirements

All former JSON, TXZ1 and TXD1 snapshots must remain valid; checkpoint policy retains user's 1–64 setting and hard recovery bound; do not downgrade to an old APK after TXD1 writes. Existing database and snapshots must not be deleted or silently repaired. Market-preview candles never execute orders.

## Verification

Static packaging/integrity checks only here; Dart SDK, Flutter CI, Android signing and phone performance benchmarks have NOT run. If CI fails, repair and rebuild the same `0.3.0+30` candidate. Never claim a numerical speedup before bench output is available.
