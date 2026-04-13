import Foundation
import os

/// Simple console event logger for user-facing output.
/// Logs hot word detection, command transcription, webhook status, and errors.
public final class EventLogger {
    public static let shared = EventLogger()
    
    private let logger = AppLogger.shared
    private let dateFormatter: DateFormatter
    private var startTime: Date?
    
    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        dateFormatter.timeZone = TimeZone.current
    }
    
    /// Mark the start of a listening session
    public func markStart() {
        startTime = Date()
        print("\n🎤 Native Audio Bridge started")
        print("   Listening for hot word...")
        print("   Press Ctrl+C to exit\n")
        logger.info("EventLogger session started", category: .app)
    }
    
    /// Log hot word detection
    public func logHotWordDetected(hotWord: String) {
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] 🎯 Hot word detected: \"\(hotWord)\"")
        print("              Listening for command...")
        logger.info("Hot word detected: \(hotWord)", category: .speech)
    }
    
    /// Log command transcription (interim/partial results)
    public func logTranscriptionInterim(_ text: String) {
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] 📝 ... \(text)")
        logger.debug("Interim transcription: \(text)", category: .speech)
    }
    
    /// Log final command transcription
    public func logTranscriptionFinal(_ text: String) {
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] ✓ Command: \"\(text)\"")
        logger.info("Final transcription: \(text)", category: .speech)
    }
    
    /// Log webhook dispatch status
    public func logWebhookDispatched(success: Bool, destination: String) {
        let timestamp = dateFormatter.string(from: Date())
        if success {
            print("[\(timestamp)] 📤 Dispatched to \(destination)")
            logger.info("Webhook dispatched to \(destination)", category: .webhook)
        } else {
            print("[\(timestamp)] ❌ Dispatch failed")
            logger.error("Webhook dispatch failed", category: .webhook)
        }
    }
    
    /// Log JSONL file output
    public func logJSONLSaved(path: String) {
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] 💾 Saved to \(path)")
        logger.info("Command saved to JSONL: \(path)", category: .app)
    }
    
    /// Log silence detection (end of command)
    public func logSilenceDetected() {
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] 🔇 Silence detected, processing command...")
        logger.debug("Silence detected", category: .audio)
    }
    
    /// Log state transitions
    public func logStateChange(from oldState: BridgeState, to newState: BridgeState) {
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] ℹ️  State: \(oldState) → \(newState)")
        logger.debug("State transition: \(oldState) → \(newState)", category: .app)
    }
    
    /// Log configuration loaded
    public func logConfigurationLoaded(config: Configuration) {
        print("\n⚙️  Configuration loaded:")
        print("   Hot word: \"\(config.hotWord)\"")
        print("   Silence timeout: \(config.silenceTimeoutMs)ms")
        print("   Webhook: \(config.webhookURL)")
        if let path = try? OutputManager(config: config, mode: .jsonlFile).jsonlFilePath() {
            print("   JSONL: \(path)")
        }
        print("")
        logger.info("Configuration loaded", category: .config)
    }
    
    /// Log errors
    public func logError(_ error: Error, context: String) {
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] 💥 Error in \(context): \(error.localizedDescription)")
        logger.error("Error in \(context): \(error)", category: .app)
    }
    
    /// Log listening status (periodic heartbeat)
    public func logListeningStatus() {
        let timestamp = dateFormatter.string(from: Date())
        logger.info("[\(timestamp)] 👂 Listening... say \"\(ConfigurationManager.defaultHotWord)\"", category: .app)
    }
    
    /// Log shutdown
    public func logShutdown() {
        let timestamp = dateFormatter.string(from: Date())
        if let start = startTime {
            let duration = Date().timeIntervalSince(start)
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            print("\n[\(timestamp)] 👋 Shutdown (runtime: \(minutes)m \(seconds)s)")
        } else {
            print("\n[\(timestamp)] 👋 Shutdown")
        }
        logger.info("EventLogger session ended", category: .app)
    }
}

extension BridgeState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle: return "idle"
        case .listening: return "listening"
        case .processing: return "processing"
        case .dispatching: return "dispatching"
        }
    }
}