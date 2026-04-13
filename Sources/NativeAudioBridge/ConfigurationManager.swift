import Foundation

public struct Configuration {
    public let hotWord: String
    public let silenceTimeoutMs: Int
    public let silenceThreshold: Float
    public let webhookURL: String
    public let webhookToken: String
    public let logLevel: LogLevel
}

public enum ConfigurationError: LocalizedError {
    case missingRequiredField(String)
    case invalidValue(field: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .missingRequiredField(let field):
            return "Missing required configuration field: \(field)"
        case .invalidValue(let field, let reason):
            return "Invalid value for \(field): \(reason)"
        }
    }
}

public final class ConfigurationManager {
    private static let envPrefix = "NATIVE_AUDIO_BRIDGE_"

    private static let envHotWord = "\(envPrefix)HOT_WORD"
    private static let envSilenceTimeout = "\(envPrefix)SILENCE_TIMEOUT"
    private static let envSilenceThreshold = "\(envPrefix)SILENCE_THRESHOLD"
    private static let envWebhookURL = "\(envPrefix)WEBHOOK_URL"
    private static let envWebhookToken = "\(envPrefix)TOKEN"
    private static let envLogLevel = "\(envPrefix)LOG_LEVEL"

    public static let defaultHotWord = "hey claW"
    public static let defaultSilenceTimeoutMs = 1500
    public static let defaultSilenceThreshold: Float = 0.01
    public static let defaultWebhookURL = "https://gateway.openclaw.io/hooks/agent"
    public static let defaultLogLevel = LogLevel.info

    private let env: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.env = environment
    }

    public func load(from path: String? = nil) throws -> Configuration {
        var config = Configuration(
            hotWord: Self.defaultHotWord,
            silenceTimeoutMs: Self.defaultSilenceTimeoutMs,
            silenceThreshold: Self.defaultSilenceThreshold,
            webhookURL: Self.defaultWebhookURL,
            webhookToken: "",
            logLevel: Self.defaultLogLevel
        )

        if let path {
            let fileConfig = try loadConfigFile(path: path)
            config = merge(base: config, override: fileConfig)
        }

        let envConfig = loadFromEnvironment()
        config = merge(base: config, override: envConfig)

        try validate(config: config)
        return config
    }

    private func loadConfigFile(path: String) throws -> PartialConfiguration {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let parsed = try YAMLParser.parse(yaml: data)
        return PartialConfiguration(
            hotWord: parsed["hot_word"],
            silenceTimeoutMs: parsed["silence_timeout"].flatMap { Int($0) },
            silenceThreshold: parsed["silence_threshold"].flatMap { Float($0) },
            webhookURL: parsed["webhook_url"],
            webhookToken: parsed["webhook_token"],
            logLevel: parsed["log_level"].flatMap { LogLevel(from: $0) }
        )
    }

    private func loadFromEnvironment() -> PartialConfiguration {
        PartialConfiguration(
            hotWord: env[Self.envHotWord],
            silenceTimeoutMs: env[Self.envSilenceTimeout].flatMap { Int($0) },
            silenceThreshold: env[Self.envSilenceThreshold].flatMap { Float($0) },
            webhookURL: env[Self.envWebhookURL],
            webhookToken: env[Self.envWebhookToken],
            logLevel: env[Self.envLogLevel].flatMap { LogLevel(from: $0) }
        )
    }

    private func merge(base: Configuration, override: PartialConfiguration) -> Configuration {
        Configuration(
            hotWord: override.hotWord ?? base.hotWord,
            silenceTimeoutMs: override.silenceTimeoutMs ?? base.silenceTimeoutMs,
            silenceThreshold: override.silenceThreshold ?? base.silenceThreshold,
            webhookURL: override.webhookURL ?? base.webhookURL,
            webhookToken: override.webhookToken ?? base.webhookToken,
            logLevel: override.logLevel ?? base.logLevel
        )
    }

    private func validate(config: Configuration) throws {
        guard !config.webhookURL.isEmpty else {
            throw ConfigurationError.missingRequiredField("webhookURL")
        }
        guard let webhookURL = URL(string: config.webhookURL),
              webhookURL.scheme != nil else {
            throw ConfigurationError.invalidValue(field: "webhookURL", reason: "must be a valid URL with scheme")
        }
        guard !config.webhookToken.isEmpty else {
            throw ConfigurationError.missingRequiredField("webhookToken (set NATIVE_AUDIO_BRIDGE_TOKEN or configure webhook_token)")
        }
        guard config.silenceTimeoutMs > 0 else {
            throw ConfigurationError.invalidValue(field: "silenceTimeoutMs", reason: "must be greater than 0")
        }
        guard config.silenceThreshold > 0 else {
            throw ConfigurationError.invalidValue(field: "silenceThreshold", reason: "must be greater than 0")
        }
        guard !config.hotWord.isEmpty else {
            throw ConfigurationError.invalidValue(field: "hotWord", reason: "must not be empty")
        }
    }
}

extension LogLevel {
    public init?(from string: String) {
        switch string.lowercased() {
        case "debug": self = .debug
        case "info": self = .info
        case "error": self = .error
        default: return nil
        }
    }
}

private struct PartialConfiguration {
    let hotWord: String?
    let silenceTimeoutMs: Int?
    let silenceThreshold: Float?
    let webhookURL: String?
    let webhookToken: String?
    let logLevel: LogLevel?
}

private enum YAMLParser {
    static func parse(yaml: Data) throws -> [String: String] {
        guard let content = String(data: yaml, encoding: .utf8) else {
            return [:]
        }
        var result: [String: String] = [:]
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            } else if value.hasPrefix("'") && value.hasSuffix("'") {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }
}