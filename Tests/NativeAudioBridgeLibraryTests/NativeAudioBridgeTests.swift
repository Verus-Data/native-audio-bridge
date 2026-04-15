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

    func testFileOutputModeWithNestedYamlKeys() {
        let tempDir = NSTemporaryDirectory()
        let configPath = tempDir + "test_config_file_output_\(Int(Date().timeIntervalSince1970)).yaml"
        // Using nested YAML structure for file output (this is what users expect to work)
        let yaml = """
        hot_word: "hey test"
        output_mode: "file"
        file:
          path: "-"
          rotate_daily: false
        webhook_token: "test-token"
        """
        try! yaml.write(toFile: configPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let env: [String: String] = [:]
        let manager = ConfigurationManager(environment: env)
        let config = try! manager.load(from: configPath)
        
        // This test DEMONSTRATES THE BUG: nested YAML keys don't parse correctly
        // Expected: outputMode should be .file, fileOutput.path should be "-"
        // Actual: outputMode defaults to .webhook because nested keys aren't parsed
        XCTAssertEqual(config.outputMode, OutputMode.file, "file output mode should be parsed from nested YAML")
        XCTAssertEqual(config.fileOutput.path, "-", "file.path should be parsed from nested YAML")
    }

    func testFileOutputModeWithFlatKeys() {
        let tempDir = NSTemporaryDirectory()
        let configPath = tempDir + "test_config_file_output_flat_\(Int(Date().timeIntervalSince1970)).yaml"
        // Using flat dot-notation keys (workaround for the YAML parser limitation)
        let yaml = """
        hot_word: "hey test"
        output_mode: "file"
        file.path: "-"
        file.rotate_daily: false
        webhook_token: "test-token"
        """
        try! yaml.write(toFile: configPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let env: [String: String] = [:]
        let manager = ConfigurationManager(environment: env)
        let config = try! manager.load(from: configPath)
        
        // Flat keys should work correctly
        XCTAssertEqual(config.outputMode, OutputMode.file)
        XCTAssertEqual(config.fileOutput.path, "-")
    }
}

final class LogLevelTests: XCTestCase {

    func testFromString() {
        XCTAssertEqual(LogLevel(from: "debug"), LogLevel.debug)
        XCTAssertEqual(LogLevel(from: "info"), LogLevel.info)
        XCTAssertEqual(LogLevel(from: "error"), LogLevel.error)
        XCTAssertEqual(LogLevel(from: "DEBUG"), LogLevel.debug)
        XCTAssertNil(LogLevel(from: "invalid"))
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