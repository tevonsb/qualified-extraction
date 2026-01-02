#!/usr/bin/env python3
"""
View statistics from your digital footprint data.

Usage:
    python stats.py              # Show overview + today + week
    python stats.py today        # Today's activity
    python stats.py apps         # Detailed app usage
    python stats.py browsing     # Web browsing patterns
    python stats.py podcasts     # Podcast listening
    python stats.py messages     # Messaging stats
    python stats.py bluetooth    # Device connections
"""

import sys
from pathlib import Path

# Add src to path for imports
sys.path.insert(0, str(Path(__file__).parent / "src"))

from stats.stats import main

if __name__ == "__main__":
    main()
