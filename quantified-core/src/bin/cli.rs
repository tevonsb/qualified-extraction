//! Command-line interface for quantified-core extraction

use quantified_core::{
    extract_all, extract_source, CollectorType, CoreExtractionConfig as ExtractionConfig,
};
use std::env;
use std::path::PathBuf;
use std::process;

fn print_usage() {
    eprintln!("Usage: quantified-core [OPTIONS] [COLLECTOR]");
    eprintln!();
    eprintln!("Extract macOS digital footprint data into a unified database.");
    eprintln!();
    eprintln!("Options:");
    eprintln!("  -o, --output <DIR>    Output directory (default: ./data)");
    eprintln!("  -q, --quiet           Suppress verbose output");
    eprintln!("  -h, --help            Show this help message");
    eprintln!();
    eprintln!("Collectors:");
    eprintln!("  messages              Extract iMessage/SMS data");
    eprintln!("  chrome                Extract Chrome browsing history");
    eprintln!("  knowledgec            Extract app usage, bluetooth, etc.");
    eprintln!("  podcasts              Extract Apple Podcasts history");
    eprintln!("  all                   Extract all sources (default)");
    eprintln!();
    eprintln!("Examples:");
    eprintln!("  quantified-core                    # Extract all sources");
    eprintln!("  quantified-core messages           # Extract only messages");
    eprintln!("  quantified-core -o ~/data chrome   # Extract Chrome to ~/data");
}

fn main() {
    let args: Vec<String> = env::args().collect();

    let mut output_dir = PathBuf::from("data");
    let mut verbose = true;
    let mut collector_name: Option<String> = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "-h" | "--help" => {
                print_usage();
                process::exit(0);
            }
            "-o" | "--output" => {
                if i + 1 >= args.len() {
                    eprintln!("Error: --output requires a directory path");
                    process::exit(1);
                }
                output_dir = PathBuf::from(&args[i + 1]);
                i += 2;
            }
            "-q" | "--quiet" => {
                verbose = false;
                i += 1;
            }
            arg if !arg.starts_with('-') => {
                collector_name = Some(arg.to_string());
                i += 1;
            }
            _ => {
                eprintln!("Error: Unknown option: {}", args[i]);
                eprintln!();
                print_usage();
                process::exit(1);
            }
        }
    }

    // Create config
    let config = ExtractionConfig::with_output_dir(output_dir).verbose(verbose);

    println!();
    println!("╔══════════════════════════════════════════════════════════╗");
    println!("║              QUANTIFIED EXTRACTION (RUST)                ║");
    println!("╚══════════════════════════════════════════════════════════╝");
    println!();

    // Run extraction
    let results = match collector_name.as_deref() {
        None | Some("all") => {
            // Extract all sources
            match extract_all(&config) {
                Ok(results) => results,
                Err(e) => {
                    eprintln!("Error: {}", e);
                    process::exit(1);
                }
            }
        }
        Some(name) => {
            // Extract specific source
            let collector_type = match CollectorType::from_str(name) {
                Some(ct) => ct,
                None => {
                    eprintln!("Error: Unknown collector: {}", name);
                    eprintln!("Available collectors: messages, chrome, knowledgec, podcasts");
                    process::exit(1);
                }
            };

            match extract_source(&config, collector_type) {
                Ok(result) => vec![result],
                Err(e) => {
                    eprintln!("Error: {}", e);
                    process::exit(1);
                }
            }
        }
    };

    // Print summary
    println!();
    println!("╔══════════════════════════════════════════════════════════╗");
    println!("║                      SUMMARY                             ║");
    println!("╚══════════════════════════════════════════════════════════╝");
    println!();

    let mut total_added = 0;
    let mut total_skipped = 0;
    let mut successful = 0;
    let mut failed = 0;

    for result in &results {
        let status = match result.status {
            quantified_core::types::ExtractionStatus::Completed => {
                successful += 1;
                "✓"
            }
            quantified_core::types::ExtractionStatus::Failed => {
                failed += 1;
                "✗"
            }
            quantified_core::types::ExtractionStatus::Running => "⋯",
        };

        println!(
            "  {} {:12} Added: {:6}  Skipped: {:6}",
            status, result.source, result.records_added, result.records_skipped
        );

        if let Some(error) = &result.error_message {
            println!("     Error: {}", error);
        }

        total_added += result.records_added;
        total_skipped += result.records_skipped;
    }

    println!();
    println!("  Total: {} added, {} skipped", total_added, total_skipped);
    println!("  Status: {} successful, {} failed", successful, failed);
    println!();

    if failed > 0 {
        process::exit(1);
    }
}
