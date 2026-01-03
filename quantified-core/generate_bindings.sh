#!/bin/bash
set -e

echo "🦀 Building Rust library..."
cargo build --lib --release

echo ""
echo "📦 Generating Swift bindings with uniffi..."

# Use cargo run with a small helper program to generate bindings
# uniffi-bindgen is a library, so we'll use it programmatically

cat > /tmp/uniffi_gen.rs << 'EOF'
fn main() {
    uniffi::uniffi_bindgen_main()
}
EOF

# Generate Swift bindings using uniffi
cargo run --bin uniffi-bindgen generate \
    --library target/release/libquantified_core.dylib \
    --language swift \
    --out-dir target/swift-bindings 2>&1 || {

    # If that doesn't work, try using uniffi's scaffolding command
    echo "Trying alternative method..."

    # Create a temporary Rust program to generate bindings
    mkdir -p target/bindgen-helper
    cat > target/bindgen-helper/Cargo.toml << 'TOML'
[package]
name = "bindgen-helper"
version = "0.1.0"
edition = "2021"

[dependencies]
uniffi = { version = "0.28", features = ["bindgen"] }
TOML

    cat > target/bindgen-helper/src/main.rs << 'RUST'
use uniffi_bindgen::bindings::swift;
use std::path::PathBuf;

fn main() {
    let library_path = PathBuf::from("../../target/release/libquantified_core.dylib");
    let out_dir = PathBuf::from("../../target/swift-bindings");

    std::fs::create_dir_all(&out_dir).expect("Failed to create output directory");

    println!("Generating Swift bindings...");
    println!("Library: {:?}", library_path);
    println!("Output: {:?}", out_dir);

    // This will be replaced with the actual uniffi binding generation
    eprintln!("Note: Manual binding generation required");
}
RUST

    cd target/bindgen-helper
    cargo run
    cd ../..
}

echo ""
echo "✅ Done! Swift bindings should be in target/swift-bindings/"
ls -lh target/swift-bindings/ 2>/dev/null || echo "⚠️  Bindings not generated - uniffi-bindgen CLI not available"
echo ""
echo "Note: If bindings weren't generated, you'll need to use uniffi from Xcode build phase"
