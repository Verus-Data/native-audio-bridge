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
            when speech is detected. A microphone is required.

            Default config path: ~/.config/native-audio-bridge/config.yaml

            Examples:
              native-audio-bridge                          Run with default config
              native-audio-bridge --generate-config        Generate default config file
              native-audio-bridge --generate-config /path/to/config.yaml  Generate to custom path
              native-audio-bridge --dry-run                Validate config without starting
              native-audio-bridge --check-audio            Verify audio input is available
              native-audio-bridge --check-permissions     Check microphone and speech permissions
              native-audio-bridge --config /path/to/config.yaml  Use custom config
            """,
        version: AppVersion.current
    )

    @Option(name: [.customLong("config"), .customShort("c")],
            help: "Path to YAML configuration file")
    var configPath: String?

    @Flag(name: .long, help: "Validate config and print status without starting audio capture")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Check if audio input is available and exit")
    var checkAudio: Bool = false

    @Flag(name: [.customLong("check-permissions"), .customShort("p")],
            help: "Check microphone and speech recognition permissions and diagnostics")
    var checkPermissions: Bool = false

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

        #if os(macOS)
        if checkAudio {
            print("Checking audio input availability...")
            do {
                try AudioEngine.checkAudioAvailable()
                print("Audio input is available. Ready to capture audio.")
                throw ExitCode.success
            } catch let error as AudioError {
                print("Audio input is NOT available.")
                print("Error: \(error.localizedDescription)")
                print("")
                print("Troubleshooting steps:")
                print("  1. Connect a microphone or use built-in input")
                print("  2. Check System Settings > Sound > Input")
                print("  3. Ensure no other app is using the microphone")
                print("  4. Try: sudo killall coreaudiod (restarts audio subsystem)")
                throw ExitCode.failure
            } catch {
                print("Audio check failed: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
        #endif

        if checkPermissions {
            await performPermissionsCheck()
            return
        }

        log.info("Native Audio Bridge starting...")
        log.debug("Configuration loaded - hotWord: \(config.hotWord), silenceTimeout: \(config.silenceTimeoutMs)ms, webhookURL: \(config.webhookURL)")

        printStartupBanner(config: config)
        
        print("🔍 Checking permissions and audio devices...")

        print("[DEBUG] Creating AudioEngine...")
        let audioEngine = AudioEngine()
        print("[DEBUG] AudioEngine initialized")
        
        print("[DEBUG] Creating StateManager...")
        let stateManager = StateManager()
        print("[DEBUG] Creating SpeechRecognizer...")
        let speechRecognizer = SpeechRecognizer()
        print("[DEBUG] Creating HotWordDetector...")
        let hotWordDetector = HotWordDetector(hotWord: config.hotWord)
        print("[DEBUG] Creating CommandBuffer...")
        let commandBuffer = CommandBuffer(silenceTimeoutMs: config.silenceTimeoutMs, silenceThreshold: config.silenceThreshold)
        print("[DEBUG] Creating CommandProcessor...")
        let commandProcessor = CommandProcessor()
        print("[DEBUG] Creating keepalive DispatchGroup...")
        let keepAlive = DispatchGroup()

        let webhookDispatcher: WebhookDispatcher
        do {
            print("[DEBUG] Creating WebhookDispatcher...")
            webhookDispatcher = try WebhookDispatcher(
                webhookURL: config.webhookURL,
                bearerToken: config.webhookToken
            )
            print("[DEBUG] WebhookDispatcher created")
        } catch {
            log.error("Invalid webhook configuration: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        print("[DEBUG] Setting up state change handler...")
        stateManager.setOnStateChange { oldState, newState in
            log.info("[\(oldState) → \(newState)]")
        }

        hotWordDetector.onHotWordDetected = {
            log.info("Hot word detected. Transitioning to listening...")
            stateManager.transition(to: .listening)
            commandBuffer.startCapture()
        }

        print("[DEBUG] Setting up hot word detector callback...")
        hotWordDetector.onHotWordDetected = {
            log.info("Hot word detected. Transitioning to listening...")
            stateManager.transition(to: .listening)
            commandBuffer.startCapture()
        }

        print("[DEBUG] Setting up command buffer callback...")
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

        print("[DEBUG] Setting up speech recognizer callback...")
        audioEngine.setOnAudioBuffer { data in
            if commandBuffer.capturing {
                commandBuffer.append(data)
            }
        }

        print("[DEBUG] Checking microphone permission status...")
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        print("[DEBUG] Microphone status: \(micStatus)")
        switch micStatus {
        case .authorized:
            break
        case .notDetermined:
            print("[DEBUG] Requesting microphone permission if needed...")
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

        print("[DEBUG] Microphone permission granted/available")
        let audioDevices = AVCaptureDevice.devices(for: .audio)
        log.info("Found \(audioDevices.count) audio input device(s)")
        for device in audioDevices {
            log.debug("  - \(device.localizedName)")
        }

        guard !audioDevices.isEmpty else {
            log.error("No audio input devices found. Please connect a microphone.")
            log.error("Possible causes:")
            log.error("  - No microphone connected")
            log.error("  - External microphone disconnected")
            log.error("  - macOS audio subsystem issue (try: sudo killall coreaudiod)")
            throw ExitCode.failure
        }

        print("[DEBUG] Checking speech recognition permission status...")
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        switch speechStatus {
        case .authorized:
            break
        case .notDetermined:
            print("[DEBUG] Requesting speech recognition permission if needed...")
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

        print("[DEBUG] Speech recognition permission granted/available")
        print("[DEBUG] Starting audio engine...")
        do {
            try audioEngine.start()
            log.info("Audio engine running. Sample rate: \(audioEngine.sampleRateValue) Hz")
            stateManager.transition(to: .idle)
        } catch let error as AudioError {
            log.error("Failed to start audio engine: \(error.localizedDescription)")
            log.error("Possible causes:")
            log.error("  - No microphone connected")
            log.error("  - Microphone in use by another app")
            log.error("  - macOS audio subsystem issue (try: sudo killall coreaudiod)")
            throw ExitCode.failure
        } catch {
            log.error("Failed to start audio engine: \(error.localizedDescription)")
            log.error("Possible causes:")
            log.error("  - No microphone connected")
            log.error("  - Microphone in use by another app")
            log.error("  - macOS audio subsystem issue (try: sudo killall coreaudiod)")
            throw ExitCode.failure
        }

        print("[DEBUG] Engine started successfully")
        print("[DEBUG] Starting speech recognition...")
        do {
            #if os(macOS)
            try AudioEngine.checkAudioAvailable()
            #endif
            guard let sharedEngine = audioEngine.engine else {
                throw AudioError.microphoneNotAvailable
            }
            try speechRecognizer.startStreaming(audioEngine: sharedEngine)
            print("[DEBUG] Speech recognition started")
        } catch let error as AudioError {
            log.error("Audio subsystem unavailable for speech recognition: \(error.localizedDescription)")
            log.info("Running in audio-only mode (hot word detection via transcripts unavailable).")
        } catch {
            log.error("Failed to start speech recognizer: \(error.localizedDescription)")
            log.info("Running in audio-only mode (hot word detection via transcripts unavailable).")
        }

        print("[DEBUG] Starting hot word detection...")
        print("[DEBUG] Entering main run loop...")
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
            # ═══════════════════════════════════════════════════════════════════════════
            # Native Audio Bridge Configuration
            # Generated: \(ISO8601DateFormatter().string(from: Date()))
            # ═══════════════════════════════════════════════════════════════════════════
            #
            # QUICK START
            # ──────────
            # 1. Set your webhook_url and webhook_token for production use
            # 2. Customize the hot_word to your preferred trigger phrase
            # 3. Run: native-audio-bridge --dry-run to validate
            # 4. Run: native-audio-bridge to start listening
            #
            # OUTPUT MODES
            # ────────────
            # This app supports two output modes:
            #
            #   webhook  → POST commands to a URL (production use)
            #   file     → Write JSONL to a file (testing/debugging)
            #
            # Uncomment the mode you want to use. Default is webhook.

            # ─────────────────────────────────────────────────────────────────────────
            # HOT WORD DETECTION
            # ─────────────────────────────────────────────────────────────────────────

            # The trigger phrase the app listens for.
            # When detected, the app begins capturing audio until silence is detected.
            # Example: "hey claW", "hey assistant", "computer"
            hot_word: "hey claW"

            # Whether hot word matching is case-sensitive.
            # Set to false to match "HEY CLAW", "Hey Claw", etc.
            # Options: true, false
            case_sensitive: false

            # ─────────────────────────────────────────────────────────────────────────
            # SILENCE DETECTION
            # ─────────────────────────────────────────────────────────────────────────

            # Milliseconds to wait after speech ends before processing.
            # Higher values give more time for natural pauses in speech.
            # Lower values respond faster but may truncate commands.
            # Typical range: 500-3000ms
            silence_timeout: 1500

            # Audio level threshold for silence detection (0.0 - 1.0)
            # Lower values = more sensitive to quiet sounds
            # Higher values = only loud sounds trigger detection
            # 0.01 is a good default for typical environments
            # 0.001 for quiet rooms, 0.05 for noisy environments
            silence_threshold: 0.01

            # ─────────────────────────────────────────────────────────────────────────
            # OUTPUT MODE
            # ─────────────────────────────────────────────────────────────────────────
            # Choose how to output detected commands:
            #   "webhook" → POST to a URL (recommended for production)
            #   "file"    → Write JSONL lines to a file
            output_mode: "webhook"

            # ─────────────────────────────────────────────────────────────────────────
            # WEBHOOK OUTPUT (when output_mode: "webhook")
            # ─────────────────────────────────────────────────────────────────────────
            #
            # Use webhook mode for production deployments where you need
            # real-time command delivery to your backend or agent system.

            # Required: URL to POST commands to
            webhook_url: "https://gateway.openclaw.io/hooks/agent"

            # Required: Bearer token for authentication
            # Set via environment: NATIVE_AUDIO_BRIDGE_TOKEN
            webhook_token: "your-token-here"

            # Optional: HTTP method for webhook requests
            # Options: "POST" (default), "PUT"
            # webhook.method: "POST"

            # Optional: Retry failed requests automatically
            # Set to "false" to disable retries
            webhook.retry: true

            # ─────────────────────────────────────────────────────────────────────────
            # FILE OUTPUT (when output_mode: "file")
            # ─────────────────────────────────────────────────────────────────────────
            #
            # Use file mode for testing, debugging, or local development.
            # Each command is written as a JSON line (JSONL) to the specified file.
            #
            # Example JSONL output:
            #   {"transcript": "turn on the lights", "timestamp": "2024-01-15T10:30:00Z"}
            #   {"transcript": "play some music", "timestamp": "2024-01-15T10:31:15Z"}

            # Path for output file. Use "-" for stdout (console output).
            # Example paths:
            #   "-"          → Print to console/stdout
            #   "commands.jsonl"     → Write to current directory
            #   "/tmp/voice-commands.jsonl" → Write to temp directory
            #   "~/voice-commands.jsonl"     → Write to home directory
            # file.path: "-"

            # Whether to rotate files daily (adds date suffix).
            # When enabled, files are named: commands-2024-01-15.jsonl
            # file.rotate_daily: false

            # ─────────────────────────────────────────────────────────────────────────
            # LOGGING
            # ─────────────────────────────────────────────────────────────────────────
            # Controls verbosity of console output.
            # Options:
            #   "debug" → Detailed logs for troubleshooting
            #   "info"  → Normal operational logs (recommended)
            #   "error" → Only errors and critical messages
            log_level: "info"

            # ═══════════════════════════════════════════════════════════════════════════
            # EXAMPLE CONFIGURATIONS
            # ═══════════════════════════════════════════════════════════════════════════
            #
            # PRODUCTION CONFIG (webhook mode):
            # ───────────────────────────────────────────────────────────────────────
            # hot_word: "hey claW"
            # case_sensitive: false
            # silence_timeout: 1500
            # silence_threshold: 0.01
            # output_mode: "webhook"
            # webhook_url: "https://your-server.com/api/commands"
            # webhook_token: "your-secure-token-here"
            # webhook.retry: true
            # log_level: "info"
            #
            # TESTING CONFIG (console output):
            # ───────────────────────────────────────────────────────────────────────
            # hot_word: "hey claW"
            # case_sensitive: false
            # silence_timeout: 2000
            # silence_threshold: 0.01
            # output_mode: "file"
            # file.path: "-"
            # log_level: "debug"
            #
            # DEBUGGING CONFIG (file output):
            # ───────────────────────────────────────────────────────────────────────
            # hot_word: "hey claW"
            # case_sensitive: false
            # silence_timeout: 1500
            # silence_threshold: 0.01
            # output_mode: "file"
            # file.path: "/tmp/voice-commands.jsonl"
            # file.rotate_daily: true
            # log_level: "debug"
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

        if config.outputMode == .webhook {
            print("🌐 Webhook:")
            print("   URL: \(config.webhookURL)")
            print("   Token: \(config.webhookToken.isEmpty ? "❌ Not set" : "✅ Configured")")
        } else {
            print("📄 File output:")
            print("   Path: \(config.fileOutput.path)")
        }
        print("")

        let allPassed = micStatus.granted && speechStatus.granted && (config.outputMode == .file || !config.webhookToken.isEmpty)
        print("───────────────────────────────────────────────────────────────")
        print("Status: \(allPassed ? "✅ Ready to start" : "⚠️  Some issues need attention")")
        print("")
    }

    private func performPermissionsCheck() async {
        print("")
        print("╔══════════════════════════════════════════════════════════════╗")
        print("║          Native Audio Bridge - Permission Check                  ║")
        print("╚══════════════════════════════════════════════════════════════╝")
        print("")

        let micStatus = await Self.checkMicrophonePermission()
        print("🎤 Microphone:")
        print("   Status: \(micStatus.icon) \(micStatus.status)")
        if !micStatus.granted {
            print("   Fix: Enable in System Settings > Privacy & Security > Microphone")
        }
        print("")

        let speechStatus = Self.checkSpeechRecognitionPermission()
        print("🔊 Speech Recognition:")
        print("   Status: \(speechStatus.icon) \(speechStatus.status)")
        if !speechStatus.granted {
            print("   Fix: Enable in System Settings > Privacy & Security > Speech Recognition")
        }
        print("")

        #if os(macOS)
        let audioDevices = AVCaptureDevice.devices(for: .audio)
        let deviceCount = audioDevices.count
        print("🎛️  Audio Input Devices:")
        print("   Count: \(deviceCount)")
        if deviceCount == 0 {
            print("   Fix: Connect a microphone or check System Settings > Sound > Input")
        } else {
            for device in AVCaptureDevice.devices(for: .audio) {
                print("   - \(device.localizedName)")
            }
        }
        print("")
        #endif

        let allGranted = micStatus.granted && speechStatus.granted
        print("───────────────────────────────────────────────────────────────")
        if allGranted {
            print("Status: ✅ All permissions granted")
        } else {
            print("Status: ⚠️  Permissions missing")
            print("")
            print("To fix:")
            print("  • Open: System Settings > Privacy & Security")
            print("  • Enable Microphone and Speech Recognition")
            #if os(macOS)
            if deviceCount == 0 {
                print("  • Connect a microphone")
            }
            #endif
        }
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
        let statusIcon: String
        switch config.outputMode {
        case .webhook:
            statusIcon = "[🌐 Webhook]"
        case .file:
            statusIcon = "[📄 File]"
        }
        print("   Status: [🎤 Microphone] [🔊 Speech recognition] \(statusIcon)")
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
