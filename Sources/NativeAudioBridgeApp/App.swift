import AVFoundation
import Foundation
import NativeAudioBridgeLibrary
import Speech

@main
struct AudioBridgeApp {
    static func main() async {
        let audioEngine = AudioEngine()
        let stateManager = StateManager()
        let speechRecognizer = SpeechRecognizer()
        let hotWordDetector = HotWordDetector()
        let commandBuffer = CommandBuffer(silenceTimeoutMs: 1500, silenceThreshold: 0.01)
        let commandProcessor = CommandProcessor()
        let keepAlive = DispatchGroup()

        let webhookURL = "https://gateway.openclaw.io/hooks/agent"
        let webhookToken = ProcessInfo.processInfo.environment["NATIVE_AUDIO_BRIDGE_TOKEN"] ?? ""

        var webhookDispatcher: WebhookDispatcher?
        do {
            webhookDispatcher = try WebhookDispatcher(
                webhookURL: webhookURL,
                bearerToken: webhookToken
            )
        } catch {
            print("ERROR: Invalid webhook configuration: \(error)")
            return
        }

        stateManager.setOnStateChange { oldState, newState in
            print("[\(oldState) → \(newState)]")
        }

        hotWordDetector.onHotWordDetected = {
            print("🔥 Hot word detected! Transitioning to listening...")
            stateManager.transition(to: .listening)
            commandBuffer.startCapture()
        }

        commandBuffer.onSilenceDetected = {
            print("⏸ Silence detected. Processing command...")
            stateManager.transition(to: .processing)

            let transcript = speechRecognizer.currentTranscript
            commandBuffer.stopCapture()

            guard let payload = commandProcessor.preparePayload(transcript: transcript) else {
                print("Empty command after processing. Returning to idle.")
                stateManager.transition(to: .idle)
                hotWordDetector.reset()
                return
            }

            stateManager.transition(to: .dispatching)

            Task {
                do {
                    try await webhookDispatcher?.dispatch(payload: payload)
                    print("✅ Command dispatched successfully")
                } catch {
                    print("ERROR: Webhook dispatch failed: \(error)")
                }
                stateManager.transition(to: .idle)
                hotWordDetector.reset()
            }
        }

        speechRecognizer.onPartialResult = { transcript in
            let detected = hotWordDetector.process(transcript: transcript)
            if !detected, stateManager.state == .listening {
                print("  Partial: \(transcript)")
            }
        }

        speechRecognizer.onFinalResult = { transcript in
            print("  Final transcript: \(transcript)")
            if !commandBuffer.capturing {
                stateManager.transition(to: .processing)

                guard let payload = commandProcessor.preparePayload(transcript: transcript) else {
                    print("Empty command after processing. Returning to idle.")
                    stateManager.transition(to: .idle)
                    hotWordDetector.reset()
                    return
                }

                stateManager.transition(to: .dispatching)

                Task {
                    do {
                        try await webhookDispatcher?.dispatch(payload: payload)
                        print("✅ Command dispatched successfully")
                    } catch {
                        print("ERROR: Webhook dispatch failed: \(error)")
                    }
                    stateManager.transition(to: .idle)
                    hotWordDetector.reset()
                }
            }
        }

        speechRecognizer.onError = { error in
            print("Speech recognition error: \(error.localizedDescription)")
        }

        audioEngine.setOnAudioBuffer { data in
            if commandBuffer.capturing {
                commandBuffer.append(data)
            }
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
            commandBuffer.stopCapture()
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