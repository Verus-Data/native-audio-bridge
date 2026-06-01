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
        guard let speechRecognizer else {
            throw SpeechRecognizerError.notAvailable
        }
        
        print("[SpeechRecognizer] Availability check: \(speechRecognizer.isAvailable)")
        guard speechRecognizer.isAvailable else {
            AppLogger.shared.error("Speech recognizer is not available. Check internet or speech assets.")
            print("[SpeechRecognizer] ERROR: Not available!")
            throw SpeechRecognizerError.notAvailable
        }

        stopStreaming()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // NOTE: requiresOnDeviceRecognition disabled on macOS — local speech assets
        // may not be present, causing silent failure (no transcripts, no errors).
        #if !os(macOS)
        request.requiresOnDeviceRecognition = true
        #endif
        self.recognitionRequest = request

        AppLogger.shared.info("Starting recognition task (on-device)...")
        print("[SpeechRecognizer] Starting recognition task (on-device)...")

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
                    AppLogger.shared.info("Recognition result: isFinal=\(result.isFinal), transcript=\(transcript)")
                    print("[SpeechRecognizer] Result: isFinal=\(result.isFinal), transcript='\(transcript)'")
                    if result.isFinal {
                        onFinal?(transcript)
                    } else {
                        onPartial?(transcript)
                    }
                }
                if let error {
                    AppLogger.shared.error("Recognition task error: \(error.localizedDescription)")
                    print("[SpeechRecognizer] ERROR: \(error)")
                    onErr?(error)
                    self.stopStreamingInternal()
                }
            }
        }

        self.recognitionTask = task
        self.isRunning = true
    }

    public func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
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