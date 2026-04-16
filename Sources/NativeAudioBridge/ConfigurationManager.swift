import Foundation

public enum OutputMode: String {
    case webhook
    case file
}

public struct WebhookConfig {
    public let method: String
    public let headers: [String: String]
    public let retryEnabled: Bool
    public let retryCount: Int
    public let retryDelayMs: Int

    public init(method: String = "POST", headers: [String: String] = [:], retryEnabled: Bool = true, retryCount: Int = 3, retryDelayMs: Int = 1000) {
        self.method = method
        self.headers = headers
        self.retryEnabled = retryEnabled
        self.retryCount = retryCount
        self.retryDelayMs = retryDelayMs
    }
}

public struct FileOutputConfig {
    public let path: String
    public let rotateDaily: Bool

    public init(path: String = "-", rotateDaily: Bool = false) {
        self.path = path
        self.rotateDaily = rotateDaily
    }
}

public struct Configuration {
    public let hotWord: String
    public let caseSensitive: Bool
    public let silenceTimeoutMs: Int
    public let silenceThreshold: Float
    public let outputMode: OutputMode
    public let webhookURL: String
    public let webhookToken: String
    public let webhookConfig: WebhookConfig
    public let fileOutput: FileOutputConfig
    public let logLevel: LogLevel
    public let inputDevice: String?
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
    private static let envCaseSensitive = "\(envPrefix)CASE_SENSITIVE"
    private static let envSilenceTimeout = "\(envPrefix)SILENCE_TIMEOUT"
    private static let envSilenceThreshold = "\(envPrefix)SILENCE_THRESHOLD"
    private static let envOutputMode = "\(envPrefix)OUTPUT_MODE"
    private static let envWebhookURL = "\(envPrefix)WEBHOOK_URL"
    private static let envWebhookToken = "\(envPrefix)TOKEN"
    private static let envFilePath = "\(envPrefix)FILE_PATH"
    private static let envLogLevel = "\(envPrefix)LOG_LEVEL"
    private static let envInputDevice = "\(envPrefix)INPUT_DEVICE"

    public static let defaultHotWord = "hey claW"
    public static let defaultCaseSensitive = false
    public static let defaultSilenceTimeoutMs = 1500
    public static let defaultSilenceThreshold: Float = 0.01
    public static let defaultOutputMode = OutputMode.webhook
    public static let defaultWebhookURL = "https://gateway.openclaw.io/hooks/agent"
    public static let defaultLogLevel = LogLevel.info

    private let env: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.env = environment
    }

    public func load(from path: String? = nil) throws -> Configuration {
        var config = Configuration(
            hotWord: Self.defaultHotWord,
            caseSensitive: Self.defaultCaseSensitive,
            silenceTimeoutMs: Self.defaultSilenceTimeoutMs,
            silenceThreshold: Self.defaultSilenceThreshold,
            outputMode: Self.defaultOutputMode,
            webhookURL: Self.defaultWebhookURL,
            webhookToken: "",
            webhookConfig: WebhookConfig(),
            fileOutput: FileOutputConfig(),
            logLevel: Self.defaultLogLevel,
            inputDevice: nil
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

        var webhookConfig = WebhookConfig()
        if let method = parsed["webhook.method"] {
            webhookConfig = WebhookConfig(method: method)
        }
        if parsed["webhook.retry"] == "false" || parsed["webhook.retry"] == "no" {
            webhookConfig = WebhookConfig(retryEnabled: false)
        }

        var fileOutput = FileOutputConfig()
        if let filePath = parsed["file.path"] {
            let rotateDaily = parsed["file.rotate_daily"] == "true" || parsed["file.rotate_daily"] == "yes"
            fileOutput = FileOutputConfig(path: filePath, rotateDaily: rotateDaily)
        }

        let outputMode: OutputMode? = parsed["output_mode"].flatMap { OutputMode(rawValue: $0) }

        return PartialConfiguration(
            hotWord: parsed["hot_word"],
            caseSensitive: parsed["case_sensitive"].flatMap { $0 == "true" || $0 == "yes" },
            silenceTimeoutMs: parsed["silence_timeout"].flatMap { Int($0) },
            silenceThreshold: parsed["silence_threshold"].flatMap { Float($0) },
            outputMode: outputMode,
            webhookURL: parsed["webhook_url"],
            webhookToken: parsed["webhook_token"],
            webhookConfig: webhookConfig,
            fileOutput: fileOutput,
            logLevel: parsed["log_level"].flatMap { LogLevel(from: $0) },
            inputDevice: parsed["input_device"]
        )
    }

    private func loadFromEnvironment() -> PartialConfiguration {
        let outputMode: OutputMode? = env[Self.envOutputMode].flatMap { OutputMode(rawValue: $0) }
        let filePath = env[Self.envFilePath]
        let fileOutput = filePath.map { FileOutputConfig(path: $0) }

        return PartialConfiguration(
            hotWord: env[Self.envHotWord],
            caseSensitive: env[Self.envCaseSensitive].flatMap { $0 == "true" || $0 == "yes" },
            silenceTimeoutMs: env[Self.envSilenceTimeout].flatMap { Int($0) },
            silenceThreshold: env[Self.envSilenceThreshold].flatMap { Float($0) },
            outputMode: outputMode,
            webhookURL: env[Self.envWebhookURL],
            webhookToken: env[Self.envWebhookToken],
            webhookConfig: nil,
            fileOutput: fileOutput,
            logLevel: env[Self.envLogLevel].flatMap { LogLevel(from: $0) },
            inputDevice: env[Self.envInputDevice]
        )
    }

    private func merge(base: Configuration, override: PartialConfiguration) -> Configuration {
        Configuration(
            hotWord: override.hotWord ?? base.hotWord,
            caseSensitive: override.caseSensitive ?? base.caseSensitive,
            silenceTimeoutMs: override.silenceTimeoutMs ?? base.silenceTimeoutMs,
            silenceThreshold: override.silenceThreshold ?? base.silenceThreshold,
            outputMode: override.outputMode ?? base.outputMode,
            webhookURL: override.webhookURL ?? base.webhookURL,
            webhookToken: override.webhookToken ?? base.webhookToken,
            webhookConfig: override.webhookConfig ?? base.webhookConfig,
            fileOutput: override.fileOutput ?? base.fileOutput,
            logLevel: override.logLevel ?? base.logLevel,
            inputDevice: override.inputDevice ?? base.inputDevice
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
    let caseSensitive: Bool?
    let silenceTimeoutMs: Int?
    let silenceThreshold: Float?
    let outputMode: OutputMode?
    let webhookURL: String?
    let webhookToken: String?
    let webhookConfig: WebhookConfig?
    let fileOutput: FileOutputConfig?
    let logLevel: LogLevel?
    let inputDevice: String?
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