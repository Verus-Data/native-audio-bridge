import ArgumentParser
import AVFoundation
import Foundation
import NativeAudioBridgeLibrary

struct StatusCommand: ParsableCommand {
    
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the current status and configuration of the audio bridge"
    )

    @Option(name: [.customLong("config"), .customShort("c")],
            help: "Path to YAML configuration file")
    var configPath: String?
    
    func run() throws {
        let defaultConfigPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/native-audio-bridge/config.yaml").path
        let resolvedPath = configPath ?? defaultConfigPath
        
        let configManager = ConfigurationManager()
        let config: Configuration
        do {
            config = try configManager.load(from: resolvedPath)
        } catch {
            print("❌ Failed to load configuration: \(error.localizedDescription)")
            print("   Config path: \(resolvedPath)")
            throw ExitCode.failure
        }
        
        print("🔊 Audio Bridge Status")
        print(String(repeating: "=", count: 30))
        print("🔹 Mode: CLI")
        print("🔹 Hot word: \"\(config.hotWord)\"")
        print("🔹 Webhook URL: \(config.webhookURL.prefix(60))...")
        print("🔹 Output mode: \(config.outputMode.description)")
        print("🔹 Log level: \(config.logLevel)")
        
        if let device = config.inputDevice {
            print("🔹 Input device: \(device)")
        }
        
        #if os(macOS)
        print("")
        print("🎤 Audio Devices:")
        let devices = AudioEngine.listAudioDevices()
        if devices.isEmpty {
            print("   No input devices found")
        } else {
            for device in devices {
                let marker = device.isDefault ? " (default)" : ""
                print("   [\(device.id)] \(device.name)\(marker)")
            }
        }
        #endif
        
        print("\n📁 Config location: \(resolvedPath)")
    }
}