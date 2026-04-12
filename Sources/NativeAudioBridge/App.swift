import AVFoundation
import Foundation

@main
struct AudioBridgeApp {
    static func main() async {
        let audioEngine = AudioEngine()
        let stateManager = StateManager()
        let keepAlive = DispatchGroup()

        stateManager.setOnStateChange { oldState, newState in
            print("[\(oldState) → \(newState)]")
        }

        audioEngine.setOnAudioBuffer { data in
            let rms = Self.calculateRMS(from: data)
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
        signalSource.setEventHandler {
            print("\nShutting down...")
            audioEngine.stop()
            keepAlive.leave()
        }
        signalSource.resume()

        keepAlive.enter()
        _ = keepAlive.wait(timeout: .distantFuture)

        print("Audio bridge stopped.")
    }

    private static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func calculateRMS(from data: Data) -> Float {
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