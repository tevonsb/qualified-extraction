#!/bin/bash
#
# Qualified Extraction - One-click runner
#
# Usage:
#   ./run.sh           # Run all collectors and show stats
#   ./run.sh chrome    # Run specific collector only
#

cd "$(dirname "$0")"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              QUALIFIED EXTRACTION                        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Run extraction
python3 extract.py "$@"

# If no args provided, show stats after extraction
if [ $# -eq 0 ]; then
    echo ""
    python3 stats.py
fi
