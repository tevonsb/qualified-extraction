"""
Collector for Apple's knowledgeC.db (Screen Time, App Usage, Bluetooth, etc.)
"""

import sqlite3
from pathlib import Path
from .base import BaseCollector, make_hash


class KnowledgeCCollector(BaseCollector):
    """Extract data from Apple's Knowledge database."""

    name = "knowledgeC"
    source_paths = [
        "~/Desktop/knowledgeC.db",  # Your copied version
        "~/Library/Application Support/Knowledge/knowledgeC.db",  # Original location
    ]

    def extract(self) -> bool:
        """Extract all relevant data from knowledgeC."""
        source_path = self.source_db_dir / f"{self.name}.db"
        source = sqlite3.connect(source_path)

        try:
            self._extract_app_usage(source)
            self._extract_bluetooth(source)
            self._extract_notifications(source)
            self._extract_intents(source)
            self._extract_display_state(source)
            return True
        finally:
            source.close()

    def _get_device_mapping(self, source: sqlite3.Connection) -> dict:
        """Build a mapping of device IDs to models."""
        cursor = source.execute("""
            SELECT ZDEVICEID, ZMODEL FROM ZSYNCPEER
            WHERE ZDEVICEID IS NOT NULL AND ZMODEL IS NOT NULL
        """)
        return {row[0]: row[1] for row in cursor.fetchall()}

    def _extract_app_usage(self, source: sqlite3.Connection):
        """Extract app usage sessions."""
        print("  Extracting app usage...")
        device_map = self._get_device_mapping(source)

        cursor = source.execute("""
            SELECT
                o.Z_PK,
                o.ZVALUESTRING,
                o.ZSTARTDATE,
                o.ZENDDATE,
                s.ZDEVICEID
            FROM ZOBJECT o
            LEFT JOIN ZSOURCE s ON o.ZSOURCE = s.Z_PK
            WHERE o.ZSTREAMNAME = '/app/usage'
              AND o.ZVALUESTRING IS NOT NULL
            ORDER BY o.ZSTARTDATE
        """)

        for row in cursor:
            pk, bundle_id, start_date, end_date, device_id = row
            start_time = self.apple_to_unix(start_date)
            end_time = self.apple_to_unix(end_date)

            if start_time is None:
                continue

            duration = None
            if end_time and start_time:
                duration = end_time - start_time

            device_model = device_map.get(device_id) if device_id else None
            record_hash = make_hash(bundle_id, start_time, device_id)

            try:
                self.unified_db.execute("""
                    INSERT INTO app_usage
                    (record_hash, bundle_id, start_time, end_time, duration_seconds, device_id, device_model)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (record_hash, bundle_id, start_time, end_time, duration, device_id, device_model))
                self.records_added += 1
            except sqlite3.IntegrityError:
                self.records_skipped += 1

        self.unified_db.commit()

    def _extract_bluetooth(self, source: sqlite3.Connection):
        """Extract Bluetooth connection events."""
        print("  Extracting bluetooth connections...")

        cursor = source.execute("""
            SELECT
                o.Z_PK,
                o.ZSTARTDATE,
                o.ZENDDATE,
                sm.Z_DKBLUETOOTHMETADATAKEY__NAME,
                sm.Z_DKBLUETOOTHMETADATAKEY__ADDRESS,
                sm.Z_DKBLUETOOTHMETADATAKEY__DEVICETYPE,
                sm.Z_DKBLUETOOTHMETADATAKEY__PRODUCTID
            FROM ZOBJECT o
            LEFT JOIN ZSTRUCTUREDMETADATA sm ON o.ZSTRUCTUREDMETADATA = sm.Z_PK
            WHERE o.ZSTREAMNAME = '/bluetooth/isConnected'
            ORDER BY o.ZSTARTDATE
        """)

        for row in cursor:
            pk, start_date, end_date, name, address, device_type, product_id = row
            start_time = self.apple_to_unix(start_date)
            end_time = self.apple_to_unix(end_date)

            if start_time is None:
                continue

            duration = None
            if end_time and start_time:
                duration = end_time - start_time

            record_hash = make_hash(address, start_time)

            try:
                self.unified_db.execute("""
                    INSERT INTO bluetooth_connections
                    (record_hash, device_name, device_address, device_type, product_id, start_time, end_time, duration_seconds)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (record_hash, name, address, device_type, product_id, start_time, end_time, duration))
                self.records_added += 1
            except sqlite3.IntegrityError:
                self.records_skipped += 1

        self.unified_db.commit()

    def _extract_notifications(self, source: sqlite3.Connection):
        """Extract notification events."""
        print("  Extracting notifications...")

        cursor = source.execute("""
            SELECT
                o.Z_PK,
                o.ZVALUESTRING,
                o.ZSTARTDATE,
                s.ZBUNDLEID
            FROM ZOBJECT o
            LEFT JOIN ZSOURCE s ON o.ZSOURCE = s.Z_PK
            WHERE o.ZSTREAMNAME = '/notification/usage'
            ORDER BY o.ZSTARTDATE
        """)

        for row in cursor:
            pk, event_type, start_date, bundle_id = row
            timestamp = self.apple_to_unix(start_date)

            if timestamp is None:
                continue

            # Use bundle_id from source, fall back to event type if it looks like a bundle
            app_bundle = bundle_id or event_type
            if not app_bundle or app_bundle in ('Receive', 'Dismiss'):
                continue  # Skip if no app identifier

            record_hash = make_hash(app_bundle, timestamp, event_type)

            try:
                self.unified_db.execute("""
                    INSERT INTO notifications (record_hash, bundle_id, event_type, timestamp)
                    VALUES (?, ?, ?, ?)
                """, (record_hash, app_bundle, event_type, timestamp))
                self.records_added += 1
            except sqlite3.IntegrityError:
                self.records_skipped += 1

        self.unified_db.commit()

    def _extract_intents(self, source: sqlite3.Connection):
        """Extract Siri intents and shortcuts."""
        print("  Extracting intents...")

        cursor = source.execute("""
            SELECT
                o.Z_PK,
                o.ZSTARTDATE,
                sm.Z_DKINTENTMETADATAKEY__INTENTCLASS,
                sm.Z_DKINTENTMETADATAKEY__INTENTVERB,
                s.ZBUNDLEID
            FROM ZOBJECT o
            LEFT JOIN ZSTRUCTUREDMETADATA sm ON o.ZSTRUCTUREDMETADATA = sm.Z_PK
            LEFT JOIN ZSOURCE s ON o.ZSOURCE = s.Z_PK
            WHERE o.ZSTREAMNAME = '/app/intents'
            ORDER BY o.ZSTARTDATE
        """)

        for row in cursor:
            pk, start_date, intent_class, intent_verb, bundle_id = row
            timestamp = self.apple_to_unix(start_date)

            if timestamp is None:
                continue

            record_hash = make_hash(intent_class, bundle_id, timestamp)

            try:
                self.unified_db.execute("""
                    INSERT INTO intents (record_hash, intent_class, intent_verb, bundle_id, timestamp)
                    VALUES (?, ?, ?, ?, ?)
                """, (record_hash, intent_class, intent_verb, bundle_id, timestamp))
                self.records_added += 1
            except sqlite3.IntegrityError:
                self.records_skipped += 1

        self.unified_db.commit()

    def _extract_display_state(self, source: sqlite3.Connection):
        """Extract display on/off events."""
        print("  Extracting display state...")

        cursor = source.execute("""
            SELECT
                o.Z_PK,
                o.ZVALUEINTEGER,
                o.ZSTARTDATE,
                o.ZENDDATE
            FROM ZOBJECT o
            WHERE o.ZSTREAMNAME = '/display/isBacklit'
            ORDER BY o.ZSTARTDATE
        """)

        for row in cursor:
            pk, is_backlit, start_date, end_date = row
            start_time = self.apple_to_unix(start_date)
            end_time = self.apple_to_unix(end_date)

            if start_time is None:
                continue

            duration = None
            if end_time and start_time:
                duration = end_time - start_time

            record_hash = make_hash(start_time, is_backlit)

            try:
                self.unified_db.execute("""
                    INSERT INTO display_state (record_hash, is_backlit, start_time, end_time, duration_seconds)
                    VALUES (?, ?, ?, ?, ?)
                """, (record_hash, is_backlit, start_time, end_time, duration))
                self.records_added += 1
            except sqlite3.IntegrityError:
                self.records_skipped += 1

        self.unified_db.commit()
