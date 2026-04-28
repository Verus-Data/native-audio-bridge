import AVFoundation
import Foundation

/// Errors that can occur during Telegram audio export operations.
public enum TelegramExporterError: LocalizedError {
    case notConfigured
    case invalidBotToken
    case invalidChatId
    case audioConversionFailed(String)
    case httpError(statusCode: Int, body: String)
    case maxRetriesExceeded(lastError: Error)
    case noResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Telegram exporter is not configured (missing bot token or chat ID)"
        case .invalidBotToken:
            return "Invalid Telegram bot token"
        case .invalidChatId:
            return "Invalid Telegram chat ID"
        case .audioConversionFailed(let reason):
            return "Audio conversion failed: \(reason)"
        case .httpError(let statusCode, let body):
            return "Telegram API HTTP error \(statusCode): \(body)"
        case .maxRetriesExceeded(let lastError):
            return "Max retries exceeded: \(lastError.localizedDescription)"
        case .noResponse:
            return "No response received from Telegram API"
        }
    }
}

/// Exports captured audio buffers as Telegram voice messages.
///
/// Uses the Telegram Bot API `sendVoice` endpoint to deliver audio from the
/// audio bridge directly to a configured Telegram chat. Audio is converted
/// from PCM float32 to a WAV container (Telegram transcodes server-side to OGG/Opus).
///
/// Configuration:
/// - `telegram_bot_token`: Bot token from @BotFather
/// - `telegram_chat_id`: Target chat ID (numeric string or @channel)
/// - Environment vars: `NATIVE_AUDIO_BRIDGE_TELEGRAM_BOT_TOKEN`, `NATIVE_AUDIO_BRIDGE_TELEGRAM_CHAT_ID`
public final class TelegramAudioExporter {
    private let botToken: String
    private let chatId: String
    private let maxRetries: Int
    private let baseDelayMs: Int
    private let session: URLSession
    private let logger = AppLogger.shared

    /// Base URL for Telegram Bot API
    private var apiBaseURL: String {
        "https://api.telegram.org/bot\(botToken)"
    }

    /// Initialize with configuration
    public init(
        botToken: String,
        chatId: String,
        maxRetries: Int = 3,
        baseDelayMs: Int = 1000,
        session: URLSession? = nil
    ) throws {
        guard !botToken.isEmpty else {
            throw TelegramExporterError.invalidBotToken
        }
        guard !chatId.isEmpty else {
            throw TelegramExporterError.invalidChatId
        }
        self.botToken = botToken
        self.chatId = chatId
        self.maxRetries = maxRetries
        self.baseDelayMs = baseDelayMs
        self.session = session ?? URLSession.shared
    }

    /// Create from Configuration struct — convenience initializer
    public convenience init(config: Configuration) throws {
        try self.init(
            botToken: config.telegramBotToken,
            chatId: config.telegramChatId
        )
    }

    // MARK: - Audio Conversion

    /// Convert PCM float32 audio buffers to WAV format data.
    ///
    /// Telegram accepts various audio formats and transcodes server-side to OGG/Opus
    /// for voice messages. We wrap PCM float32 data in a WAV container which
    /// Telegram can process.
    ///
    /// - Parameter buffers: Array of PCM float32 audio data chunks
    /// - Parameter sampleRate: Sample rate of the audio (default: 16000)
    /// - Returns: WAV encoded audio data
    public func convertToWAV(buffers: [Data], sampleRate: Double = 16000) throws -> Data {
        guard !buffers.isEmpty else {
            throw TelegramExporterError.audioConversionFailed("No audio buffers to convert")
        }

        let pcmData = buffers.reduce(Data()) { $0 + $1 }
        return createWAVData(pcmData: pcmData, sampleRate: sampleRate, channels: 1, bitsPerSample: 32)
    }

    /// Create a WAV file header + data from raw PCM float32 samples
    private func createWAVData(pcmData: Data, sampleRate: Double, channels: Int, bitsPerSample: Int) -> Data {
        let dataSize = UInt32(pcmData.count)
        let fileSize = 36 + dataSize
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = UInt16(channels * (bitsPerSample / 8))

        var header = Data()
        // RIFF header
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        header.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        // fmt chunk
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(3).littleEndian) { Array($0) }) // IEEE float
        header.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })
        // data chunk
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        header.append(pcmData)
        return header
    }

    // MARK: - Export Methods

    /// Export audio buffers as a Telegram voice message.
    public func exportVoice(
        buffers: [Data],
        sampleRate: Double = 16000,
        caption: String? = nil
    ) async throws {
        let audioData = try convertToWAV(buffers: buffers, sampleRate: sampleRate)
        try await sendVoice(audioData: audioData, caption: caption)
    }

    /// Export command text as a regular Telegram text message.
    public func exportText(_ text: String) async throws {
        try await sendMessage(text: text)
    }

    // MARK: - Telegram API

    /// Send a voice message via Telegram Bot API using multipart/form-data.
    private func sendVoice(audioData: Data, caption: String? = nil) async throws {
        let urlString = "\(apiBaseURL)/sendVoice"
        guard let url = URL(string: urlString) else {
            throw TelegramExporterError.invalidBotToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // chat_id field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(chatId)\r\n".data(using: .utf8)!)

        // voice file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"voice\"; filename=\"voice.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // caption (optional)
        if let caption, !caption.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"caption\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(caption)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw TelegramExporterError.noResponse
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    let body = String(data: data, encoding: .utf8) ?? "empty"
                    throw TelegramExporterError.httpError(
                        statusCode: httpResponse.statusCode,
                        body: body
                    )
                }
                logger.info("Telegram voice message sent successfully (attempt \(attempt + 1))")
                return
            } catch {
                lastError = error
                logger.error("Telegram send attempt \(attempt + 1) failed: \(error.localizedDescription)")
                if attempt < maxRetries - 1 {
                    let delayMs = baseDelayMs * (1 << attempt)
                    try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                }
            }
        }
        throw TelegramExporterError.maxRetriesExceeded(
            lastError: lastError ?? TelegramExporterError.noResponse
        )
    }

    /// Send a text message via Telegram Bot API.
    private func sendMessage(text: String) async throws {
        let urlString = "\(apiBaseURL)/sendMessage"
        guard let url = URL(string: urlString) else {
            throw TelegramExporterError.invalidBotToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = [
            "chat_id": chatId,
            "text": text,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw TelegramExporterError.noResponse
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    let body = String(data: data, encoding: .utf8) ?? "empty"
                    throw TelegramExporterError.httpError(
                        statusCode: httpResponse.statusCode,
                        body: body
                    )
                }
                logger.info("Telegram text message sent successfully (attempt \(attempt + 1))")
                return
            } catch {
                lastError = error
                logger.error("Telegram send attempt \(attempt + 1) failed: \(error.localizedDescription)")
                if attempt < maxRetries - 1 {
                    let delayMs = baseDelayMs * (1 << attempt)
                    try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                }
            }
        }
        throw TelegramExporterError.maxRetriesExceeded(
            lastError: lastError ?? TelegramExporterError.noResponse
        )
    }
}