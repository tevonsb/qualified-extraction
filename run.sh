#!/bin/bash
#
# Qualified Extraction - One-click runner (Rust version)
#
# Usage:
#   ./run.sh           # Run all collectors and show stats
#   ./run.sh chrome    # Run specific collector only
#

cd "$(dirname "$0")"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              QUALIFIED EXTRACTION (RUST)                 ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Build the Rust binary if needed
if [ ! -f "quantified-core/target/release/quantified-core" ]; then
    echo "Building Rust binary (first time only)..."
    cd quantified-core
    cargo build --release
    cd ..
    echo ""
fi

# Run extraction
./quantified-core/target/release/quantified-core "$@"

# If no args provided, show stats after extraction
if [ $# -eq 0 ]; then
    echo ""
    if [ -d "venv" ]; then
        source venv/bin/activate 2>/dev/null
    fi
    python3 stats.py
fi
