#!/bin/bash
#
# Qualified Extraction - One-click runner
#
# Usage:
#   ./run.sh           # Run all collectors and show stats
#   ./run.sh chrome    # Run specific collector only
#

cd "$(dirname "$0")"

# Activate virtual environment if it exists
if [ -d "venv" ]; then
    source venv/bin/activate
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              QUALIFIED EXTRACTION                        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Run extraction
python extract.py "$@"

# If no args provided, show stats after extraction
if [ $# -eq 0 ]; then
    echo ""
    python stats.py
fi
