"""
Data extraction from macOS system databases.
"""

from .schema import init_database, SCHEMA
from .collectors import (
    BaseCollector,
    KnowledgeCCollector,
    MessagesCollector,
    ChromeCollector,
    PodcastsCollector,
)

__all__ = [
    'init_database',
    'SCHEMA',
    'BaseCollector',
    'KnowledgeCCollector',
    'MessagesCollector',
    'ChromeCollector',
    'PodcastsCollector',
]
