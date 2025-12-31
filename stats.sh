#!/bin/bash
# Quick stats viewer
cd "$(dirname "$0")"
python3 stats.py "$@"
