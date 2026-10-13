# Terminal X Native Core — Phase 2 (Rust ABI v2)

This is a **dependency-free Rust runtime used by the Android market worker**.
The signed Terminal X ARM64 APK packages the verified `.so`; Dart keeps the
existing SQLite schema-1 projection and UI snapshot format.

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
  limits, limit reservations, cancel, maker-price fills, market/IOC/FOK and
  post-only policies, fill records, conservation audit, stable numeric API.
  audit, stable numeric API.
- `terminal_x_core.h`: independently compilable C ABI v2 contract.
- `lib/engine/tx_native_core_ffi.dart` (repo root): explicit per-isolate Dart bridge.

## Local native commands (only with Rust installed)

```sh
cd scripts/tx_native_core
cargo test --locked
cargo build --release --locked
```

The phone ZIP importer runs the pinned Rust ARM64 build inside GitHub Actions
and stages the `.so` into the generated Android app. The Android production
worker loads it explicitly and fails closed if it is unavailable. Required
release gates remain:

1. The same funded, seeded order sequences on Dart and Rust: identical
   per-order status, remaining, fills, cash, share reserves, FIFO ordering.
2. Full restore and 32/64-period checkpoint transitions without any loss of
   original v0.3.0 SQLite schema-1 snapshots.
3. ARM64 NDK/linker setup, signed upgrade APK, stable package ID/cert, and
   compiler toolchain pinned in GitHub CI.
4. On-device p50/p95 and long-history memory tests. Use a decision gate
   based on full-minute throughput, not isolated native benchmark numbers.

## ABI limits

ABI v2 uses numeric account IDs (u64), order IDs (u64), two funded game
symbols (0/1), plus extensible u32 symbol IDs, integer cents (i64) and
quantities (i64). The Dart worker adapter persists the lossless string-to-
numeric mapping as the native event journal. The current runtime does not
support arbitrary complex asset types or transactional rollback on a native
panic; a native failure therefore blocks the worker and never falls back to
Dart execution on Android.

A native crash must never advance the public game clock or acknowledge a
SQLite commit. Existing full ledger validation must remain authoritative.

## Phase 2: deterministic journal and Dart parity runner

- Every **state-mutating** registration, opening-inventory addition, order
  placement and successful cancellation is appended as a fixed-layout
  `TxCoreEvent`. Idempotent retries and invalid inputs do not duplicate events.
- ABI v2 exposes an immediately copied event view and native cold reconstruction
  (`tx_core_rebuild_from_events`), with every event's result checked. The Dart
  adapter carries the same journal through the existing SQLite snapshot/delta
  format.
- Native Rust unit tests compare the entire internal engine after replay;
  the optional Dart parity runner compares cash, reserves, holdings, live order
  states and actual fills on the same funded order sequence.
- Execute `bash scripts/tx_native_core/ci_native.sh` on a development runner
  with rustc, cargo, clang and optionally Dart; Android NDK is needed for the
  ARM64 target check. A prior handoff compiled Rust 1.88.0 and ran its native
  tests, but the v0.3.5 execution-policy changes in this working tree require
  a fresh Cargo/Flutter/Dart parity run before release.
- The signed Android ARM64 APK now embeds the `.so` and the persistent market
  worker owns the native handle. Before calling a build production-ready,
  still require native CI, deterministic equivalence, cold restore, and
  on-device long-history performance evidence.
