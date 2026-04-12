import Foundation
import NativeAudioBridgeLibrary

private var testsPassed = 0
private var testsFailed = 0

private func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        testsPassed += 1
    } else {
        testsFailed += 1
        let filename = (file as NSString).lastPathComponent
        print("  FAIL [\(filename):\(line)]: \(message)")
    }
}

private func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) {
    assert(a == b, "\(message) - expected \(b), got \(a)", file: file, line: line)
}

private func assertNil<T>(_ a: T?, _ message: String = "", file: String = #file, line: Int = #line) {
    assert(a == nil, "\(message) - expected nil, got \(String(describing: a))", file: file, line: line)
}

private func assertNotNil<T>(_ a: T?, _ message: String = "", file: String = #file, line: Int = #line) {
    assert(a != nil, "\(message) - expected non-nil", file: file, line: line)
}

private func assertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: String = #file, line: Int = #line) {
    do {
        _ = try expression()
        assert(false, "\(message) - expected error to be thrown", file: file, line: line)
    } catch {
        testsPassed += 1
    }
}

private func createSilentAudioData(count: Int) -> Data {
    var floats = [Float](repeating: 0.0, count: count)
    return floats.withUnsafeMutableBufferPointer { Data(buffer: $0) }
}

func testCommandBufferStartCaptureSetsCapturing() {
    let buffer = CommandBuffer()
    assert(!buffer.capturing, "should not be capturing initially")
    buffer.startCapture()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    assert(buffer.capturing, "should be capturing after startCapture")
    buffer.stopCapture()
}

func testCommandBufferStopCaptureClearsCapturing() {
    let buffer = CommandBuffer()
    buffer.startCapture()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    assert(buffer.capturing, "should be capturing after startCapture")
    buffer.stopCapture()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    assert(!buffer.capturing, "should not be capturing after stopCapture")
}

func testCommandBufferAppendStoresData() {
    let buffer = CommandBuffer()
    buffer.startCapture()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    let sampleData = createSilentAudioData(count: 1024)
    buffer.append(sampleData)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    let buffers = buffer.getBuffers()
    assertEqual(buffers.count, 1, "should have 1 buffer")
    assertEqual(buffers[0].count, sampleData.count, "buffer size should match")
    buffer.stopCapture()
}

func testCommandBufferRMSCalculationSilence() {
    let buffer = CommandBuffer()
    let silentData = Data(repeating: 0, count: 1024 * MemoryLayout<Float>.size)
    let rms = buffer.calculateRMS(from: silentData)
    assertEqual(rms, 0.0, "RMS of silence should be 0")
}

func testCommandBufferRMSCalculationSignal() {
    let buffer = CommandBuffer()
    var floats: [Float] = []
    for i in 0..<512 { floats.append(sin(Float(i) * 0.1)) }
    let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
    let rms = buffer.calculateRMS(from: data)
    assert(rms > 0.0, "RMS of signal should be positive")
    assert(rms < 1.0, "RMS of signal should be less than 1")
}

func testCommandBufferSilenceDetection() {
    let buffer = CommandBuffer(silenceTimeoutMs: 100, silenceThreshold: 0.5)
    var silenceDetected = false
    buffer.onSilenceDetected = { silenceDetected = true }
    buffer.startCapture()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    let silentData = Data(repeating: 0, count: 256 * MemoryLayout<Float>.size)
    buffer.append(silentData)
    let deadline = Date().addingTimeInterval(3.0)
    while !silenceDetected && Date() < deadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    assert(silenceDetected, "silence should be detected within timeout")
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    assert(!buffer.capturing, "capture should stop after silence detection")
}

func testCommandBufferClearBuffers() {
    let buffer = CommandBuffer()
    buffer.startCapture()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    let data = Data(repeating: 0x55, count: 256)
    buffer.append(data)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    assertEqual(buffer.getBuffers().count, 1, "should have 1 buffer before clear")
    buffer.clearBuffers()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    assertEqual(buffer.getBuffers().count, 0, "should have 0 buffers after clear")
    buffer.stopCapture()
}

func testCommandProcessorSanitizeTrim() {
    let processor = CommandProcessor()
    assertEqual(processor.sanitize("  hello world  "), "hello world", "should trim whitespace")
}

func testCommandProcessorSanitizeMultipleSpaces() {
    let processor = CommandProcessor()
    assertEqual(processor.sanitize("hello   world"), "hello world", "should normalize multiple spaces")
}

func testCommandProcessorSanitizeLowercase() {
    let processor = CommandProcessor()
    assertEqual(processor.sanitize("HELLO WORLD"), "hello world", "should lowercase")
}

func testCommandProcessorSanitizeNewlines() {
    let processor = CommandProcessor()
    assertEqual(processor.sanitize("\n  hello world  \n"), "hello world", "should trim newlines")
}

