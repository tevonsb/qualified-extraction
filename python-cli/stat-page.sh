#!/bin/bash
# Generate HTML statistics page
cd "$(dirname "$0")"
source venv/bin/activate 2>/dev/null || true
python stat-page.py "$@"
