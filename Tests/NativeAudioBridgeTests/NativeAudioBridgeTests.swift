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
    assert(a == nil, "\(message) - expected nil", file: file, line: line)
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

// MARK: - CommandBuffer Tests

func testCommandBufferStartCaptureSetsCapturing() {
    let buffer = CommandBuffer()
    assert(!buffer.capturing, "should not be capturing initially")
    buffer.startCapture()
    usleep(50000)
    assert(buffer.capturing, "should be capturing after startCapture")
}

func testCommandBufferStopCaptureClearsCapturing() {
    let buffer = CommandBuffer()
    buffer.startCapture()
    usleep(50000)
    assert(buffer.capturing, "should be capturing after startCapture")
    buffer.stopCapture()
    usleep(50000)
    assert(!buffer.capturing, "should not be capturing after stopCapture")
}

func testCommandBufferAppendStoresData() {
    let buffer = CommandBuffer()
    buffer.startCapture()
    usleep(50000)
    let sampleData = createSilentAudioData(count: 1024)
    buffer.append(sampleData)
    usleep(100000)
    let buffers = buffer.getBuffers()
    assertEqual(buffers.count, 1, "should have 1 buffer")
    assertEqual(buffers[0].count, sampleData.count, "buffer size should match")
}

func testCommandBufferCircularEviction() {
    let buffer = CommandBuffer()
    buffer.startCapture()
    usleep(50000)
    let largeData = Data(repeating: 0xAA, count: 1024 * 1024)
    for _ in 0..<82 {
        buffer.append(largeData)
    }
    usleep(200000)
    let buffers = buffer.getBuffers()
    assert(buffers.count <= 81, "buffer should evict old data when exceeding memory limit")
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
    for i in 0..<512 {
        floats.append(sin(Float(i) * 0.1))
    }
    let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
    let rms = buffer.calculateRMS(from: data)
    assert(rms > 0.0, "RMS of signal should be positive")
    assert(rms < 1.0, "RMS of signal should be less than 1")
}

func testCommandBufferSilenceDetection() {
    let buffer = CommandBuffer(silenceTimeoutMs: 100, silenceThreshold: 0.5)
    var silenceDetected = false
    buffer.onSilenceDetected = {
        silenceDetected = true
    }
    buffer.startCapture()
    usleep(50000)
    let silentData = Data(repeating: 0, count: 256 * MemoryLayout<Float>.size)
    buffer.append(silentData)

    let deadline = Date().addingTimeInterval(3.0)
    while !silenceDetected && Date() < deadline {
        usleep(50000)
    }
    assert(silenceDetected, "silence should be detected")
    usleep(100000)
    assert(!buffer.capturing, "capture should stop after silence detection")
}

func testCommandBufferNoSilenceDetectionWithLoudAudio() {
    let buffer = CommandBuffer(silenceTimeoutMs: 500, silenceThreshold: 0.01)
    var silenceDetected = false
    buffer.onSilenceDetected = {
        silenceDetected = true
    }
    buffer.startCapture()
    var loudFloats: [Float] = []
    for i in 0..<512 {
        loudFloats.append(sin(Float(i) * 0.1) * 0.5)
    }
    let loudData = loudFloats.withUnsafeBufferPointer { Data(buffer: $0) }
    buffer.append(loudData)

    usleep(800000)
    assert(!silenceDetected, "silence should not be detected with loud audio")
    assert(buffer.capturing, "capture should continue with loud audio")
}

func testCommandBufferClearBuffers() {
    let buffer = CommandBuffer()
    buffer.startCapture()
    let data = Data(repeating: 0x55, count: 256)
    buffer.append(data)
    usleep(100000)
    assertEqual(buffer.getBuffers().count, 1, "should have 1 buffer before clear")
    buffer.clearBuffers()
    usleep(100000)
    assertEqual(buffer.getBuffers().count, 0, "should have 0 buffers after clear")
}

// MARK: - CommandProcessor Tests

func testCommandProcessorSanitizeTrim() {
    let processor = CommandProcessor()
    let result = processor.sanitize("  hello world  ")
    assertEqual(result, "hello world", "should trim whitespace")
}

