import ArgumentParser
import Foundation
import NativeAudioBridgeLibrary

struct ValidateConfigCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "validate-config",
        abstract: "Validate the configuration file and environment variables"
    )

    @Option(name: .long, help: "Path to configuration file")
    var configPath: String?

    func run() throws {
        let configManager = ConfigurationManager()
        do {
            let config = try configManager.load(from: configPath)
            print("Configuration is valid")
            print("  Hot word: \(config.hotWord)")
            print("  Silence timeout: \(config.silenceTimeoutMs)ms")
            print("  Output mode: \(config.outputMode.description)")
            print("  Webhook URL: \(config.webhookURL.prefix(40))...")
            print("  Log level: \(config.logLevel)")
        } catch {
            print("Configuration error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}