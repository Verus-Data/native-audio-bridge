import Foundation

public enum LogLevel: Int, Comparable, CustomStringConvertible {
    case debug = 0
    case info = 1
    case error = 2

    public var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .error: return "ERROR"
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public final class Logger {
    public static let shared = Logger()
    private var minLevel: LogLevel = .info
    private let queue = DispatchQueue(label: "com.nativeaudiobridge.logger", attributes: .concurrent)
    private let dateFormatter: DateFormatter

    private init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        self.dateFormatter = formatter
    }

    public func setLogLevel(_ level: LogLevel) {
        queue.async(flags: .barrier) { [weak self] in
            self?.minLevel = level
        }
    }

    public func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .debug, message: message, file: file, function: function, line: line)
    }

    public func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .info, message: message, file: file, function: function, line: line)
    }

    public func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .error, message: message, file: file, function: function, line: line)
    }

    private func log(level: LogLevel, message: String, file: String, function: String, line: Int) {
        let shouldLog = queue.sync { level >= minLevel }
        guard shouldLog else { return }

        let timestamp = queue.sync { dateFormatter.string(from: Date()) }
        let filename = (file as NSString).lastPathComponent
        let output: String

        switch level {
        case .error:
            output = "\(timestamp) [\(level)] \(filename):\(line) \(function) - \(message)"
        case .debug:
            output = "\(timestamp) [\(level)] \(filename):\(line) - \(message)"
        case .info:
            output = "\(timestamp) [\(level)] \(message)"
        }

        print(output)
    }
}