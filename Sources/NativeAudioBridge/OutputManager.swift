import Foundation
import os

/// Manages output destinations for processed commands.
/// Supports webhook dispatch and JSONL file output.
public final class OutputManager {
    private let webhookDispatcher: WebhookDispatcher?
    private let jsonlPath: URL?
    private let logger = AppLogger.shared
    
    /// Output modes supported by the manager
    public enum OutputMode {
        case webhook
        case jsonlFile
        case both
    }
    
    /// Current output mode
    public private(set) var mode: OutputMode
    
    /// Initialize with configuration
    public init(config: Configuration, mode: OutputMode = .webhook) throws {
        self.mode = mode
        
        // Setup webhook if needed
        if mode == .webhook || mode == .both {
            self.webhookDispatcher = try WebhookDispatcher(
                webhookURL: config.webhookURL,
                bearerToken: config.webhookToken
            )
        } else {
            self.webhookDispatcher = nil
        }
        
        // Setup JSONL file if needed
        if mode == .jsonlFile || mode == .both {
            let fileManager = FileManager.default
            let docsURL = try fileManager.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.jsonlPath = docsURL.appendingPathComponent("native-audio-bridge-commands.jsonl")
        } else {
            self.jsonlPath = nil
        }
        
        logger.info("OutputManager initialized with mode: \(mode)", category: .app)
    }
    
    /// Switch output mode at runtime
    public func setMode(_ newMode: OutputMode) throws {
        guard newMode != mode else { return }
        
        // Re-initialize if switching to/from modes that require different setup
        if (newMode == .webhook || newMode == .both) && webhookDispatcher == nil {
            throw OutputError.webhookNotConfigured
        }
        
        self.mode = newMode
        logger.info("Output mode switched to: \(newMode)", category: .app)
    }
    
    /// Output a processed command to configured destinations
    public func output(_ payload: WebhookPayload) async throws {
        let dispatchGroup = DispatchGroup()
        var errors: [Error] = []
        
        // Webhook output
        if let dispatcher = webhookDispatcher, (mode == .webhook || mode == .both) {
            dispatchGroup.enter()
            Task {
                do {
                    try await dispatcher.dispatch(payload: payload)
                    logger.debug("Webhook dispatch succeeded", category: .webhook)
                } catch {
                    errors.append(error)
                    logger.error("Webhook dispatch failed: \(error)", category: .webhook)
                }
                dispatchGroup.leave()
            }
        }
        
        // JSONL file output
        if let path = jsonlPath, (mode == .jsonlFile || mode == .both) {
            dispatchGroup.enter()
            do {
                try await appendToJSONL(payload: payload, at: path)
                logger.debug("JSONL append succeeded", category: .app)
            } catch {
                errors.append(error)
                logger.error("JSONL append failed: \(error)", category: .app)
            }
            dispatchGroup.leave()
        }
        
        // Wait with timeout
        let result = dispatchGroup.wait(timeout: .now() + 10)
        if result == .timedOut {
            logger.error("Output operation timed out", category: .app)
            throw OutputError.timeout
        }
        
        // Report if any errors occurred
        if !errors.isEmpty {
            throw OutputError.partialFailure(errors)
        }
    }
    
    /// Append payload to JSONL file
    private func appendToJSONL(payload: WebhookPayload, at path: URL) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        
        let data = try encoder.encode(payload)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw OutputError.encodingFailed
        }
        
        let line = jsonString + "\n"
        guard let lineData = line.data(using: .utf8) else {
            throw OutputError.encodingFailed
        }
        
        // Use file coordinator for thread-safe writes
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        
        coordinator.coordinate(writingItemAt: path, options: .forMerging, error: &coordinatorError) { url in
            if FileManager.default.fileExists(atPath: url.path) {
                // Append to existing file
                if let fileHandle = try? FileHandle(forWritingTo: url) {
                    _ = try? fileHandle.seekToEnd()
                    try? fileHandle.write(contentsOf: lineData)
                    try? fileHandle.close()
                }
            } else {
                // Create new file
                try? lineData.write(to: url)
            }
        }
        
        if let error = coordinatorError {
            throw OutputError.fileWriteFailed(error)
        }
    }
    
    /// Get the path to the JSONL file (for user info)
    public func jsonlFilePath() -> String? {
        return jsonlPath?.path
    }
}

/// Errors that can occur during output operations
public enum OutputError: Error {
    case webhookNotConfigured
    case encodingFailed
    case fileWriteFailed(Error)
    case timeout
    case partialFailure([Error])
}

extension OutputMode: CustomStringConvertible {
    public var description: String {
        switch self {
        case .webhook: return "webhook"
        case .jsonlFile: return "jsonl-file"
        case .both: return "both"
        }
    }
}