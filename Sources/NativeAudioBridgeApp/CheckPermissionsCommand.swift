import ArgumentParser
import AVFoundation
import Foundation

struct CheckPermissionsCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "check-permissions",
        abstract: "Check microphone and speech recognition permissions for the audio bridge"
    )

    func run() async throws {
        print("Checking microphone permission...")
        let microphoneGranted = await requestMicrophonePermission()
        if microphoneGranted {
            print("  Microphone: Authorized")
        } else {
            print("  Microphone: Denied")
        }

        print("\nNext steps if permissions are denied:")
        print("1. Go to System Settings → Privacy & Security → Microphone")
        print("2. Enable permissions and restart the application")
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}