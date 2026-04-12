import AVFoundation
import Foundation

@main
struct AudioBridgeApp {
    static func main() async {
        let app = AudioBridgeApp()
        await app.run()
    }

    private let audioEngine = AudioEngine()
    private let stateManager = StateManager()
    private let keepAlive = DispatchGroup()

    private func run() async {
        stateManager.setOnStateChange { oldState, newState in
            print("[\(oldState) → \(newState)]")
        }

        audioEngine.setOnAudioBuffer { data in
            let rms = self.calculateRMS(from: data)
            if rms > 0.01 {
                print("Audio sample: \(data.count) bytes, RMS: \(String(format: "%.4f", rms))")
            }
        }

        print("Native Audio Bridge starting...")
        print("Requesting microphone permission...")

        let authorized = await requestMicrophonePermission()
        guard authorized else {
            print("ERROR: Microphone permission denied. Exiting.")
            return
        }

        print("Microphone authorized. Starting audio engine...")

        do {
            try audioEngine.start()
            print("Audio engine running. Sample rate: \(audioEngine.sampleRateValue) Hz")
            print("Listening for hot word... Press Ctrl+C to stop.")
            stateManager.transition(to: .idle)
        } catch {
            print("ERROR: Failed to start audio engine: \(error)")
            return
        }

        signal(SIGINT, SIG_IGN)
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signalSource.setEventHandler { [weak self] in
            print("\nShutting down...")
            self?.audioEngine.stop()
            self?.keepAlive.leave()
        }
        signalSource.resume()

        keepAlive.enter()
        keepAlive.wait()

        print("Audio bridge stopped.")
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func calculateRMS(from data: Data) -> Float {
        guard data.count >= MemoryLayout<Float>.size else { return 0.0 }
        let floatCount = data.count / MemoryLayout<Float>.size
        var sum: Float = 0.0
        data.withUnsafeBytes { rawBuffer in
            let floatPtr = rawBuffer.bindMemory(to: Float.self)
            for i in 0..<floatCount {
                let value = floatPtr[i]
                sum += value * value
            }
        }
        return sqrt(sum / Float(floatCount))
    }
}