func testCommandProcessorSanitizeMultipleSpaces() {
    let processor = CommandProcessor()
    let result = processor.sanitize("hello   world")
    assertEqual(result, "hello world", "should normalize multiple spaces")
}

func testCommandProcessorSanitizeLowercase() {
    let processor = CommandProcessor()
    let result = processor.sanitize("HELLO WORLD")
    assertEqual(result, "hello world", "should lowercase")
}

func testCommandProcessorSanitizeNewlines() {
    let processor = CommandProcessor()
    let result = processor.sanitize("\n  hello world  \n")
    assertEqual(result, "hello world", "should trim newlines")
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
    let payload = processor.preparePayload(transcript: "   ")
    assertNil(payload, "empty transcript should return nil")
}

func testCommandProcessorPreparePayloadCustom() {
    let processor = CommandProcessor(name: "TestBot", agentId: "test-agent", wakeMode: "push")
    let payload = processor.preparePayload(transcript: "hello")
    assertNotNil(payload, "payload should not be nil")
    assertEqual(payload!.name, "TestBot", "name should be custom")
    assertEqual(payload!.agentId, "test-agent", "agentId should be custom")
    assertEqual(payload!.wakeMode, "push", "wakeMode should be custom")
}

func testDispatchPayloadEncoding() throws {
    let payload = DispatchPayload(message: "turn on lights", name: "AudioBridge", agentId: "audio-bridge", wakeMode: "now")
    let data = try JSONEncoder().encode(payload)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: String]
    assertEqual(json["message"], "turn on lights", "message field")
    assertEqual(json["name"], "AudioBridge", "name field")
    assertEqual(json["agentId"], "audio-bridge", "agentId field")
    assertEqual(json["wakeMode"], "now", "wakeMode field")
}

// MARK: - WebhookDispatcher Tests

func testWebhookInitValidURL() throws {
    let dispatcher = try WebhookDispatcher(
        webhookURL: "https://example.com/webhook",
        bearerToken: "test-token"
    )
    assertNotNil(dispatcher as Any?, "dispatcher should be created")
}

func testWebhookInitInvalidURL() {
    assertThrowsError(try WebhookDispatcher(webhookURL: "", bearerToken: "test-token"), "should throw for empty URL")
}

func testWebhookSuccessfulDispatch() async throws {
    let mockSession = MockHTTPHelper.createMockSession(statusCode: 200, responseBody: Data())
    let dispatcher = try WebhookDispatcher(
        webhookURL: "https://example.com/webhook",
        bearerToken: "test-token",
        maxRetries: 1,
        session: mockSession
    )
    let payload = DispatchPayload(message: "test", name: "AudioBridge", agentId: "audio-bridge", wakeMode: "now")
    let result = try await dispatcher.dispatch(payload: payload)
    assert(result, "dispatch should succeed")
}

func testWebhookRetryOnFailure() async throws {
    let mockSession = MockHTTPHelper.createFailingMockSession()
    let dispatcher = try WebhookDispatcher(
        webhookURL: "https://example.com/webhook",
        bearerToken: "test-token",
        maxRetries: 2,
        baseDelayMs: 50,
        session: mockSession
    )
    let payload = DispatchPayload(message: "test", name: "AudioBridge", agentId: "audio-bridge", wakeMode: "now")
    do {
        _ = try await dispatcher.dispatch(payload: payload)
        assert(false, "should throw after max retries exceeded")
    } catch {
        guard let dispatchError = error as? WebhookDispatcherError else {
            assert(false, "expected WebhookDispatcherError")
            return
        }
        if case .maxRetriesExceeded = dispatchError {
            assert(true, "correct error type")
        } else {
            assert(false, "expected maxRetriesExceeded, got \(dispatchError)")
        }
    }
}

