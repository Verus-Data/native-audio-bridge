import Foundation

public struct Configuration {
    public let hotWord: String
    public let silenceTimeoutMs: Int
    public let silenceThreshold: Float
    public let webhookURL: String
    public let webhookToken: String
    public let logLevel: LogLevel
    public let outputMode: OutputMode
}

public enum OutputMode: String {
    case webhook
    case jsonlFile
    case both
        
    public var rawValue: String { return self.rawValue }
}

public enum LogLevel: String {
    public case debug
    public case info
    public case error
    
    public init?(from string: String) {
        switch string.lowercased() {
        case "debug": self = .debug
        case "info": self = .info
        case "error": self = .error
        default: return nil
        }
    }
    
    public var description: String { return switch self { 
        case .debug: "debug"
        case .info: "info" 
        case .error: "error"
    } }
}

// Existing enum definitions...
/* The rest of your existing code */