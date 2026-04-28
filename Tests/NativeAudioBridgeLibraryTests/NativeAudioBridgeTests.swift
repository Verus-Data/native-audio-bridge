import XCTest
@testable import NativeAudioBridgeLibrary

final class CommandBufferTests: XCTestCase {

    func testStartCaptureSetsCapturing() {
        let buffer = CommandBuffer()
        XCTAssertFalse(buffer.capturing)
        buffer.startCapture()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertTrue(buffer.capturing)
        buffer.stopCapture()
    }

    func testStopCaptureClearsCapturing() {
        let buffer = CommandBuffer()
        buffer.startCapture()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertTrue(buffer.capturing)
        buffer.stopCapture()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertFalse(buffer.capturing)
    }

    func testAppendStoresData() {
        let buffer = CommandBuffer()
        buffer.startCapture()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let sampleData = createSilentAudioData(count: 1024)
        buffer.append(sampleData)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        let buffers = buffer.getBuffers()
        XCTAssertEqual(buffers.count, 1)
        XCTAssertEqual(buffers[0].count, sampleData.count)
        buffer.stopCapture()
    }

    func testRMSCalculationSilence() {
        let buffer = CommandBuffer()
        let silentData = Data(repeating: 0, count: 1024 * MemoryLayout<Float>.size)
        let rms = buffer.calculateRMS(from: silentData)
        XCTAssertEqual(rms, 0.0)
    }

    func testRMSCalculationSignal() {
        let buffer = CommandBuffer()
        var floats: [Float] = []
        for i in 0..<512 { floats.append(sin(Float(i) * 0.1)) }
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        let rms = buffer.calculateRMS(from: data)
        XCTAssertGreaterThan(rms, 0.0)
        XCTAssertLessThan(rms, 1.0)
    }

    func testSilenceDetection() {
        let buffer = CommandBuffer(silenceTimeoutMs: 100, silenceThreshold: 0.5)
        let expectation = self.expectation(description: "silence detected")
        buffer.onSilenceDetected = { expectation.fulfill() }
        buffer.startCapture()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let silentData = Data(repeating: 0, count: 256 * MemoryLayout<Float>.size)
        buffer.append(silentData)
        waitForExpectations(timeout: 3.0)
        XCTAssertFalse(buffer.capturing)
    }

    func testClearBuffers() {
        let buffer = CommandBuffer()
        buffer.startCapture()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let data = Data(repeating: 0x55, count: 256)
        buffer.append(data)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertEqual(buffer.getBuffers().count, 1)
        buffer.clearBuffers()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertEqual(buffer.getBuffers().count, 0)
        buffer.stopCapture()
    }

    private func createSilentAudioData(count: Int) -> Data {
        var floats = [Float](repeating: 0.0, count: count)
        return floats.withUnsafeMutableBufferPointer { Data(buffer: $0) }
    }
}

final class CommandProcessorTests: XCTestCase {

    func testSanitizeTrim() {
        let processor = CommandProcessor()
        XCTAssertEqual(processor.sanitize("  hello world  "), "hello world")
    }

    func testSanitizeMultipleSpaces() {
        let processor = CommandProcessor()
        XCTAssertEqual(processor.sanitize("hello   world"), "hello world")
    }

    func testSanitizeLowercase() {
        let processor = CommandProcessor()
        XCTAssertEqual(processor.sanitize("HELLO WORLD"), "hello world")
    }

    func testSanitizeNewlines() {
        let processor = CommandProcessor()
        XCTAssertEqual(processor.sanitize("\n  hello world  \n"), "hello world")
    }

    func testPreparePayloadValid() {
        let processor = CommandProcessor()
        let payload = processor.preparePayload(transcript: "  turn on the lights  ")
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload!.message, "turn on the lights")
        XCTAssertEqual(payload!.name, "AudioBridge")
        XCTAssertEqual(payload!.agentId, "audio-bridge")
        XCTAssertEqual(payload!.wakeMode, "now")
    }

    func testPreparePayloadEmpty() {
        let processor = CommandProcessor()
        XCTAssertNil(processor.preparePayload(transcript: "   "))
    }

    func testPreparePayloadCustom() {
        let processor = CommandProcessor(name: "TestBot", agentId: "test-agent", wakeMode: "push")
        let payload = processor.preparePayload(transcript: "hello")
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload!.name, "TestBot")
        XCTAssertEqual(payload!.agentId, "test-agent")
    }
}

final class WebhookDispatcherTests: XCTestCase {

    func testInitValidURL() {
        let dispatcher = try? WebhookDispatcher(webhookURL: "https://example.com/webhook", bearerToken: "test-token")
        XCTAssertNotNil(dispatcher)
    }

