import Foundation

enum BridgeState {
    case idle
    case listening
    case processing
    case dispatching
}

final class StateManager {
    private(set) var state: BridgeState = .idle
    private let stateQueue = DispatchQueue(label: "com.nativeaudiobridge.state", attributes: .concurrent)
    private var onStateChange: ((BridgeState, BridgeState) -> Void)?

    func setOnStateChange(_ handler: @escaping (BridgeState, BridgeState) -> Void) {
        onStateChange = handler
    }

    func transition(to newState: BridgeState) {
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            let oldState = self.state
            self.state = newState
            self.onStateChange?(oldState, newState)
        }
    }
}