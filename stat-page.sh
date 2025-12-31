#!/bin/bash
# Generate HTML statistics page
cd "$(dirname "$0")"
python3 stat-page.py "$@"
