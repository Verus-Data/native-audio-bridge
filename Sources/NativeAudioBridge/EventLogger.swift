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
    
    private func timestamp() -> String {
        dateFormatter.string(from: Date())
    }
    
    /// Mark the start of a listening session
    public func markStart() {
        startTime = Date()
        logger.info("🎤 Native Audio Bridge started — Listening for hot word...", category: .app)
    }
    
    /// Log hot word detection
    public func logHotWordDetected(hotWord: String) {
        logger.info("[\(timestamp())] 🎯 Hot word detected: \"\(hotWord)\" — Listening for command...", category: .speech)
    }
    
    /// Log command transcription (interim/partial results)
    public func logTranscriptionInterim(_ text: String) {
        logger.debug("[\(timestamp())] 📝 ... \(text)", category: .speech)
    }
    
    /// Log final command transcription
    public func logTranscriptionFinal(_ text: String) {
        logger.info("[\(timestamp())] ✓ Command: \"\(text)\"", category: .speech)
    }
    
    /// Log webhook dispatch status
    public func logWebhookDispatched(success: Bool, destination: String) {
        if success {
            logger.info("[\(timestamp())] 📤 Dispatched to \(destination)", category: .webhook)
        } else {
            logger.error("[\(timestamp())] ❌ Dispatch failed", category: .webhook)
        }
    }
    
    /// Log JSONL file output
    public func logJSONLSaved(path: String) {
        logger.info("[\(timestamp())] 💾 Saved to \(path)", category: .app)
    }
    
    /// Log silence detection (end of command)
    public func logSilenceDetected() {
        logger.debug("[\(timestamp())] 🔇 Silence detected, processing command...", category: .audio)
    }
    
    /// Log state transitions
    public func logStateChange(from oldState: BridgeState, to newState: BridgeState) {
        logger.debug("[\(timestamp())] ℹ️  State: \(oldState) → \(newState)", category: .app)
    }
    
    /// Log configuration loaded
    public func logConfigurationLoaded(config: Configuration) {
        var lines: [String] = ["⚙️  Configuration loaded:"]
        lines.append("   Hot word: \"\(config.hotWord)\"")
        lines.append("   Silence timeout: \(config.silenceTimeoutMs)ms")
        lines.append("   Webhook: \(config.webhookURL)")
        if let path = try? OutputManager(config: config, mode: .jsonlFile).jsonlFilePath() {
            lines.append("   JSONL: \(path)")
        }
        logger.info(lines.joined(separator: "\n"), category: .config)
    }
    
    /// Log errors
    public func logError(_ error: Error, context: String) {
        logger.error("[\(timestamp())] 💥 Error in \(context): \(error.localizedDescription)", category: .app)
    }
    
    /// Log listening status (periodic heartbeat)
    public func logListeningStatus() {
        logger.info("[\(timestamp())] 👂 Listening... say \"\(ConfigurationManager.defaultHotWord)\"", category: .app)
    }
    
    /// Log shutdown
    public func logShutdown() {
        if let start = startTime {
            let duration = Date().timeIntervalSince(start)
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            logger.info("[\(timestamp())] 👋 Shutdown (runtime: \(minutes)m \(seconds)s)", category: .app)
        } else {
            logger.info("[\(timestamp())] 👋 Shutdown", category: .app)
        }
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
