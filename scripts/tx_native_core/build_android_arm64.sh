#!/usr/bin/env bash
# Native build stage for a FUTURE trusted CI workflow. Do not invoke before
# parity tests and release gate are passed. Does not modify pubspec or signing.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
crate="$repo/scripts/tx_native_core"
: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to a pinned Android NDK installation}"
: "${TX_RUST_NATIVE_ENABLED:?Explicitly set TX_RUST_NATIVE_ENABLED=1 after review}"
[[ "$TX_RUST_NATIVE_ENABLED" == "1" ]] || { echo 'Native release gate is disabled' >&2; exit 2; }
command -v cargo >/dev/null
command -v rustup >/dev/null
rustup target add aarch64-linux-android
linker="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang"
[[ -x "$linker" ]] || { echo "Expected pinned NDK linker missing: $linker" >&2; exit 2; }
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$linker"
cargo test --locked --manifest-path "$crate/Cargo.toml"
cargo build --locked --release --target aarch64-linux-android --manifest-path "$crate/Cargo.toml"
so="$crate/target/aarch64-linux-android/release/libterminal_x_core.so"
[[ -s "$so" ]] || { echo 'Native .so missing' >&2; exit 2; }
output="$repo/android/app/src/main/jniLibs/arm64-v8a"
mkdir -p "$output"
cp "$so" "$output/libterminal_x_core.so"
echo "Rust ARM64 library staged in $output (app still requires explicit Dart backend activation)"
