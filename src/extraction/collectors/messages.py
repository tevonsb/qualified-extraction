"""
Collector for Apple Messages (iMessage/SMS) from chat.db
"""

import sqlite3
from pathlib import Path
from .base import BaseCollector, make_hash


class MessagesCollector(BaseCollector):
    """Extract data from Apple Messages database."""

    name = "messages"
    source_paths = [
        "~/Library/Messages/chat.db",
    ]

    def extract(self) -> bool:
        """Extract messages and chats."""
        source_path = self.source_db_dir / f"{self.name}.db"
        source = sqlite3.connect(source_path)

        try:
            self._extract_chats(source)
            self._extract_messages(source)
            return True
        finally:
            source.close()

    def _extract_chats(self, source: sqlite3.Connection):
        """Extract chat/conversation metadata."""
        print("  Extracting chats...")

        cursor = source.execute("""
            SELECT
                c.ROWID,
                c.guid,
                c.chat_identifier,
                c.display_name,
                (SELECT COUNT(*) FROM chat_handle_join WHERE chat_id = c.ROWID) as participant_count,
                (SELECT MAX(m.date) FROM message m
                 JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
                 WHERE cmj.chat_id = c.ROWID) as last_message_date
            FROM chat c
        """)

        for row in cursor:
            rowid, guid, identifier, display_name, participants, last_msg = row

            if not guid:
                continue

            last_message_time = self.apple_nano_to_unix(last_msg)
            record_hash = guid  # guid is already unique

            try:
                self.unified_db.execute("""
                    INSERT INTO chats
                    (record_hash, chat_identifier, display_name, participant_count, last_message_time)
                    VALUES (?, ?, ?, ?, ?)
                """, (record_hash, identifier, display_name, participants, last_message_time))
                self.records_added += 1
            except sqlite3.IntegrityError:
                self.records_skipped += 1

        self.unified_db.commit()

    def _extract_messages(self, source: sqlite3.Connection):
        """Extract individual messages."""
        print("  Extracting messages...")

        cursor = source.execute("""
            SELECT
                m.ROWID,
                m.guid,
                m.text,
                m.is_from_me,
                m.date,
                m.date_read,
                m.date_delivered,
                h.id as handle_id,
                c.guid as chat_guid,
                m.service,
                (SELECT COUNT(*) FROM attachment a
                 JOIN message_attachment_join maj ON a.ROWID = maj.attachment_id
                 WHERE maj.message_id = m.ROWID) as attachment_count
            FROM message m
            LEFT JOIN handle h ON m.handle_id = h.ROWID
            LEFT JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
            LEFT JOIN chat c ON cmj.chat_id = c.ROWID
            ORDER BY m.date
        """)

        for row in cursor:
            (rowid, guid, text, is_from_me, date, date_read, date_delivered,
             handle_id, chat_guid, service, attachment_count) = row

            if not guid:
                continue

            timestamp = self.apple_nano_to_unix(date)
            read_time = self.apple_nano_to_unix(date_read)
            delivered_time = self.apple_nano_to_unix(date_delivered)

            if timestamp is None:
                continue

            has_attachment = 1 if attachment_count and attachment_count > 0 else 0
            record_hash = guid  # guid is already unique

            try:
                self.unified_db.execute("""
                    INSERT INTO messages
                    (record_hash, text, is_from_me, timestamp, date_read, date_delivered,
                     handle_id, chat_id, service, has_attachment)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (record_hash, text, is_from_me, timestamp, read_time, delivered_time,
                      handle_id, chat_guid, service, has_attachment))
                self.records_added += 1
            except sqlite3.IntegrityError:
                self.records_skipped += 1

        self.unified_db.commit()
