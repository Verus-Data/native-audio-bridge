import Foundation

public struct DispatchPayload: Encodable {
    public let message: String
    public let name: String
    public let agentId: String
    public let wakeMode: String

    public init(message: String, name: String, agentId: String, wakeMode: String) {
        self.message = message
        self.name = name
        self.agentId = agentId
        self.wakeMode = wakeMode
    }
}

public final class CommandProcessor {
    private let name: String
    private let agentId: String
    private let wakeMode: String

    public init(name: String = "AudioBridge", agentId: String = "audio-bridge", wakeMode: String = "now") {
        self.name = name
        self.agentId = agentId
        self.wakeMode = wakeMode
    }

    public func sanitize(_ text: String) -> String {
        var result = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let replacements: [(String, String)] = [
            (" +", " "),
            ("\\s+", " "),
        ]
        for (pattern, replacement) in replacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: range,
                    withTemplate: replacement
                )
            }
        }

        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    public func preparePayload(transcript: String) -> DispatchPayload? {
        let sanitized = sanitize(transcript)
        guard !sanitized.isEmpty else {
            Logger.shared.info("Empty transcript after sanitization, skipping dispatch")
            return nil
        }
        Logger.shared.debug("Prepared payload: \"\(sanitized)\"")
        return DispatchPayload(
            message: sanitized,
            name: name,
            agentId: agentId,
            wakeMode: wakeMode
        )
    }
}