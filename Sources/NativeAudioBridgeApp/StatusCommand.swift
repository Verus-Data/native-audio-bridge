import ArgumentParser
import Foundation
import NativeAudioBridgeLibrary

struct StatusCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the current status and configuration of the audio bridge"
    )

    func run() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = home + "/.config/native-audio-bridge/config.yaml"

        let configManager = ConfigurationManager()
        guard let config = try? configManager.load(from: configPath) else {
            print("No config file found at ~/.config/native-audio-bridge/config.yaml")
            return
        }

        print("Audio Bridge Status")
        print(String(repeating: "=", count: 30))
        print("  Mode: CLI")
        print("  Hot word: \"\(config.hotWord)\"")
        print("  Webhook URL: \(config.webhookURL.prefix(60))...")
        print("  Output mode: \(config.outputMode.description)")
        print("  Log level: \(config.logLevel)")

        // Check if daemon is running
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/pgrep")
        task.arguments = ["-f", "NativeAudioBridge"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                print("\nAudio bridge daemon is running")
            } else {
                print("\nAudio bridge daemon is NOT running")
            }
        } catch {
            print("\nCould not check daemon status")
        }
    }
}