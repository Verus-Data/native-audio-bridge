import Foundation

public enum BridgeState {
    case idle
    case listening
    case processing
    case dispatching
}

public final class StateManager {
    public private(set) var state: BridgeState = .idle
    private let stateQueue = DispatchQueue(label: "com.nativeaudiobridge.state", attributes: .concurrent)
    private var onStateChange: ((BridgeState, BridgeState) -> Void)?

    public func setOnStateChange(_ handler: @escaping (BridgeState, BridgeState) -> Void) {
        onStateChange = handler
    }

    public func transition(to newState: BridgeState) {
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            let oldState = self.state
            self.state = newState
            self.onStateChange?(oldState, newState)
        }
    }
}