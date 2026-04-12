import AVFoundation
import Foundation
import Speech

@main
struct AudioBridgeApp {
    static func main() async {
        let audioEngine = AudioEngine()
        let stateManager = StateManager()
        let speechRecognizer = SpeechRecognizer()
        let hotWordDetector = HotWordDetector()
        let keepAlive = DispatchGroup()

        stateManager.setOnStateChange { oldState, newState in
            print("[\(oldState) → \(newState)]")
        }

        hotWordDetector.onHotWordDetected = {
            print("🔥 Hot word detected! Transitioning to listening...")
            stateManager.transition(to: .listening)
        }

        speechRecognizer.onPartialResult = { transcript in
            let detected = hotWordDetector.process(transcript: transcript)
            if !detected, stateManager.state == .listening {
                print("  Partial: \(transcript)")
            }
        }

        speechRecognizer.onFinalResult = { transcript in
            print("  Final transcript: \(transcript)")
            stateManager.transition(to: .processing)
            print("  Command: \(transcript)")
        }

        speechRecognizer.onError = { error in
            print("Speech recognition error: \(error.localizedDescription)")
        }

        print("Native Audio Bridge starting...")
        print("Requesting microphone permission...")

        let micAuthorized = await requestMicrophonePermission()
        guard micAuthorized else {
            print("ERROR: Microphone permission denied. Exiting.")
            return
        }

        print("Microphone authorized. Requesting speech recognition permission...")

        let speechAuthorized = await SpeechRecognizer.requestAuthorization()
        guard speechAuthorized else {
            print("ERROR: Speech recognition permission denied. Exiting.")
            return
        }

        print("Speech recognition authorized. Starting audio engine...")

        do {
            try audioEngine.start()
            print("Audio engine running. Sample rate: \(audioEngine.sampleRateValue) Hz")
            print("Listening for hot word... Press Ctrl+C to stop.")
            stateManager.transition(to: .idle)
        } catch {
            print("ERROR: Failed to start audio engine: \(error)")
            return
        }

        do {
            let nativeEngine = AVAudioEngine()
            try nativeEngine.start()
            try speechRecognizer.startStreaming(audioEngine: nativeEngine)
            print("Speech recognizer streaming started.")
        } catch {
            print("ERROR: Failed to start speech recognizer: \(error)")
            print("Running in audio-only mode (hot word detection via transcripts unavailable).")
        }

        signal(SIGINT, SIG_IGN)
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signalSource.setEventHandler {
            print("\nShutting down...")
            speechRecognizer.stopStreaming()
            audioEngine.stop()
            keepAlive.leave()
        }
        signalSource.resume()

        keepAlive.enter()
        _ = keepAlive.wait(timeout: .distantFuture)

        print("Audio bridge stopped.")
    }

    private static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}