    func testInitInvalidURL() {
        XCTAssertThrowsError(try WebhookDispatcher(webhookURL: "", bearerToken: "test-token"))
    }
}

final class StateManagerTests: XCTestCase {

    func testInitialState() {
        let manager = StateManager()
        XCTAssertEqual(manager.state, BridgeState.idle)
    }

    func testTransition() {
        let manager = StateManager()
        manager.transition(to: .listening)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertEqual(manager.state, BridgeState.listening)
    }
}

final class AudioEngineTests: XCTestCase {

    func testCreation() {
        let engine = AudioEngine()
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.sampleRateValue, 16000.0)
    }
}

final class HotWordDetectorTests: XCTestCase {

    func testDetection() {
        let detector = HotWordDetector(hotWord: "hey claW")
        detector.onHotWordDetected = { }
        XCTAssertTrue(detector.process(transcript: "hey claW what's the weather"))
    }

    func testNotDetected() {
        let detector = HotWordDetector(hotWord: "hey claW")
        XCTAssertFalse(detector.process(transcript: "what's the weather today"))
    }

    func testCaseInsensitive() {
        let detector = HotWordDetector(hotWord: "hey claW")
        _ = detector.process(transcript: "HEY CLAW what's up")
        XCTAssertEqual(detector.state, HotWordDetectorState.listening)
    }
}

final class ConfigurationManagerTests: XCTestCase {

    func testDefaults() {
        let env: [String: String] = ["NATIVE_AUDIO_BRIDGE_TOKEN": "test-token"]
        let manager = ConfigurationManager(environment: env)
        let config = try! manager.load()
        XCTAssertEqual(config.hotWord, "hey claW")
        XCTAssertEqual(config.silenceTimeoutMs, 1500)
        XCTAssertEqual(config.silenceThreshold, Float(0.01))
        XCTAssertEqual(config.webhookURL, "https://gateway.openclaw.io/hooks/agent")
        XCTAssertEqual(config.webhookToken, "test-token")
        XCTAssertEqual(config.logLevel, LogLevel.info)
    }

    func testEnvOverride() {
        let env: [String: String] = [
            "NATIVE_AUDIO_BRIDGE_TOKEN": "env-token",
            "NATIVE_AUDIO_BRIDGE_HOT_WORD": "hey coffee",
            "NATIVE_AUDIO_BRIDGE_SILENCE_TIMEOUT": "2000",
            "NATIVE_AUDIO_BRIDGE_SILENCE_THRESHOLD": "0.05",
            "NATIVE_AUDIO_BRIDGE_WEBHOOK_URL": "https://example.com/hook",
            "NATIVE_AUDIO_BRIDGE_LOG_LEVEL": "debug"
        ]
        let manager = ConfigurationManager(environment: env)
        let config = try! manager.load()
        XCTAssertEqual(config.hotWord, "hey coffee")
        XCTAssertEqual(config.silenceTimeoutMs, 2000)
        XCTAssertEqual(config.silenceThreshold, Float(0.05))
        XCTAssertEqual(config.webhookURL, "https://example.com/hook")
        XCTAssertEqual(config.webhookToken, "env-token")
        XCTAssertEqual(config.logLevel, LogLevel.debug)
    }

    func testMissingTokenFails() {
        let env: [String: String] = [:]
        let manager = ConfigurationManager(environment: env)
        XCTAssertThrowsError(try manager.load())
    }

    func testInvalidURLFails() {
        let env: [String: String] = [
            "NATIVE_AUDIO_BRIDGE_TOKEN": "test",
            "NATIVE_AUDIO_BRIDGE_WEBHOOK_URL": "not-a-url"
        ]
        let manager = ConfigurationManager(environment: env)
        XCTAssertThrowsError(try manager.load())
    }

