#!/bin/bash
set -e

echo "🔧 Generating Swift bindings for quantified-core..."

# Build the library first
cd "$(dirname "$0")"
cargo build --release --lib

# Output directory for Swift bindings
OUT_DIR="../qualifiedApp/QualifiedApp/Generated"
mkdir -p "$OUT_DIR"

# Use uniffi-bindgen (Python) to generate Swift bindings
LIBRARY_PATH="target/release/libquantified_core.dylib"

# Check if uniffi-bindgen is installed
if ! command -v uniffi-bindgen &> /dev/null; then
    echo "uniffi-bindgen not found. Installing..."
    pip3 install uniffi-bindgen==0.28.0
fi

# Generate Swift bindings
uniffi-bindgen generate \
    --library "$LIBRARY_PATH" \
    --language swift \
    --out-dir "$OUT_DIR" \
    --no-format

echo "✅ Swift bindings generated in $OUT_DIR"
