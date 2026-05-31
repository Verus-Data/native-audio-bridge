import ArgumentParser
import AVFoundation
import Foundation
import NativeAudioBridgeLibrary
import Speech

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the audio bridge and start listening for the hot word"
    )

    @Option(name: [.customLong("config"), .customShort("c")],
            help: "Path to YAML configuration file")
    var configPath: String?

    #if os(macOS)
    @Flag(name: .long, help: "List available audio input devices and exit")
    var listDevices: Bool = false

    @Option(name: .long, help: "Specify audio input device by name or numeric ID")
    var inputDevice: String?
    #endif

    func run() async throws {
        let log = AppLogger.shared

        #if os(macOS)
        if listDevices {
            let devices = AudioEngine.listAudioDevices()
            if devices.isEmpty {
                print("No audio input devices found.")
                print("Connect a microphone and check System Settings > Sound > Input.")
            } else {
                print("Available audio input devices:")
                print("")
                for device in devices {
                    let marker = device.isDefault ? " (default)" : ""
                    print("  [\(device.id)] \(device.name)\(marker)")
                }
                print("")
                print("Use --input-device <name-or-id> to select a specific device.")
            }
            return
        }
        #endif

        guard let config = AudioBridgeApp.checkConfigFile(configPath) else {
            throw ExitCode.failure
        }

        log.setLogLevel(config.logLevel)

        #if os(macOS)
        if let deviceIdentifier = config.inputDevice ?? inputDevice {
            let audioEngine = AudioEngine()
            do {
                try audioEngine.setInputDevice(identifier: deviceIdentifier)
                if let name = audioEngine.getSelectedDeviceName() {
                    log.info("Selected input device: \(name)")
                }
            } catch {
                log.error("Failed to set input device: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
        #endif

        AudioBridgeApp.printStartupBanner(config: config)
        
        let audioEngine = AudioEngine()
        let stateManager = StateManager()
        let speechRecognizer = SpeechRecognizer()
        let hotWordDetector = HotWordDetector(hotWord: config.hotWord)
        let commandBuffer = CommandBuffer(silenceTimeoutMs: config.silenceTimeoutMs, silenceThreshold: config.silenceThreshold)
        let commandProcessor = CommandProcessor()
        let keepAlive = DispatchGroup()

        let outputManager: OutputManager
        do {
            outputManager = try OutputManager(config: config, mode: config.outputMode)
        } catch {
            log.error("Failed to initialize output manager: \(error.localizedDescription)")
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
                    try await outputManager.output(payload)
                    log.info("Command output successful")
                } catch {
                    log.error("Command output failed: \(error.localizedDescription)")
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
                        try await outputManager.output(payload)
                        log.info("Command output successful")
                    } catch {
                        log.error("Command output failed: \(error.localizedDescription)")
                    }
                    stateManager.transition(to: .idle)
                    hotWordDetector.reset()
                }
            }
        }

        speechRecognizer.onError = { error in
            log.error("Speech recognition error: \(error.localizedDescription)")
        }

        log.info("Requesting microphone permission...")
        let micAuthorized = await requestMicrophonePermission()
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
            if let engine = audioEngine.engine {
                try speechRecognizer.startStreaming(audioEngine: engine)
                audioEngine.setOnAudioBuffer { data in
                    if let pcmBuffer = data.toPCMBuffer(format: engine.inputNode.outputFormat(forBus: 0)) {
                        speechRecognizer.appendBuffer(pcmBuffer)
                    }
                    if commandBuffer.capturing {
                        commandBuffer.append(data)
                    }
                }
                log.info("Speech recognizer streaming started.")
            } else {
                log.error("Audio engine not initialized.")
            }
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

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

private extension Data {
    func toPCMBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameLength = count / MemoryLayout<Float>.size
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameLength)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameLength)
        withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            buffer.floatChannelData?[0].update(from: base.assumingMemoryBound(to: Float.self), count: frameLength)
        }
        return buffer
    }
}
