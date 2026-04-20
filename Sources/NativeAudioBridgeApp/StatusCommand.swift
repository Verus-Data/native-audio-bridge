struct StatusCommand: ParsableCommand {
    
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the current status and configuration of the audio bridge"
    )
    
    func run() throws {
        let configPath = ~/.config/native-audio-bridge/config.yaml
        guard let configPath else {
            print("No config file found at ~/.config/native-audio-bridge/config.yaml")
            exit(1)
        }
        
        let configManager = ConfigurationManager()
        let config = try configManager.load(from: configPath)
        
        print("🔊 Audio Bridge Status")
        print("=" * 30)
        print("🔹 Mode: CLI")
        print("🔹 Hot word: \"\(config.hotWord)\"")
        print("🔹 Webhook URL: \(config.webhookURL.prefix(60))... ")
        print("🔹 Output mode: \(config.outputMode.rawValue)")
        print("🔹 Log level: \(config.logLevel)")
        print("🔹 Instances: 1 daemon running")
        
        // Check permissions
        print("\n🛡️  Permissions:")
        Task {
            let micGranted = await requestMicrophonePermission()
            if micGranted {
                print("   • Microphone: ✅ Authorized")
            } else {
                print("   • Microphone: ❌ Denied")
            }
            
            // Add speech recognition permission check
            let speechGranted = await withCheckedContinuation { continuation in
                Task {
                    let granted = await withCheckedContinuation { finalContinuation in
                        Task {
                            AVAudioSession.sharedInstance().requestPermission { permitted in
                                continuation.resume(returning: permitted)
                            }
                        }
                    }
                    guard granted else {
                        print("   • Speech Recognition: ❌ Denied")
                    }
                    continuation.resume(returning: true)
                }
            }
            
            if speechGranted {
                print("   • Speech Recognition: ✅ Authorized")
            } else {
                print("   • Speech Recognition: ❌ Denied")
            }
        }
        
        print("\n📁 Config location: \(configPath)")
        
        // Check running process
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-ef", "|", "grep", "NativeAudioBridge", "|", "grep", "-v", "grep"]
        let pipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errPipe
        
        try? task.run()
        let output = try? pipe.fileHandleForReading.readData().compile()
        let errorOutput = try? errPipe.fileHandleForReading.readData().compile()
        
        if let output, output.count > 0 {
            print("🟢 Audio bridge daemon is running (PID: $(ps aux | grep NativeAudioBridge | grep -v grep | awk '{print $2}'))")
        } else {
            print("🔴 Audio bridge daemon is NOT running")
        }
    }
    
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    private func checkPermissions() -> Bool {
        // Implementation would go here
        return true
    }
}