func testCommandProcessorPreparePayloadValid() {
    let processor = CommandProcessor()
    let payload = processor.preparePayload(transcript: "  turn on the lights  ")
    assertNotNil(payload, "payload should not be nil")
    assertEqual(payload!.message, "turn on the lights", "message should be sanitized")
    assertEqual(payload!.name, "AudioBridge", "name should match")
    assertEqual(payload!.agentId, "audio-bridge", "agentId should match")
    assertEqual(payload!.wakeMode, "now", "wakeMode should match")
}

func testCommandProcessorPreparePayloadEmpty() {
    let processor = CommandProcessor()
    assertNil(processor.preparePayload(transcript: "   "), "empty transcript should return nil")
}

func testCommandProcessorPreparePayloadCustom() {
    let processor = CommandProcessor(name: "TestBot", agentId: "test-agent", wakeMode: "push")
    let payload = processor.preparePayload(transcript: "hello")
    assertNotNil(payload, "payload should not be nil")
    assertEqual(payload!.name, "TestBot", "name should be custom")
    assertEqual(payload!.agentId, "test-agent", "agentId should be custom")
}

func testWebhookInitValidURL() {
    let dispatcher = try? WebhookDispatcher(webhookURL: "https://example.com/webhook", bearerToken: "test-token")
    assertNotNil(dispatcher, "dispatcher should be created")
}

func testWebhookInitInvalidURL() {
    assertThrowsError(try WebhookDispatcher(webhookURL: "", bearerToken: "test-token"), "should throw for empty URL")
}

func testStateManagerInitialState() {
    let manager = StateManager()
    assertEqual(manager.state, BridgeState.idle, "initial state should be idle")
}

func testStateManagerTransition() {
    let manager = StateManager()
    manager.transition(to: .listening)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    assertEqual(manager.state, BridgeState.listening, "state should be listening after transition")
}

func testAudioEngineCreation() {
    let engine = AudioEngine()
    assert(!engine.isRunning, "should not be running initially")
    assertEqual(engine.sampleRateValue, 16000.0, "sample rate should be 16000")
}

func testHotWordDetection() {
    let detector = HotWordDetector(hotWord: "hey claW")
    detector.onHotWordDetected = { }
    assert(detector.process(transcript: "hey claW what's the weather"), "should detect hot word")
}

func testHotWordNotDetected() {
    let detector = HotWordDetector(hotWord: "hey claW")
    assert(!detector.process(transcript: "what's the weather today"), "should not detect hot word")
}

func testHotWordCaseInsensitive() {
    let detector = HotWordDetector(hotWord: "hey claW")
    _ = detector.process(transcript: "HEY CLAW what's up")
    assertEqual(detector.state, HotWordDetectorState.listening, "should detect case-insensitive hot word")
}

func testConfigurationManagerDefaults() {
    let env: [String: String] = ["NATIVE_AUDIO_BRIDGE_TOKEN": "test-token"]
    let manager = ConfigurationManager(environment: env)
    let config = try! manager.load()
    assertEqual(config.hotWord, "hey claW", "hot word default should match")
    assertEqual(config.silenceTimeoutMs, 1500, "silence timeout default should match")
    assertEqual(config.silenceThreshold, Float(0.01), "silence threshold default should match")
    assertEqual(config.webhookURL, "https://gateway.openclaw.io/hooks/agent", "webhook URL default should match")
    assertEqual(config.webhookToken, "test-token", "webhook token should come from env")
    assertEqual(config.logLevel, LogLevel.info, "log level default should be info")
}

func testConfigurationManagerEnvOverride() {
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
    assertEqual(config.hotWord, "hey coffee", "hot word should be overridden by env")
    assertEqual(config.silenceTimeoutMs, 2000, "silence timeout should be overridden by env")
    assertEqual(config.silenceThreshold, Float(0.05), "silence threshold should be overridden by env")
    assertEqual(config.webhookURL, "https://example.com/hook", "webhook URL should be overridden by env")
    assertEqual(config.webhookToken, "env-token", "token should come from env")
    assertEqual(config.logLevel, LogLevel.debug, "log level should be overridden by env")
}

func testConfigurationManagerMissingTokenFails() {
    let env: [String: String] = [:]
    let manager = ConfigurationManager(environment: env)
    assertThrowsError(try manager.load(), "should throw when token is missing")
}

func testConfigurationManagerInvalidURLFails() {
    let env: [String: String] = [
        "NATIVE_AUDIO_BRIDGE_TOKEN": "test",
        "NATIVE_AUDIO_BRIDGE_WEBHOOK_URL": "not-a-url"
    ]
    let manager = ConfigurationManager(environment: env)
    assertThrowsError(try manager.load(), "should throw for invalid URL")
}

func testConfigurationManagerConfigFile() {
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
    assertEqual(config.hotWord, "hey custom", "hot word should come from config file")
    assertEqual(config.silenceTimeoutMs, 3000, "silence timeout should come from config file")
    assertEqual(config.silenceThreshold, Float(0.02), "silence threshold should come from config file")
    assertEqual(config.webhookURL, "https://custom.example.com/hook", "webhook URL should come from config file")
    assertEqual(config.webhookToken, "file-token", "webhook token should come from config file")
}

