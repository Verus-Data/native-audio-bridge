import Foundation

public enum HotWordDetectorState {
    case idle
    case listening
}

public final class HotWordDetector {
    private let hotWord: String
    private let windowSize: Int
    private var transcriptWindow: [String] = []
    private let queue = DispatchQueue(label: "com.nativeaudiobridge.hotword", attributes: .concurrent)
    private(set) var state: HotWordDetectorState = .idle

    public var onHotWordDetected: (() -> Void)?

    public init(hotWord: String = "hey claW", windowSize: Int = 3) {
        self.hotWord = hotWord.lowercased()
        self.windowSize = windowSize
    }

    public func process(transcript: String) -> Bool {
        let normalized = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            self.transcriptWindow.append(normalized)
            if self.transcriptWindow.count > self.windowSize {
                self.transcriptWindow.removeFirst()
            }
        }

        if matchesHotWord(normalized) {
            state = .listening
            onHotWordDetected?()
            return true
        }

        if slidingWindowMatch() {
            state = .listening
            onHotWordDetected?()
            return true
        }

        return false
    }

    public func reset() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            self.transcriptWindow.removeAll()
            self.state = .idle
        }
    }

    private func matchesHotWord(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains(hotWord)
    }

    private func slidingWindowMatch() -> Bool {
        let window = queue.sync { transcriptWindow }
        guard window.count >= 2 else { return false }

        let combined = window.suffix(2).joined(separator: " ")
        return combined.lowercased().contains(hotWord)
    }
}