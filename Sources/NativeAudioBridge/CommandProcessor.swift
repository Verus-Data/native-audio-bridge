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

        // Collapse multiple whitespace into single space
        result = result.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    public func preparePayload(transcript: String) -> DispatchPayload? {
        let sanitized = sanitize(transcript)
        guard !sanitized.isEmpty else {
            AppLogger.shared.info("Empty transcript after sanitization, skipping dispatch")
            return nil
        }
        AppLogger.shared.debug("Prepared payload: \"\(sanitized)\"")
        return DispatchPayload(
            message: sanitized,
            name: name,
            agentId: agentId,
            wakeMode: wakeMode
        )
    }
}