func testWebhookHTTPErrorStatusCode() async throws {
    let mockSession = MockHTTPHelper.createMockSession(statusCode: 500, responseBody: Data("internal error".utf8))
    let dispatcher = try WebhookDispatcher(
        webhookURL: "https://example.com/webhook",
        bearerToken: "test-token",
        maxRetries: 1,
        baseDelayMs: 50,
        session: mockSession
    )
    let payload = DispatchPayload(message: "test", name: "AudioBridge", agentId: "audio-bridge", wakeMode: "now")
    do {
        _ = try await dispatcher.dispatch(payload: payload)
        assert(false, "should throw on 500")
    } catch let dispatchError as WebhookDispatcherError {
        if case .httpError(let statusCode, _) = dispatchError {
            assertEqual(statusCode, 500, "status code should be 500")
        } else {
            assert(false, "expected httpError, got \(dispatchError)")
        }
    } catch {
        assert(false, "expected WebhookDispatcherError")
    }
}

func testWebhookBearerTokenInRequest() async throws {
    var capturedRequest: URLRequest? = nil
    let protocolClass: AnyClass = RequestCaptureHelper.mockProtocol { request in
        capturedRequest = request
    }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [protocolClass]
    let session = URLSession(configuration: config)

    let dispatcher = try WebhookDispatcher(
        webhookURL: "https://example.com/webhook",
        bearerToken: "my-secret-token",
        maxRetries: 1,
        session: session
    )
    let payload = DispatchPayload(message: "test", name: "AudioBridge", agentId: "audio-bridge", wakeMode: "now")
    _ = try await dispatcher.dispatch(payload: payload)

    assertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer my-secret-token", "auth header")
    assertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json", "content type")
    assertEqual(capturedRequest?.httpMethod, "POST", "method")
}

// MARK: - StateManager Tests

func testStateManagerInitialState() {
    let manager = StateManager()
    assertEqual(manager.state, BridgeState.idle, "initial state should be idle")
}

func testStateManagerTransition() {
    let manager = StateManager()
    manager.transition(to: .listening)
    usleep(100000)
    assertEqual(manager.state, BridgeState.listening, "state should be listening after transition")
}

func testStateManagerMultipleTransitions() {
    let manager = StateManager()
    manager.transition(to: .listening)
    usleep(50000)
    manager.transition(to: .processing)
    usleep(50000)
    manager.transition(to: .dispatching)
    usleep(50000)
    assertEqual(manager.state, BridgeState.dispatching, "state should be dispatching")
}

// MARK: - AudioEngine Tests

func testAudioEngineCreation() {
    let engine = AudioEngine()
    assert(!engine.isRunning, "should not be running initially")
    assertEqual(engine.sampleRateValue, 16000.0, "sample rate should be 16000")
}

// MARK: - HotWordDetector Tests

func testHotWordDetection() {
    let detector = HotWordDetector(hotWord: "hey claW")
    detector.onHotWordDetected = { }
    let result = detector.process(transcript: "hey claW what's the weather")
    assert(result, "should detect hot word")
}

func testHotWordNotDetected() {
    let detector = HotWordDetector(hotWord: "hey claW")
    let result = detector.process(transcript: "what's the weather today")
    assert(!result, "should not detect hot word")
}

func testHotWordCaseInsensitive() {
    let detector = HotWordDetector(hotWord: "hey claW")
    _ = detector.process(transcript: "HEY CLAW what's up")
    assertEqual(detector.state, HotWordDetectorState.listening, "should detect case-insensitive hot word")
}

func testHotWordReset() {
    let detector = HotWordDetector(hotWord: "hey claW")
    _ = detector.process(transcript: "hey claW")
    assertEqual(detector.state, HotWordDetectorState.listening, "should be listening after hot word")
    detector.reset()
    usleep(50000)
    assertEqual(detector.state, HotWordDetectorState.idle, "should be idle after reset")
}

// MARK: - Mock Helpers

class MockResponseProtocol: URLProtocol {
    static var mockStatusCode: Int = 200
    static var mockResponseBody: Data = Data()
    static var shouldFail: Bool = false

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if Self.shouldFail {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "test", code: -1, userInfo: nil))
        } else {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: Self.mockStatusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.mockResponseBody)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

class MockHTTPHelper {
    static func createMockSession(statusCode: Int, responseBody: Data) -> URLSession {
        MockResponseProtocol.mockStatusCode = statusCode
        MockResponseProtocol.mockResponseBody = responseBody
        MockResponseProtocol.shouldFail = false
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockResponseProtocol.self]
        return URLSession(configuration: config)
    }

    static func createFailingMockSession() -> URLSession {
        MockResponseProtocol.shouldFail = true
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockResponseProtocol.self]
        return URLSession(configuration: config)
    }
}

