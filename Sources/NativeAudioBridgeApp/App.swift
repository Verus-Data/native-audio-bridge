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
        discussion: """
            Native Audio Bridge listens for a hot word and streams audio to a webhook \
            when speech is detected. Configure via YAML file or environment variables.

            Default config path: ~/.config/native-audio-bridge/config.yaml

            Examples:
              native-audio-bridge                          Run with default config
              native-audio-bridge --generate-config        Generate default config file
              native-audio-bridge --generate-config /path/to/config.yaml  Generate to custom path
              native-audio-bridge --dry-run                Validate config without starting
              native-audio-bridge --config /path/to/config.yaml  Use custom config
            """,
        version: AppVersion.current
    )

    @Option(name: [.customLong("config"), .customShort("c")],
            help: "Path to YAML configuration file")
    var configPath: String?

    @Flag(name: .long, help: "Validate config and print status without starting audio capture")
    var dryRun: Bool = false

    @Option(name: .long, help: "Generate a default config file at the specified path")
    var generateConfig: String?

    func run() async throws {
        let log = AppLogger.shared

        if let configOutputPath = generateConfig {
            try generateConfigFile(at: configOutputPath)
            return
        }

        let resolvedConfigPath = resolveConfigPath()
        let configManager = ConfigurationManager()
        let config: Configuration

        do {
            config = try configManager.load(from: configPath)
        } catch {
            printNoConfigError(defaultPath: resolvedConfigPath)
            log.error("Failed to load configuration: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        log.setLogLevel(config.logLevel)

        if dryRun {
            await performDryRun(config: config, configPath: resolvedConfigPath)
            return
        }

        log.info("Native Audio Bridge starting...")
        log.debug("Configuration loaded - hotWord: \(config.hotWord), silenceTimeout: \(config.silenceTimeoutMs)ms, webhookURL: \(config.webhookURL)")

        printStartupBanner(config: config)

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

        log.info("Speech recognition authorized. Starting audio engine...")

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch micStatus {
        case .authorized:
            break
        case .notDetermined:
            let granted = await Self.requestMicrophonePermission()
            if !granted {
                log.error("Microphone permission denied. Please enable in System Settings > Privacy & Security > Microphone")
                throw ExitCode.failure
            }
        case .denied, .restricted:
            log.error("Microphone permission denied. Please enable in System Settings > Privacy & Security > Microphone")
            throw ExitCode.failure
        @unknown default:
            log.error("Unknown microphone permission status. Please check System Settings > Privacy & Security > Microphone")
            throw ExitCode.failure
        }

        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        switch speechStatus {
        case .authorized:
            break
        case .notDetermined:
            let granted = await SpeechRecognizer.requestAuthorization()
            if !granted {
                log.error("Speech recognition permission denied. Please enable in System Settings > Privacy & Security > Speech Recognition")
                throw ExitCode.failure
            }
        case .denied, .restricted:
            log.error("Speech recognition permission denied. Please enable in System Settings > Privacy & Security > Speech Recognition")
            throw ExitCode.failure
        @unknown default:
            log.error("Unknown speech recognition permission status. Please check System Settings > Privacy & Security > Speech Recognition")
            throw ExitCode.failure
        }

        do {
            try audioEngine.start()
            log.info("Audio engine running. Sample rate: \(audioEngine.sampleRateValue) Hz")
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

    private func resolveConfigPath() -> String {
        if let path = configPath {
            return path
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/native-audio-bridge/config.yaml").path
    }

    private func configFileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private func generateConfigFile(at path: String) throws {
        let defaultContent = """
            # Native Audio Bridge Configuration
            # Generated on \(ISO8601DateFormatter().string(from: Date()))

            # Hot word to listen for
            hot_word: "hey claW"

            # Silence timeout in milliseconds (time to wait after speech ends)
            silence_timeout: 1500

            # Audio level threshold for silence detection (0.0 - 1.0)
            silence_threshold: 0.01

            # Webhook URL for dispatching commands
            webhook_url: "https://gateway.openclaw.io/hooks/agent"

            # Bearer token for webhook authentication
            webhook_token: "your-token-here"

            # Log level: debug, info, or error
            log_level: "info"
            """

        let configURL: URL
        if path.isEmpty || path == "~/.config/native-audio-bridge/config.yaml" {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let configDir = home.appendingPathComponent(".config/native-audio-bridge")
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            configURL = configDir.appendingPathComponent("config.yaml")
        } else {
            configURL = URL(fileURLWithPath: path)
            let dir = configURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }

        try defaultContent.write(to: configURL, atomically: true, encoding: .utf8)

        print("")
        print("✅ Config file created at:")
        print("   \(configURL.path)")
        print("")
        print("Next steps:")
        print("  1. Edit the config and add your webhook_token")
        print("  2. Run: native-audio-bridge")
        print("  3. Or specify a custom path: native-audio-bridge --config \(configURL.path)")
        print("")
    }

    private func printNoConfigError(defaultPath: String) {
        print("")
        print("❌ No config file found")
        print("")
        print("Checked path: \(defaultPath)")
        print("")
        print("To get started:")
        print("  • Run with --generate-config to create a default config")
        print("  • Or use --config /path/to/config.yaml to specify a custom location")
        print("")
        print("Minimal config example:")
        print("""
            hot_word: "hey claW"
            webhook_url: "https://example.com/hooks"
            webhook_token: "your-token-here"
            """)
        print("")
    }

    private func performDryRun(config: Configuration, configPath: String) async {
        print("")
        print("╔══════════════════════════════════════════════════════════════╗")
        print("║              Native Audio Bridge - Dry Run                   ║")
        print("╚══════════════════════════════════════════════════════════════╝")
        print("")

        print("📁 Config file: \(configPath)")
        print("   \(configFileExists(at: configPath) ? "✅ Found" : "⚠️  Not found")")
        print("")

        print("🔧 Configuration:")
        print("   hot_word:       '\(config.hotWord)'")
        print("   webhook_url:    \(config.webhookURL)")
        print("   silence_timeout: \(config.silenceTimeoutMs)ms")
        print("   silence_threshold: \(config.silenceThreshold)")
        print("   log_level:      \(config.logLevel.rawValue)")
        print("")

        print("🔒 Permissions:")

        let micStatus = await Self.checkMicrophonePermission()
        print("   Microphone: \(micStatus.icon) \(micStatus.status)")

        let speechStatus = Self.checkSpeechRecognitionPermission()
        print("   Speech Recognition: \(speechStatus.icon) \(speechStatus.status)")
        print("")

        print("🌐 Webhook:")
        print("   URL: \(config.webhookURL)")
        print("   Token: \(config.webhookToken.isEmpty ? "❌ Not set" : "✅ Configured")")
        print("")

        print("📤 Output mode: webhook")
        print("")

        let allPassed = micStatus.granted && speechStatus.granted && !config.webhookToken.isEmpty
        print("───────────────────────────────────────────────────────────────")
        print("Status: \(allPassed ? "✅ Ready to start" : "⚠️  Some issues need attention")")
        print("")
    }

    private func printStartupBanner(config: Configuration) {
        print("")
        print("╔══════════════════════════════════════════════════════════════╗")
        print("║              Native Audio Bridge v\(AppVersion.current)                    ║")
        print("╚══════════════════════════════════════════════════════════════╝")
        print("")
        print("   Hot word: '\(config.hotWord)'")
        print("")
        print("   Listening... (Press Ctrl+C to stop)")
        print("")
        print("   Status: [🎤 Microphone] [🔊 Speech recognition] [🌐 Webhook]")
        print("")
    }

    private static func checkMicrophonePermission() async -> PermissionStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return PermissionStatus(granted: true, status: "Authorized", icon: "✅")
        case .denied:
            return PermissionStatus(granted: false, status: "Denied", icon: "❌")
        case .restricted:
            return PermissionStatus(granted: false, status: "Restricted", icon: "❌")
        case .notDetermined:
            return PermissionStatus(granted: false, status: "Not determined", icon: "⏳")
        @unknown default:
            return PermissionStatus(granted: false, status: "Unknown", icon: "❓")
        }
    }

    private static func checkSpeechRecognitionPermission() -> PermissionStatus {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return PermissionStatus(granted: true, status: "Authorized", icon: "✅")
        case .denied:
            return PermissionStatus(granted: false, status: "Denied", icon: "❌")
        case .restricted:
            return PermissionStatus(granted: false, status: "Restricted", icon: "❌")
        case .notDetermined:
            return PermissionStatus(granted: false, status: "Not determined", icon: "⏳")
        @unknown default:
            return PermissionStatus(granted: false, status: "Unknown", icon: "❓")
        }
    }
}

private struct PermissionStatus {
    let granted: Bool
    let status: String
    let icon: String
}
