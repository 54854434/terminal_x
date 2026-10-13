#!/usr/bin/env bash
# Standalone pre-production native test gate; future GitHub Actions job.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$here/check_abi.py"
clang -std=c11 -Wall -Wextra -Werror -fsyntax-only "$here/ffi_abi_smoke.c"
command -v cargo >/dev/null
cargo test --locked --all-targets --manifest-path "$here/Cargo.toml"
cargo build --locked --release --manifest-path "$here/Cargo.toml"
if command -v dart >/dev/null 2>&1; then
  dart run "$here/dart_rust_parity.dart" \
    "$here/target/release/libterminal_x_core.so"
else
  echo 'Dart not installed: host Rust/Dart differential replay not executed'
fi
command -v rustup >/dev/null
rustup target add aarch64-linux-android
cargo check --locked --target aarch64-linux-android --manifest-path "$here/Cargo.toml"
echo 'Native source passes host tests and ARM64 Rust type-check (not APK integration)'
