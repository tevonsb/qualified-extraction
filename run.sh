#!/bin/bash
#
# Digital Self Extraction - One-click runner
#
# Usage:
#   ./run.sh           # Run all collectors and show stats
#   ./run.sh --stats   # Just show stats
#   ./run.sh chrome    # Run specific collector
#

cd "$(dirname "$0")"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           DIGITAL SELF EXTRACTION                        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Run extraction
python3 extract.py "$@"

# If no args provided, show stats after extraction
if [ $# -eq 0 ]; then
    echo ""
    python3 extract.py --stats
fi