    func testConfigFile() {
        let tempDir = NSTemporaryDirectory()
        let configPath = tempDir + "test_config_\(Int(Date().timeIntervalSince1970)).yaml"
        let yaml = """
        hot_word: "hey custom"
        silence_timeout: "3000"
        silence_threshold: "0.02"
        webhook_url: "https://custom.example.com/hook"
        webhook_token: "file-token"
        """
        try! yaml.write(toFile: configPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let env: [String: String] = [:]
        let manager = ConfigurationManager(environment: env)
        let config = try! manager.load(from: configPath)
        XCTAssertEqual(config.hotWord, "hey custom")
        XCTAssertEqual(config.silenceTimeoutMs, 3000)
        XCTAssertEqual(config.silenceThreshold, Float(0.02))
        XCTAssertEqual(config.webhookURL, "https://custom.example.com/hook")
        XCTAssertEqual(config.webhookToken, "file-token")
    }

    func testEnvOverridesFile() {
        let tempDir = NSTemporaryDirectory()
        let configPath = tempDir + "test_config_override_\(Int(Date().timeIntervalSince1970)).yaml"
        let yaml = "hot_word: \"from file\""
        try! yaml.write(toFile: configPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let env: [String: String] = [
            "NATIVE_AUDIO_BRIDGE_TOKEN": "env-token",
            "NATIVE_AUDIO_BRIDGE_HOT_WORD": "from env"
        ]
        let manager = ConfigurationManager(environment: env)
        let config = try! manager.load(from: configPath)
        XCTAssertEqual(config.hotWord, "from env")
        XCTAssertEqual(config.webhookToken, "env-token")
    }
}

final class LogLevelTests: XCTestCase {

    func testFromRawValue() {
        XCTAssertEqual(LogLevel(rawValue: "debug"), LogLevel.debug)
        XCTAssertEqual(LogLevel(rawValue: "info"), LogLevel.info)
        XCTAssertEqual(LogLevel(rawValue: "error"), LogLevel.error)
        XCTAssertEqual(LogLevel(rawValue: "DEBUG".lowercased()), LogLevel.debug)
        XCTAssertNil(LogLevel(rawValue: "invalid"))
    }
}

final class AppLoggerTests: XCTestCase {

    func testLogLevelFiltering() {
        let log = AppLogger.shared
        log.setLogLevel(.error)
        log.debug("should not appear")
        log.info("should not appear")
        log.error("should appear")
        log.setLogLevel(.info)
    }
}

final class VersionTests: XCTestCase {

    func testVersionString() {
        let version = AppVersion.current
        XCTAssertFalse(version.isEmpty)
        let parts = version.split(separator: ".").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 3, "version should have 3 components (semver)")
        if parts.count >= 1 {
            XCTAssertGreaterThanOrEqual(parts[0], 0)
        }
    }
}

final class OutputModeTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(OutputMode.allCases.count, 4)
        XCTAssertTrue(OutputMode.allCases.contains(.webhook))
        XCTAssertTrue(OutputMode.allCases.contains(.jsonlFile))
        XCTAssertTrue(OutputMode.allCases.contains(.both))
        XCTAssertTrue(OutputMode.allCases.contains(.telegram))
    }

    func testRawValues() {
        XCTAssertEqual(OutputMode.webhook.rawValue, "webhook")
        XCTAssertEqual(OutputMode.jsonlFile.rawValue, "jsonlFile")
        XCTAssertEqual(OutputMode.both.rawValue, "both")
        XCTAssertEqual(OutputMode.telegram.rawValue, "telegram")
    }

    func testDescriptions() {
        XCTAssertEqual(OutputMode.webhook.description, "webhook")
        XCTAssertEqual(OutputMode.jsonlFile.description, "jsonl-file")
        XCTAssertEqual(OutputMode.both.description, "both")
        XCTAssertEqual(OutputMode.telegram.description, "telegram")
    }

    func testInitFromRawValue() {
        XCTAssertEqual(OutputMode(rawValue: "webhook"), .webhook)
        XCTAssertEqual(OutputMode(rawValue: "jsonlFile"), .jsonlFile)
        XCTAssertEqual(OutputMode(rawValue: "both"), .both)
        XCTAssertEqual(OutputMode(rawValue: "telegram"), .telegram)
        XCTAssertNil(OutputMode(rawValue: "invalid"))
    }
}

final class TelegramAudioExporterTests: XCTestCase {

    func testInitValidConfig() {
        let exporter = try? TelegramAudioExporter(
            botToken: "123456:ABCdef",
            chatId: "-1001234567890"
        )
        XCTAssertNotNil(exporter)
    }

    func testInitEmptyBotTokenFails() {
        XCTAssertThrowsError(try TelegramAudioExporter(
            botToken: "",
            chatId: "-1001234567890"
        )) { error in
            XCTAssertTrue(error is TelegramExporterError)
            if let telegramError = error as? TelegramExporterError {
                XCTAssertEqual(telegramError, .invalidBotToken)
            }
        }
    }

    func testInitEmptyChatIdFails() {
        XCTAssertThrowsError(try TelegramAudioExporter(
            botToken: "123456:ABCdef",
            chatId: ""
        )) { error in
            XCTAssertTrue(error is TelegramExporterError)
            if let telegramError = error as? TelegramExporterError {
                XCTAssertEqual(telegramError, .invalidChatId)
            }
        }
    }

    func testWAVConversionEmptyBuffersFails() {
        let exporter = try! TelegramAudioExporter(
            botToken: "123456:ABCdef",
            chatId: "-1001234567890"
        )
        XCTAssertThrowsError(try exporter.convertToWAV(buffers: [])) { error in
            XCTAssertTrue(error is TelegramExporterError)
        }
    }

