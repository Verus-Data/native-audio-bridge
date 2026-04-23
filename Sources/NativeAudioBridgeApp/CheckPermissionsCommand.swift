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
        let speechGranted = await withCheckedContinuation { continuation in
            Task {
                AVAudioSession.sharedInstance().requestPermission { permitted in
                    continuation.resume(returning: permitted)
                }
            }
        }
        
        if speechGranted {
            print("✅ Speech Recognition: Authorized")
        } else {
            print("❌ Speech Recognition: Denied")
        }
        
        print()
        print("Next steps if permissions are denied:")
        print("1. Go to System Preferences → Privacy & Security → Microphone")
        print("2. Check 'Voice Control' or 'Listening' for our app")
        print("3. Enable permissions and restart the application")
        
        print()
        print("Note: On macOS, the screen must be unlocked for speech recognition")
        print("to work properly. If the screen is locked, you won't get recognition.")
    }
    
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}