import AVFoundation
import Foundation
import Speech

public final class SpeechRecognizer {
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private let speechRecognizer: SFSpeechRecognizer?
    private let queue = DispatchQueue(label: "com.nativeaudiobridge.speech", attributes: .concurrent)
    private var isRunning = false
    private var lastTranscript: String = ""

    public var onPartialResult: (@Sendable (String) -> Void)?
    public var onFinalResult: (@Sendable (String) -> Void)?
    public var onError: (@Sendable (Error) -> Void)?

    public init(locale: Locale = Locale(identifier: "en-US")) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    public var currentTranscript: String {
        queue.sync { lastTranscript }
    }

    public static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    public static func authorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    public func startStreaming(audioEngine: AVAudioEngine) throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechRecognizerError.notAvailable
        }

        stopStreaming()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        let task = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            let onPartial = self.onPartialResult
            let onFinal = self.onFinalResult
            let onErr = self.onError
            self.queue.async {
                if let result {
                    let transcript = result.bestTranscription.formattedString
                    self.queue.async(flags: .barrier) { [weak self] in
                        self?.lastTranscript = transcript
                    }
                    if result.isFinal {
                        onFinal?(transcript)
                    } else {
                        onPartial?(transcript)
                    }
                }
                if let error {
                    onErr?(error)
                    self.stopStreamingInternal()
                }
            }
        }

        self.recognitionTask = task
        self.isRunning = true
    }

    public func stopStreaming() {
        queue.async(flags: .barrier) { [weak self] in
            self?.stopStreamingInternal()
        }
    }

    private func stopStreamingInternal() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        isRunning = false
    }

    public var isRecognizing: Bool {
        queue.sync { isRunning }
    }
}

public enum SpeechRecognizerError: LocalizedError {
    case notAvailable
    case notAuthorized

    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Speech recognizer is not available for the requested locale"
        case .notAuthorized:
            return "Speech recognition authorization was not granted"
        }
    }
}