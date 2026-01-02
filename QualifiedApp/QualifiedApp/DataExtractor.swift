//
//  DataExtractor.swift
//  QualifiedApp
//
//  Handles running the Python extraction scripts to collect data
//

import Foundation

class DataExtractor: ObservableObject {
    @Published var isExtracting = false
    @Published var extractionLog: [String] = []
    @Published var lastExtractionResult: ExtractionResult?

    struct ExtractionResult {
        let success: Bool
        let recordsAdded: Int
        let recordsSkipped: Int
        let duration: TimeInterval
        let errors: [String]
    }

    private let projectDir: URL
    private let pythonPath: String

    init() {
        // Find project directory
        projectDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("qualified-extraction")

        // Use system python3
        pythonPath = "/usr/bin/python3"
    }

    func runExtraction(completion: @escaping (Bool) -> Void) {
        guard !isExtracting else {
            addLog("⚠️ Extraction already in progress")
            completion(false)
            return
        }

        isExtracting = true
        extractionLog.removeAll()
        addLog("🚀 Starting extraction...")
        addLog("📂 Project directory: \(projectDir.path)")

        let startTime = Date()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let success = self.executeExtraction()
            let duration = Date().timeIntervalSince(startTime)

            DispatchQueue.main.async {
                self.isExtracting = false

                if success {
                    self.addLog("✅ Extraction completed in \(String(format: "%.1f", duration))s")
                } else {
                    self.addLog("❌ Extraction failed")
                }

                completion(success)
            }
        }
    }

    private func executeExtraction() -> Bool {
        let extractScript = projectDir.appendingPathComponent("extract.py")

        guard FileManager.default.fileExists(atPath: extractScript.path) else {
            addLog("❌ extract.py not found at \(extractScript.path)")
            return false
        }

        addLog("📄 Running extract.py...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [extractScript.path]
        process.currentDirectoryURL = projectDir

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Read output in real-time
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                DispatchQueue.main.async {
                    self?.addLog(output.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                DispatchQueue.main.async {
                    self?.addLog("⚠️ \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
        }

        do {
            try process.run()
            process.waitUntilExit()

            // Clean up handlers
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil

            let exitCode = process.terminationStatus

            if exitCode == 0 {
                addLog("✓ Python script completed successfully")
                return true
            } else {
                addLog("✗ Python script exited with code \(exitCode)")
                return false
            }
        } catch {
            addLog("❌ Failed to run Python script: \(error.localizedDescription)")
            return false
        }
    }

    private func addLog(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.extractionLog.append(message)
            print(message) // Also print to Xcode console
        }
    }

    func clearLog() {
        extractionLog.removeAll()
    }

    // Check if Python and required scripts exist
    func checkRequirements() -> (isValid: Bool, message: String) {
        // Check Python
        guard FileManager.default.fileExists(atPath: pythonPath) else {
            return (false, "Python3 not found at \(pythonPath)")
        }

        // Check extract.py
        let extractScript = projectDir.appendingPathComponent("extract.py")
        guard FileManager.default.fileExists(atPath: extractScript.path) else {
            return (false, "extract.py not found. Make sure the app is in the qualified-extraction directory.")
        }

        // Check src directory
        let srcDir = projectDir.appendingPathComponent("src")
        guard FileManager.default.fileExists(atPath: srcDir.path) else {
            return (false, "src directory not found")
        }

        return (true, "All requirements met")
    }
}
