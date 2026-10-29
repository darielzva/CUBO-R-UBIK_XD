#!/bin/bash
set -euo pipefail
set -x

ROOT="$(cd "$(dirname "$0")" && pwd)"
CORE="$ROOT/airlift-rust-core"
OUTPUT="$ROOT/AirliftFFI.xcframework"
TEMP_OUTPUT="$ROOT/AirliftFFI.tmp.xcframework"

# Verificar que el codigo Rust exista (si es submodulo, checkout necesita submodules: recursive)
if [ ! -f "$CORE/Cargo.toml" ]; then
  echo "ERROR: no existe $CORE/Cargo.toml"
  ls -la "$ROOT"
  exit 1
fi

if [ ! -d "$CORE/include" ]; then
  echo "ERROR: no existe la carpeta de headers $CORE/include"
  ls -la "$CORE"
  exit 1
fi

# Solo cargar el entorno de cargo si cargo no esta en el PATH (uso local)
if ! command -v cargo >/dev/null 2>&1 && [ -f "$HOME/.cargo/env" ]; then
  set +u
  # shellcheck disable=SC1091
  source "$HOME/.cargo/env"
  set -u
fi

cargo --version
rustup --version

rustup target add aarch64-apple-ios aarch64-apple-ios-sim

cargo build --manifest-path "$CORE/Cargo.toml" --release --target aarch64-apple-ios
cargo build --manifest-path "$CORE/Cargo.toml" --release --target aarch64-apple-ios-sim

DEVICE_LIB="$CORE/target/aarch64-apple-ios/release/libairlift_ffi.a"
SIM_LIB="$CORE/target/aarch64-apple-ios-sim/release/libairlift_ffi.a"

for lib in "$DEVICE_LIB" "$SIM_LIB"; do
  if [ ! -f "$lib" ]; then
    echo "ERROR: no se genero $lib"
    echo "Revisa que [lib] en Cargo.toml tenga crate-type = [\"staticlib\"] y que el nombre sea airlift_ffi"
    exit 1
  fi
done

rm -rf "$TEMP_OUTPUT"
xcodebuild -create-xcframework \
  -library "$DEVICE_LIB" \
  -headers "$CORE/include" \
  -library "$SIM_LIB" \
  -headers "$CORE/include" \
  -output "$TEMP_OUTPUT"

rm -rf "$OUTPUT"
mv "$TEMP_OUTPUT" "$OUTPUT"

echo "OK: $OUTPUT"