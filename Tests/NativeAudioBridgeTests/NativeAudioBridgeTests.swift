import XCTest
@testable import NativeAudioBridge

final class NativeAudioBridgeTests: XCTestCase {
    func testStateManagerInitialState() {
        let manager = StateManager()
        XCTAssertEqual(manager.state, .idle)
    }

    func testStateManagerTransition() {
        let manager = StateManager()
        var transitions: [(BridgeState, BridgeState)] = []
        manager.setOnStateChange { old, new in
            transitions.append((old, new))
        }
        manager.transition(to: .listening)
        XCTAssertEqual(manager.state, .listening)
        XCTAssertEqual(transitions.count, 1)
        XCTAssertEqual(transitions[0].0, .idle)
        XCTAssertEqual(transitions[0].1, .listening)
    }

    func testAudioEngineCreation() {
        let engine = AudioEngine()
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.sampleRateValue, 16000)
    }
}