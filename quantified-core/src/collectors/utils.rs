//! Utility functions for collectors

use sha2::{Digest, Sha256};

/// Create a consistent hash from multiple values
/// Handles None values by converting them to empty strings
pub fn make_hash(parts: &[Option<String>]) -> String {
    let combined = parts
        .iter()
        .map(|part| part.as_deref().unwrap_or(""))
        .collect::<Vec<_>>()
        .join("|");

    let mut hasher = Sha256::new();
    hasher.update(combined.as_bytes());
    let result = hasher.finalize();

    // Return first 32 characters of hex string (16 bytes)
    hex::encode(&result[..16])
}

/// Create hash from string slices (convenience function)
pub fn make_hash_from_strs(parts: &[&str]) -> String {
    let parts: Vec<Option<String>> = parts.iter().map(|s| Some(s.to_string())).collect();
    make_hash(&parts)
}

/// Create hash from a mix of values that can be converted to strings
/// This is the most flexible version that accepts any ToString types
pub fn make_hash_from_values<T: AsRef<str>>(values: &[T]) -> String {
    let combined = values
        .iter()
        .map(|v| v.as_ref())
        .collect::<Vec<_>>()
        .join("|");

    let mut hasher = Sha256::new();
    hasher.update(combined.as_bytes());
    let result = hasher.finalize();

    // Return first 32 characters of hex string (16 bytes)
    hex::encode(&result[..16])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_make_hash() {
        let parts = vec![
            Some("value1".to_string()),
            Some("value2".to_string()),
            Some("value3".to_string()),
        ];
        let hash = make_hash(&parts);
        assert_eq!(hash.len(), 32); // 16 bytes as hex = 32 chars
    }

    #[test]
    fn test_make_hash_with_none() {
        let parts = vec![
            Some("value1".to_string()),
            None,
            Some("value3".to_string()),
        ];
        let hash = make_hash(&parts);
        assert_eq!(hash.len(), 32);
    }

    #[test]
    fn test_make_hash_consistency() {
        let parts1 = vec![Some("a".to_string()), Some("b".to_string())];
        let parts2 = vec![Some("a".to_string()), Some("b".to_string())];
        assert_eq!(make_hash(&parts1), make_hash(&parts2));
    }

    #[test]
    fn test_make_hash_from_strs() {
        let hash = make_hash_from_strs(&["hello", "world"]);
        assert_eq!(hash.len(), 32);
    }

    #[test]
    fn test_make_hash_from_values_mixed() {
        let s1 = String::from("hello");
        let s2 = "world";
        let hash = make_hash_from_values(&[s1.as_str(), s2]);
        assert_eq!(hash.len(), 32);
    }
}
