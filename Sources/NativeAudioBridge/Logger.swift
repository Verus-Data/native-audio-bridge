import os
import Foundation

/// Log levels that map to os.Logger methods.
/// Kept as an enum so ConfigurationManager can parse from env vars.
public enum LogLevel: String, CaseIterable, Comparable {
    case debug
    case info
    case error

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValueOrder < rhs.rawValueOrder
    }

    private var rawValueOrder: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .error: return 2
        }
    }
}

/// App-wide os.Logger instances organized by subsystem category.
extension os.Logger {
    public static let app = os.Logger(subsystem: "com.nativeaudiobridge", category: "app")
    public static let audio = os.Logger(subsystem: "com.nativeaudiobridge", category: "audio")
    public static let config = os.Logger(subsystem: "com.nativeaudiobridge", category: "config")
    public static let command = os.Logger(subsystem: "com.nativeaudiobridge", category: "command")
    public static let webhook = os.Logger(subsystem: "com.nativeaudiobridge", category: "webhook")
    public static let speech = os.Logger(subsystem: "com.nativeaudiobridge", category: "speech")
}

/// Wrapper that bridges our LogLevel to os.Logger calls.
/// Respects the configured minimum log level so debug/info can be silenced at runtime.
public final class AppLogger {
    public static let shared = AppLogger()

    private var minLevel: LogLevel = .info
    private let queue = DispatchQueue(label: "com.nativeaudiobridge.applogger", attributes: .concurrent)

    private init() {}

    public func setLogLevel(_ level: LogLevel) {
        queue.async(flags: .barrier) { [weak self] in
            self?.minLevel = level
        }
    }

    public var currentLevel: LogLevel {
        queue.sync(execute: { minLevel })
    }

    public func debug(_ message: String, category: os.Logger = .app) {
        guard queue.sync(execute: { minLevel <= .debug }) else { return }
        category.debug("\(message)")
    }

    public func info(_ message: String, category: os.Logger = .app) {
        guard queue.sync(execute: { minLevel <= .info }) else { return }
        category.info("\(message)")
    }

    public func error(_ message: String, category: os.Logger = .app) {
        // Errors always log regardless of level
        category.error("\(message)")
    }
}