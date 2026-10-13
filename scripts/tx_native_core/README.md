# Terminal X Native Core — Phase 2 (Rust ABI v2)

This is a **source-level, dependency-free Rust prototype**, **NOT** an active
Android runtime dependency. The signed Terminal X APK still uses the fully
verified Dart `TxEngine` with its existing SQLite schema-1 snapshots.

## Why split now?

- Future gameplay can evolve NPC strategies, asset classes, portfolios and
  chart rendering without cross-language accounting ambiguities.
- The authoritative matching and risk model should own the order book and
  account state for many game minutes; Flutter only consumes small committed
  result summaries, not copies of the complete execution history.
- Native logic must be deterministic, funded, free of fabricated fills,
  bounded in integer arithmetic, and regression-tested against Dart's engine.

## Module layout

- `Cargo.toml`: no third-party dependencies; builds `libterminal_x_core.so`
  (Android ARM64) or `.dylib/.dll/.so` for host parity tests.
- `src/lib.rs`: dynamic u32 symbols, active-only price/time order index, funded cash and share
  limits, limit reservations, cancel, market IOC, fill records, conservation
  audit, stable numeric API.
- `terminal_x_core.h`: independently compilable C ABI v2 contract.
- `lib/engine/tx_native_core_ffi.dart` (repo root): explicit, opt-in Dart bridge.

## Local native commands (only with Rust installed)

```sh
cd scripts/tx_native_core
cargo test --locked
cargo build --release --locked
```

**This repository's phone ZIP importer currently DOES NOT run `cargo`.** The
Rust sources are intentionally under `scripts/` because native `rust/`,
`android/`, and `.github/workflows/` paths are not accepted by that importer.
The native library is not loaded automatically. The Dart production engine
is unchanged until its replacements pass all of:

1. The same funded, seeded order sequences on Dart and Rust: identical
   per-order status, remaining, fills, cash, share reserves, FIFO ordering.
2. Full restore and 32/64-period checkpoint transitions without any loss of
   original v0.3.0 SQLite schema-1 snapshots.
3. ARM64 NDK/linker setup, signed upgrade APK, stable package ID/cert, and
   compiler toolchain pinned in GitHub CI.
4. On-device p50/p95 and long-history memory tests. Use a decision gate
   based on full-minute throughput, not isolated native benchmark numbers.

## ABI limits / planned migration

ABI v2 uses numeric account IDs (u64), order IDs (u64), two initially funded symbols (0/1), plus extensible u32 symbol IDs,
integer cents (i64) and quantities (i64). Current Dart game IDs are strings.
The future adapter must provide a stable lossless mapping, persisted alongside
snapshots. This prototype **does not support production import/export,
additional complex asset types, all rejected-order semantics or transactional rollback
on panic**, and must not replace the Dart engine until those gaps are closed.

A native crash must never advance the public game clock or acknowledge a
SQLite commit. Existing full ledger validation must remain authoritative.

## Phase 2: deterministic journal and Dart parity runner

- Every **state-mutating** registration, opening-inventory addition, order
  placement and successful cancellation is appended as a fixed-layout
  `TxCoreEvent`. Idempotent retries and invalid inputs do not duplicate events.
- ABI v2 exposes an immediately copied event view and native cold reconstruction
  (`tx_core_rebuild_from_events`), with every event's result checked. This is
  replay infrastructure, **not yet SQLite event persistence**.
- Native Rust unit tests compare the entire internal engine after replay;
  the optional Dart parity runner compares cash, reserves, holdings, live order
  states and actual fills on the same funded order sequence.
- Execute `bash scripts/tx_native_core/ci_native.sh` on a development runner
  with rustc, cargo, clang and optionally Dart; Android NDK is needed for the
  ARM64 target check. **No Rust compiler is present in this packaging
  environment**, so these tests are not claimed as executed.
- There is still no embedded `.so` in the signed Flutter APK. Before enabling
  native gameplay, finish native CI, packaging, deterministic equivalence,
  worker ownership, SQLite event commit and robust FFI failure handling.
