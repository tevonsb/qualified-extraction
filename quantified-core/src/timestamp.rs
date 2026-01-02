//! Timestamp conversion utilities for different epoch formats

use crate::error::{Error, Result};

/// Apple's epoch starts at 2001-01-01 00:00:00 UTC
const APPLE_EPOCH_OFFSET: i64 = 978307200;

/// Chrome's epoch starts at 1601-01-01 (Windows FILETIME)
const CHROME_EPOCH_OFFSET: i64 = 11644473600;

/// Convert Apple timestamp (seconds since 2001-01-01) to Unix timestamp
pub fn apple_to_unix(apple_timestamp: f64) -> Result<i64> {
    if apple_timestamp <= 0.0 {
        return Err(Error::InvalidTimestamp(format!(
            "Apple timestamp must be positive: {}",
            apple_timestamp
        )));
    }
    Ok((apple_timestamp as i64) + APPLE_EPOCH_OFFSET)
}

/// Convert Apple timestamp (seconds since 2001-01-01) to Unix timestamp, returning None for invalid values
pub fn apple_to_unix_opt(apple_timestamp: Option<f64>) -> Option<i64> {
    apple_timestamp.and_then(|ts| {
        if ts <= 0.0 {
            None
        } else {
            Some((ts as i64) + APPLE_EPOCH_OFFSET)
        }
    })
}

/// Convert Apple nanosecond timestamp to Unix timestamp
pub fn apple_nano_to_unix(apple_nano: i64) -> Result<i64> {
    if apple_nano <= 0 {
        return Err(Error::InvalidTimestamp(format!(
            "Apple nano timestamp must be positive: {}",
            apple_nano
        )));
    }
    Ok((apple_nano / 1_000_000_000) + APPLE_EPOCH_OFFSET)
}

/// Convert Apple nanosecond timestamp to Unix timestamp, returning None for invalid values
pub fn apple_nano_to_unix_opt(apple_nano: Option<i64>) -> Option<i64> {
    apple_nano.and_then(|ts| {
        if ts <= 0 {
            None
        } else {
            Some((ts / 1_000_000_000) + APPLE_EPOCH_OFFSET)
        }
    })
}

/// Convert Chrome/WebKit timestamp (microseconds since 1601-01-01) to Unix timestamp
pub fn chrome_to_unix(chrome_timestamp: i64) -> Result<i64> {
    if chrome_timestamp <= 0 {
        return Err(Error::InvalidTimestamp(format!(
            "Chrome timestamp must be positive: {}",
            chrome_timestamp
        )));
    }
    // Chrome uses microseconds since 1601-01-01
    Ok((chrome_timestamp / 1_000_000) - CHROME_EPOCH_OFFSET)
}

/// Convert Chrome/WebKit timestamp to Unix timestamp, returning None for invalid values
pub fn chrome_to_unix_opt(chrome_timestamp: Option<i64>) -> Option<i64> {
    chrome_timestamp.and_then(|ts| {
        if ts <= 0 {
            None
        } else {
            Some((ts / 1_000_000) - CHROME_EPOCH_OFFSET)
        }
    })
}

/// Get current Unix timestamp
pub fn now_unix() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("System time before UNIX epoch")
        .as_secs() as i64
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_apple_to_unix() {
        // Test a known timestamp: 2023-01-01 00:00:00 UTC
        // In Apple time: 694224000 (seconds since 2001-01-01)
        // In Unix time: 1672531200 (seconds since 1970-01-01)
        let apple_ts = 694224000.0;
        let unix_ts = apple_to_unix(apple_ts).unwrap();
        assert_eq!(unix_ts, 1672531200);
    }

    #[test]
    fn test_apple_to_unix_opt() {
        assert_eq!(apple_to_unix_opt(Some(694224000.0)), Some(1672531200));
        assert_eq!(apple_to_unix_opt(Some(0.0)), None);
        assert_eq!(apple_to_unix_opt(Some(-1.0)), None);
        assert_eq!(apple_to_unix_opt(None), None);
    }

    #[test]
    fn test_apple_nano_to_unix() {
        // Same test but with nanoseconds
        let apple_nano = 694224000_000_000_000i64;
        let unix_ts = apple_nano_to_unix(apple_nano).unwrap();
        assert_eq!(unix_ts, 1672531200);
    }

    #[test]
    fn test_chrome_to_unix() {
        // Chrome timestamp for 2023-01-01 00:00:00 UTC
        // Unix timestamp: 1672531200
        // Chrome epoch offset: 11644473600 seconds
        // Total seconds from 1601: 1672531200 + 11644473600 = 13317004800
        // In microseconds: 13317004800000000
        let chrome_ts = 13317004800000000i64;
        let unix_ts = chrome_to_unix(chrome_ts).unwrap();
        assert_eq!(unix_ts, 1672531200);
    }

    #[test]
    fn test_invalid_timestamps() {
        assert!(apple_to_unix(0.0).is_err());
        assert!(apple_to_unix(-1.0).is_err());
        assert!(apple_nano_to_unix(0).is_err());
        assert!(chrome_to_unix(0).is_err());
    }
}
