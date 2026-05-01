import ArgumentParser
import AVFoundation
import Foundation
import NativeAudioBridgeLibrary
import Speech

struct CheckPermissionsCommand: AsyncParsableCommand {
    
    static let configuration = CommandConfiguration(
        commandName: "check-permissions",
        abstract: "Check microphone and speech recognition permissions for the audio bridge"
    )
    
    func run() async throws {
        print("Checking microphone permission...")
        let microphoneGranted = await requestMicrophonePermission()
        if microphoneGranted {
            print("✅ Microphone: Authorized")
        } else {
            print("❌ Microphone: Denied")
        }
        
        print("Checking speech recognition permission...")
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let speechAuthorized = speechStatus == .authorized
        if speechAuthorized {
            print("✅ Speech Recognition: Authorized")
        } else {
            let statusStr: String
            switch speechStatus {
            case .denied: statusStr = "Denied"
            case .restricted: statusStr = "Restricted"
            case .notDetermined: statusStr = "Not determined (may prompt on first use)"
            default: statusStr = "Unknown"
            }
            print("❌ Speech Recognition: \(statusStr)")
        }
        
        print()
        
        if !microphoneGranted || !speechAuthorized {
            print("Next steps to enable permissions:")
            print("1. Go to System Settings → Privacy & Security → Microphone")
            print("2. Enable access for this application")
            print("3. Go to System Settings → Privacy & Security → Speech Recognition")
            print("4. Enable access for this application")
            print()
        }
        
        print("Note: On macOS, the screen must be unlocked for speech recognition")
        print("to work properly. If the screen is locked, you won't get recognition.")
        
        #if os(macOS)
        print()
        print("Audio device status:")
        do {
            try AudioEngine.checkAudioAvailable()
            print("✅ Audio subsystem available")
        } catch {
            print("❌ Audio issue: \(error.localizedDescription)")
        }
        #endif
    }
    
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}