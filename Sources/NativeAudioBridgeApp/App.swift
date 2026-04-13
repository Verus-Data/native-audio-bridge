import ArgumentParser
import AVFoundation
import Foundation
import NativeAudioBridgeLibrary
import Speech

@main
struct AudioBridgeApp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "native-audio-bridge",
        abstract: "Native macOS voice interaction layer for OpenClaw",
        version: AppVersion.current
    )

    @Option(name: [.customLong("config"), .customShort("c")],
            help: "Path to YAML configuration file")
    var configPath: String?

    func run() async throws {
        let log = AppLogger.shared

        let configManager = ConfigurationManager()
        let config: Configuration
        do {
            config = try configManager.load(from: configPath)
        } catch {
            log.error("Failed to load configuration: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        log.setLogLevel(config.logLevel)
        log.info("Native Audio Bridge starting...")
        log.debug("Configuration loaded - hotWord: \(config.hotWord), silenceTimeout: \(config.silenceTimeoutMs)ms, webhookURL: \(config.webhookURL)")

        let audioEngine = AudioEngine()
        let stateManager = StateManager()
        let speechRecognizer = SpeechRecognizer()
        let hotWordDetector = HotWordDetector(hotWord: config.hotWord)
        let commandBuffer = CommandBuffer(silenceTimeoutMs: config.silenceTimeoutMs, silenceThreshold: config.silenceThreshold)
        let commandProcessor = CommandProcessor()
        let keepAlive = DispatchGroup()

        let webhookDispatcher: WebhookDispatcher
        do {
            webhookDispatcher = try WebhookDispatcher(
                webhookURL: config.webhookURL,
                bearerToken: config.webhookToken
            )
        } catch {
            log.error("Invalid webhook configuration: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        stateManager.setOnStateChange { oldState, newState in
            log.info("[\(oldState) → \(newState)]")
        }

        hotWordDetector.onHotWordDetected = {
            log.info("Hot word detected. Transitioning to listening...")
            stateManager.transition(to: .listening)
            commandBuffer.startCapture()
        }

        commandBuffer.onSilenceDetected = {
            log.info("Silence detected. Processing command...")
            stateManager.transition(to: .processing)

            let transcript = speechRecognizer.currentTranscript
            commandBuffer.stopCapture()

            guard let payload = commandProcessor.preparePayload(transcript: transcript) else {
                log.info("Empty command after processing. Returning to idle.")
                stateManager.transition(to: .idle)
                hotWordDetector.reset()
                return
            }

            stateManager.transition(to: .dispatching)

            Task {
                do {
                    try await webhookDispatcher.dispatch(payload: payload)
                    log.info("Command dispatched successfully")
                } catch {
                    log.error("Webhook dispatch failed: \(error.localizedDescription)")
                }
                stateManager.transition(to: .idle)
                hotWordDetector.reset()
            }
        }

        speechRecognizer.onPartialResult = { transcript in
            let detected = hotWordDetector.process(transcript: transcript)
            if !detected, stateManager.state == .listening {
                log.debug("Partial: \(transcript)")
            }
        }

        speechRecognizer.onFinalResult = { transcript in
            log.info("Final transcript: \(transcript)")
            if !commandBuffer.capturing {
                stateManager.transition(to: .processing)

                guard let payload = commandProcessor.preparePayload(transcript: transcript) else {
                    log.info("Empty command after processing. Returning to idle.")
                    stateManager.transition(to: .idle)
                    hotWordDetector.reset()
                    return
                }

                stateManager.transition(to: .dispatching)

                Task {
                    do {
                        try await webhookDispatcher.dispatch(payload: payload)
                        log.info("Command dispatched successfully")
                    } catch {
                        log.error("Webhook dispatch failed: \(error.localizedDescription)")
                    }
                    stateManager.transition(to: .idle)
                    hotWordDetector.reset()
                }
            }
        }

        speechRecognizer.onError = { error in
            log.error("Speech recognition error: \(error.localizedDescription)")
        }

        audioEngine.setOnAudioBuffer { data in
            if commandBuffer.capturing {
                commandBuffer.append(data)
            }
        }

        log.info("Requesting microphone permission...")

        let micAuthorized = await Self.requestMicrophonePermission()
        guard micAuthorized else {
            log.error("Microphone permission denied. Exiting.")
            throw ExitCode.failure
        }

        log.info("Microphone authorized. Requesting speech recognition permission...")

        let speechAuthorized = await SpeechRecognizer.requestAuthorization()
        guard speechAuthorized else {
            log.error("Speech recognition permission denied. Exiting.")
            throw ExitCode.failure
        }

        log.info("Speech recognition authorized. Starting audio engine...")

        do {
            try audioEngine.start()
            log.info("Audio engine running. Sample rate: \(audioEngine.sampleRateValue) Hz")
            log.info("Listening for hot word \"\(config.hotWord)\"... Press Ctrl+C to stop.")
            stateManager.transition(to: .idle)
        } catch {
            log.error("Failed to start audio engine: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        do {
            let nativeEngine = AVAudioEngine()
            try nativeEngine.start()
            try speechRecognizer.startStreaming(audioEngine: nativeEngine)
            log.info("Speech recognizer streaming started.")
        } catch {
            log.error("Failed to start speech recognizer: \(error.localizedDescription)")
            log.info("Running in audio-only mode (hot word detection via transcripts unavailable).")
        }

        signal(SIGINT, SIG_IGN)
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signalSource.setEventHandler {
            log.info("Shutting down...")
            speechRecognizer.stopStreaming()
            audioEngine.stop()
            commandBuffer.stopCapture()
            keepAlive.leave()
        }
        signalSource.resume()

        keepAlive.enter()
        _ = keepAlive.wait(timeout: .distantFuture)

        log.info("Audio bridge stopped.")
    }

    private static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}