class RequestCaptureHelper: URLProtocol {
    private static var requestHandler: ((URLRequest) -> Void)?

    static func mockProtocol(handler: @escaping (URLRequest) -> Void) -> AnyClass {
        requestHandler = handler
        return RequestCaptureHelper.self
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        RequestCaptureHelper.requestHandler?(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Test Runner

@main
struct TestRunner {
    static func main() async {
        print("Running NativeAudioBridge Tests...\n")

        let testFunctions: [(String, () async throws -> Void)] = [
            ("testCommandBufferStartCaptureSetsCapturing", { testCommandBufferStartCaptureSetsCapturing() }),
            ("testCommandBufferStopCaptureClearsCapturing", { testCommandBufferStopCaptureClearsCapturing() }),
            ("testCommandBufferAppendStoresData", { testCommandBufferAppendStoresData() }),
            ("testCommandBufferCircularEviction", { testCommandBufferCircularEviction() }),
            ("testCommandBufferRMSCalculationSilence", { testCommandBufferRMSCalculationSilence() }),
            ("testCommandBufferRMSCalculationSignal", { testCommandBufferRMSCalculationSignal() }),
            ("testCommandBufferSilenceDetection", { testCommandBufferSilenceDetection() }),
            ("testCommandBufferNoSilenceDetectionWithLoudAudio", { testCommandBufferNoSilenceDetectionWithLoudAudio() }),
            ("testCommandBufferClearBuffers", { testCommandBufferClearBuffers() }),
            ("testCommandProcessorSanitizeTrim", { testCommandProcessorSanitizeTrim() }),
            ("testCommandProcessorSanitizeMultipleSpaces", { testCommandProcessorSanitizeMultipleSpaces() }),
            ("testCommandProcessorSanitizeLowercase", { testCommandProcessorSanitizeLowercase() }),
            ("testCommandProcessorSanitizeNewlines", { testCommandProcessorSanitizeNewlines() }),
            ("testCommandProcessorPreparePayloadValid", { testCommandProcessorPreparePayloadValid() }),
            ("testCommandProcessorPreparePayloadEmpty", { testCommandProcessorPreparePayloadEmpty() }),
            ("testCommandProcessorPreparePayloadCustom", { testCommandProcessorPreparePayloadCustom() }),
            ("testDispatchPayloadEncoding", { try testDispatchPayloadEncoding() }),
            ("testWebhookInitValidURL", { try testWebhookInitValidURL() }),
            ("testWebhookInitInvalidURL", { testWebhookInitInvalidURL() }),
            ("testWebhookSuccessfulDispatch", { try await testWebhookSuccessfulDispatch() }),
            ("testWebhookRetryOnFailure", { try await testWebhookRetryOnFailure() }),
            ("testWebhookHTTPErrorStatusCode", { try await testWebhookHTTPErrorStatusCode() }),
            ("testWebhookBearerTokenInRequest", { try await testWebhookBearerTokenInRequest() }),
            ("testStateManagerInitialState", { testStateManagerInitialState() }),
            ("testStateManagerTransition", { testStateManagerTransition() }),
            ("testStateManagerMultipleTransitions", { testStateManagerMultipleTransitions() }),
            ("testAudioEngineCreation", { testAudioEngineCreation() }),
            ("testHotWordDetection", { testHotWordDetection() }),
            ("testHotWordNotDetected", { testHotWordNotDetected() }),
            ("testHotWordCaseInsensitive", { testHotWordCaseInsensitive() }),
            ("testHotWordReset", { testHotWordReset() }),
        ]

        var passed = 0
        var failed = 0

        for (name, testFn) in testFunctions {
            print("Running \(name)...")
            do {
                try await testFn()
                passed += 1
                print("  PASS")
            } catch {
                failed += 1
                print("  FAIL: \(error)")
            }
        }

        print("\n\(testsPassed) assertions passed, \(testsFailed) assertions failed")
        print("\(passed) tests passed, \(failed) tests failed out of \(testFunctions.count) total")

        if failed > 0 || testsFailed > 0 {
            exit(1)
        }
    }
}