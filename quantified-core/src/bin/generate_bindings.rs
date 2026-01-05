//! Helper tool to generate Swift bindings from the uniffi library
//!
//! Usage: cargo run --bin generate_bindings

use std::path::PathBuf;
use std::process::Command;

fn main() {
    println!("🔧 Generating Swift bindings for quantified-core...");

    // Get the project root directory
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let library_path = manifest_dir.join("target/release/libquantified_core.dylib");
    let out_dir = manifest_dir.join("target/swift-bindings");

    // Ensure output directory exists
    std::fs::create_dir_all(&out_dir).expect("Failed to create output directory");

    // Check if library exists
    if !library_path.exists() {
        eprintln!("❌ Library not found at: {}", library_path.display());
        eprintln!("   Run 'cargo build --release' first");
        std::process::exit(1);
    }

    println!("📦 Library: {}", library_path.display());
    println!("📁 Output: {}", out_dir.display());

    // Try to use uniffi-bindgen if available
    let status = Command::new("cargo")
        .args([
            "run",
            "--bin",
            "uniffi-bindgen",
            "--",
            "generate",
            "--library",
            library_path.to_str().unwrap(),
            "--language",
            "swift",
            "--out-dir",
            out_dir.to_str().unwrap(),
        ])
        .status();

    match status {
        Ok(s) if s.success() => {
            println!("✅ Swift bindings generated successfully!");
            println!("   Files created in: {}", out_dir.display());
        }
        _ => {
            eprintln!("⚠️  uniffi-bindgen not available");
            eprintln!("   Install with: cargo install uniffi-bindgen --version 0.28.0");
            eprintln!("   Or use the Swift module directly from Xcode");
        }
    }
}
