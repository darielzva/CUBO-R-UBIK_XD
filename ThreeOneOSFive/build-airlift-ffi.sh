#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CORE="$ROOT/airlift-rust-core"
OUTPUT="$ROOT/AirliftFFI.xcframework"
TEMP_OUTPUT="$ROOT/AirliftFFI.tmp.xcframework"

source "$HOME/.cargo/env" 2>/dev/null || true
rustup target add aarch64-apple-ios aarch64-apple-ios-sim

cargo build --manifest-path "$CORE/Cargo.toml" --release --target aarch64-apple-ios
cargo build --manifest-path "$CORE/Cargo.toml" --release --target aarch64-apple-ios-sim

rm -rf "$TEMP_OUTPUT"
xcodebuild -create-xcframework \
  -library "$CORE/target/aarch64-apple-ios/release/libairlift_ffi.a" \
  -headers "$CORE/include" \
  -library "$CORE/target/aarch64-apple-ios-sim/release/libairlift_ffi.a" \
  -headers "$CORE/include" \
  -output "$TEMP_OUTPUT"

rm -rf "$OUTPUT"
mv "$TEMP_OUTPUT" "$OUTPUT"