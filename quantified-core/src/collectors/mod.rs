//! Data collectors for various macOS databases

pub mod base;
pub mod chrome;
pub mod knowledgec;
pub mod messages;
pub mod podcasts;
pub mod utils;

pub use base::Collector;

use crate::error::Result;
use crate::types::{CollectorType, ExtractionConfig};
use rusqlite::Connection;

/// Create a collector for the given type
pub fn create_collector<'a>(
    collector_type: CollectorType,
    config: &'a ExtractionConfig,
    unified_db: &'a Connection,
) -> Result<Box<dyn Collector + 'a>> {
    match collector_type {
        CollectorType::Messages => {
            Ok(Box::new(messages::MessagesCollector::new(config, unified_db)?))
        }
        CollectorType::Chrome => {
            Ok(Box::new(chrome::ChromeCollector::new(config, unified_db)?))
        }
        CollectorType::KnowledgeC => {
            Ok(Box::new(knowledgec::KnowledgeCCollector::new(config, unified_db)?))
        }
        CollectorType::Podcasts => {
            Ok(Box::new(podcasts::PodcastsCollector::new(config, unified_db)?))
        }
    }
}