    func testWAVConversionProducesValidData() throws {
        let exporter = try TelegramAudioExporter(
            botToken: "123456:ABCdef",
            chatId: "-1001234567890"
        )
        // Create sample PCM float32 data
        var floats: [Float] = []
        for i in 0..<1024 {
            floats.append(sin(Float(i) * 0.1))
        }
        let pcmData = floats.withUnsafeBufferPointer { Data(buffer: $0) }

        let wavData = try exporter.convertToWAV(buffers: [pcmData])
        XCTAssertGreaterThan(wavData.count, 0)

        // Check WAV header starts with "RIFF"
        XCTAssertEqual(wavData[0], 0x52) // R
        XCTAssertEqual(wavData[1], 0x49) // I
        XCTAssertEqual(wavData[2], 0x46) // F
        XCTAssertEqual(wavData[3], 0x46) // F
    }

    func testWAVHeaderFormatIsCorrect() throws {
        let exporter = try TelegramAudioExporter(
            botToken: "123456:ABCdef",
            chatId: "-1001234567890"
        )
        // Create 1 second of silence at 16kHz, 1 channel, 32-bit float
        let sampleCount = 16000
        let floats = [Float](repeating: 0.0, count: sampleCount)
        let pcmData = floats.withUnsafeBufferPointer { Data(buffer: $0) }

        let wavData = try exporter.convertToWAV(buffers: [pcmData], sampleRate: 16000)

        // Check "WAVE" marker at offset 8
        XCTAssertEqual(wavData[8], 0x57) // W
        XCTAssertEqual(wavData[9], 0x41) // A
        XCTAssertEqual(wavData[10], 0x56) // V
        XCTAssertEqual(wavData[11], 0x45) // E

        // Chunk size should be 36 + data size
        let dataSize = UInt32(sampleCount * MemoryLayout<Float>.size)
        let expectedFileSize = 36 + dataSize
        let actualFileSize = wavData[4...7].withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(actualFileSize.littleEndian, expectedFileSize)
    }
}

final class TelegramConfigurationTests: XCTestCase {

    func testTelegramModeRequiresBotToken() {
        let env: [String: String] = [
            "NATIVE_AUDIO_BRIDGE_TOKEN": "test-token",
            "NATIVE_AUDIO_BRIDGE_OUTPUT_MODE": "telegram",
            "NATIVE_AUDIO_BRIDGE_TELEGRAM_CHAT_ID": "-1001234567890"
        ]
        let manager = ConfigurationManager(environment: env)
        XCTAssertThrowsError(try manager.load()) { error in
            XCTAssertTrue(error is ConfigurationError)
        }
    }

    func testTelegramModeRequiresChatId() {
        let env: [String: String] = [
            "NATIVE_AUDIO_BRIDGE_TOKEN": "test-token",
            "NATIVE_AUDIO_BRIDGE_OUTPUT_MODE": "telegram",
            "NATIVE_AUDIO_BRIDGE_TELEGRAM_BOT_TOKEN": "123456:ABCdef"
        ]
        let manager = ConfigurationManager(environment: env)
        XCTAssertThrowsError(try manager.load()) { error in
            XCTAssertTrue(error is ConfigurationError)
        }
    }

    func testTelegramModeWithValidConfig() throws {
        let env: [String: String] = [
            "NATIVE_AUDIO_BRIDGE_TOKEN": "test-token",
            "NATIVE_AUDIO_BRIDGE_OUTPUT_MODE": "telegram",
            "NATIVE_AUDIO_BRIDGE_TELEGRAM_BOT_TOKEN": "123456:ABCdef",
            "NATIVE_AUDIO_BRIDGE_TELEGRAM_CHAT_ID": "-1001234567890"
        ]
        let manager = ConfigurationManager(environment: env)
        let config = try manager.load()
        XCTAssertEqual(config.outputMode, .telegram)
        XCTAssertEqual(config.telegramBotToken, "123456:ABCdef")
        XCTAssertEqual(config.telegramChatId, "-1001234567890")
    }

    func testWebhookModeDoesNotRequireTelegramConfig() throws {
        let env: [String: String] = [
            "NATIVE_AUDIO_BRIDGE_TOKEN": "test-token"
        ]
        let manager = ConfigurationManager(environment: env)
        let config = try manager.load()
        XCTAssertEqual(config.outputMode, .webhook)
        // telegramBotToken and telegramChatId should be empty but that's OK for webhook mode
        XCTAssertEqual(config.telegramBotToken, "")
        XCTAssertEqual(config.telegramChatId, "")
    }
}