func testConfigurationManagerEnvOverridesFile() {
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
    assertEqual(config.hotWord, "from env", "env should override config file")
    assertEqual(config.webhookToken, "env-token", "env token should take priority")
}

func testLogLevelFromString() {
    assertEqual(LogLevel(from: "debug"), LogLevel.debug, "debug should parse from string")
    assertEqual(LogLevel(from: "info"), LogLevel.info, "info should parse from string")
    assertEqual(LogLevel(from: "error"), LogLevel.error, "error should parse from string")
    assertEqual(LogLevel(from: "DEBUG"), LogLevel.debug, "DEBUG should parse case-insensitively")
    assertNil(LogLevel(from: "invalid"), "invalid log level should return nil")
}

func testLoggerLogLevelFiltering() {
    let log = Logger.shared
    log.setLogLevel(.error)
    log.debug("should not appear")
    log.info("should not appear")
    log.error("should appear")
    log.setLogLevel(.info)
    log.setLogLevel(.info)
}

func testVersionString() {
    assertEqual(NativeAudioBridgeVersion.versionString, "0.3.0", "version should match semver")
    assert(NativeAudioBridgeVersion.major >= 0, "major version should be non-negative")
}

@main
struct TestRunner {
    static func main() {
        print("Running NativeAudioBridge Tests...\n")
        let tests: [(String, () -> Void)] = [
            ("testCommandBufferStartCaptureSetsCapturing", testCommandBufferStartCaptureSetsCapturing),
            ("testCommandBufferStopCaptureClearsCapturing", testCommandBufferStopCaptureClearsCapturing),
            ("testCommandBufferAppendStoresData", testCommandBufferAppendStoresData),
            ("testCommandBufferRMSCalculationSilence", testCommandBufferRMSCalculationSilence),
            ("testCommandBufferRMSCalculationSignal", testCommandBufferRMSCalculationSignal),
            ("testCommandBufferSilenceDetection", testCommandBufferSilenceDetection),
            ("testCommandBufferClearBuffers", testCommandBufferClearBuffers),
            ("testCommandProcessorSanitizeTrim", testCommandProcessorSanitizeTrim),
            ("testCommandProcessorSanitizeMultipleSpaces", testCommandProcessorSanitizeMultipleSpaces),
            ("testCommandProcessorSanitizeLowercase", testCommandProcessorSanitizeLowercase),
            ("testCommandProcessorSanitizeNewlines", testCommandProcessorSanitizeNewlines),
            ("testCommandProcessorPreparePayloadValid", testCommandProcessorPreparePayloadValid),
            ("testCommandProcessorPreparePayloadEmpty", testCommandProcessorPreparePayloadEmpty),
            ("testCommandProcessorPreparePayloadCustom", testCommandProcessorPreparePayloadCustom),
            ("testWebhookInitValidURL", testWebhookInitValidURL),
            ("testWebhookInitInvalidURL", testWebhookInitInvalidURL),
            ("testStateManagerInitialState", testStateManagerInitialState),
            ("testStateManagerTransition", testStateManagerTransition),
            ("testAudioEngineCreation", testAudioEngineCreation),
            ("testHotWordDetection", testHotWordDetection),
            ("testHotWordNotDetected", testHotWordNotDetected),
            ("testHotWordCaseInsensitive", testHotWordCaseInsensitive),
            ("testConfigurationManagerDefaults", testConfigurationManagerDefaults),
            ("testConfigurationManagerEnvOverride", testConfigurationManagerEnvOverride),
            ("testConfigurationManagerMissingTokenFails", testConfigurationManagerMissingTokenFails),
            ("testConfigurationManagerInvalidURLFails", testConfigurationManagerInvalidURLFails),
            ("testConfigurationManagerConfigFile", testConfigurationManagerConfigFile),
            ("testConfigurationManagerEnvOverridesFile", testConfigurationManagerEnvOverridesFile),
            ("testLogLevelFromString", testLogLevelFromString),
            ("testLoggerLogLevelFiltering", testLoggerLogLevelFiltering),
            ("testVersionString", testVersionString),
        ]
        var passed = 0
        var failed = 0
        var currentFailures = 0
        for (name, testFn) in tests {
            print("Running \(name)...", terminator: "")
            fflush(stdout)
            currentFailures = testsFailed
            testFn()
            if testsFailed == currentFailures {
                passed += 1
                print(" PASS")
            } else {
                failed += 1
                print(" FAIL")
            }
        }
        print("\n\(testsPassed) assertions passed, \(testsFailed) assertions failed")
        print("\(passed) tests passed, \(failed) tests failed out of \(tests.count) total")
        if testsFailed > 0 { exit(1) } else { print("All tests passed!") }
    }
}
