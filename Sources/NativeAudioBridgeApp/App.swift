import ArgumentParser
import AVFoundation
import Foundation
import NativeAudioBridgeLibrary
import Speech

@main
struct AudioBridgeApp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "native-audio-bridge",
        abstract: "Native macOS voice interaction layer for OpenClaw",
        version: AppVersion.current,
        subcommands: [RunCommand.self, StatusCommand.self, CheckPermissionsCommand.self, ValidateConfigCommand.self],
        defaultSubcommand: RunCommand.self
    )
}

// Shared functionality
extension AudioBridgeApp {
    static func printStartupBanner(config: Configuration, mode: String = "CLI") {
        print("""
        ╔══════════════════════════════════════════════════════════════╗
        ║  Native Audio Bridge v\(AppVersion.current)                                  ║
        ║  Mode: \(mode)                                               ║
        ║  Hot word: \"\(config.hotWord)\"                                           ║
        ║  Webhook: \(config.webhookURL.prefix(40))...  ║
        ║  Output: \(config.outputMode.rawValue)                                          ║
        ║  Log level: \(config.logLevel)                                        ║
        ╚══════════════════════════════════════════════════════════════╝
        """)
    }
    
    static func checkConfigFile(_ path: String?) -> Configuration? {
        let configManager = ConfigurationManager()
        do {
            return try configManager.load(from: path)
        } catch {
            print("Error: Failed to load configuration")
            print("  \(error.localizedDescription)")
            print("")
            print("To get started:")
            print("  1. Create a config file at ~/.config/native-audio-bridge/config.yaml")
            print("  2. Or set environment variables (see README.md)")
            print("  3. Run: native-audio-bridge check-permissions")
            print("  4. Run: native-audio-bridge --help")
            return nil
        }
    }
}
