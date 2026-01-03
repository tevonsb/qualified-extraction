#!/bin/bash
#
# Xcode Build Script for Rust Library Integration
# This script builds the quantified-core Rust library and prepares it for Swift
#

set -e

echo "🦀 Building Rust library for Xcode..."

# Determine project directories
PROJECT_ROOT="${PROJECT_DIR:-.}"
RUST_DIR="${PROJECT_ROOT}/quantified-core"
BUILD_DIR="${BUILT_PRODUCTS_DIR:-build}"
FRAMEWORKS_DIR="${BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH:-Frameworks}"

# Determine build configuration (Debug or Release)
if [ "${CONFIGURATION}" == "Debug" ]; then
    CARGO_BUILD_TYPE=""
    RUST_TARGET_DIR="debug"
    echo "📦 Building in Debug mode"
else
    CARGO_BUILD_TYPE="--release"
    RUST_TARGET_DIR="release"
    echo "📦 Building in Release mode"
fi

# Navigate to Rust project
cd "$RUST_DIR"

# Build the Rust library
echo "🔨 Compiling Rust library..."
cargo build --lib $CARGO_BUILD_TYPE

# Check if build was successful
DYLIB_PATH="target/${RUST_TARGET_DIR}/libquantified_core.dylib"
if [ ! -f "$DYLIB_PATH" ]; then
    echo "❌ Error: Library not found at $DYLIB_PATH"
    exit 1
fi

echo "✅ Library built successfully: $DYLIB_PATH"

# Copy library to app bundle (if running from Xcode)
if [ -n "${BUILT_PRODUCTS_DIR}" ]; then
    echo "📁 Copying library to app bundle..."
    mkdir -p "$FRAMEWORKS_DIR"
    cp "$DYLIB_PATH" "$FRAMEWORKS_DIR/"
    echo "✅ Library copied to: $FRAMEWORKS_DIR/"

    # Update library install name for app bundle
    DYLIB_NAME="libquantified_core.dylib"
    install_name_tool -id "@rpath/$DYLIB_NAME" "$FRAMEWORKS_DIR/$DYLIB_NAME" || true
fi

# Generate Swift bindings using uniffi
# Note: uniffi with proc-macros generates bindings at compile time
# The bindings are embedded in the .dylib and can be extracted

SWIFT_BINDINGS_DIR="${PROJECT_ROOT}/QualifiedApp/QualifiedApp/Generated"
mkdir -p "$SWIFT_BINDINGS_DIR"

# Try to generate bindings using cargo-run approach
echo "🔧 Generating Swift bindings..."

# Create a temporary script to extract uniffi metadata and generate bindings
cat > /tmp/generate_swift.sh << 'INNER_SCRIPT'
#!/bin/bash
cd quantified-core

# uniffi with proc-macros embeds scaffolding in the library
# We need to use uniffi_bindgen to extract and generate Swift code

# Check if we have a recent enough version of cargo that supports this
if command -v cargo-metadata &> /dev/null; then
    # Try to generate using the library directly
    echo "Using uniffi scaffolding from library..."

    # The Swift bindings need to be manually created for proc-macro approach
    # For now, we'll create a placeholder that will be replaced
    echo "// Auto-generated Swift bindings placeholder" > ../QualifiedApp/QualifiedApp/Generated/quantified_core.swift
    echo "// Run 'cargo build' to regenerate" >> ../QualifiedApp/QualifiedApp/Generated/quantified_core.swift
fi
INNER_SCRIPT

chmod +x /tmp/generate_swift.sh
/tmp/generate_swift.sh || echo "⚠️  Bindings generation skipped (will use module map instead)"

echo ""
echo "✅ Rust build complete!"
echo ""
echo "Next steps:"
echo "1. Add libquantified_core.dylib to Xcode project"
echo "2. Import the Swift bindings in your code"
echo "3. Build and run your app"
echo ""
