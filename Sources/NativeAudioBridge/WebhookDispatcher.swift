import Foundation

public enum WebhookDispatcherError: LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, body: String)
    case maxRetriesExceeded(lastError: Error)
    case noResponse

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid webhook URL"
        case .httpError(let statusCode, let body):
            return "HTTP error \(statusCode): \(body)"
        case .maxRetriesExceeded(let lastError):
            return "Max retries exceeded: \(lastError.localizedDescription)"
        case .noResponse:
            return "No response received from webhook"
        }
    }
}

public final class WebhookDispatcher {
    private let webhookURL: URL
    private let bearerToken: String
    private let maxRetries: Int
    private let baseDelayMs: Int
    private let session: URLSession
    private let queue = DispatchQueue(label: "com.nativeaudiobridge.webhook", attributes: .concurrent)

    public init(
        webhookURL: String,
        bearerToken: String,
        maxRetries: Int = 3,
        baseDelayMs: Int = 1000,
        session: URLSession? = nil
    ) throws {
        guard let url = URL(string: webhookURL) else {
            throw WebhookDispatcherError.invalidURL
        }
        self.webhookURL = url
        self.bearerToken = bearerToken
        self.maxRetries = maxRetries
        self.baseDelayMs = baseDelayMs
        self.session = session ?? URLSession.shared
    }

    @discardableResult
    public func dispatch(payload: DispatchPayload) async throws -> Bool {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                let success = try await sendRequest(payload: payload)
                if success {
                    Logger.shared.debug("Dispatch succeeded on attempt \(attempt + 1)")
                    return true
                }
            } catch {
                lastError = error
                Logger.shared.error("Attempt \(attempt + 1) failed: \(error.localizedDescription)")}

            if attempt < maxRetries - 1 {
                let delayMs = baseDelayMs * (1 << attempt)
                Logger.shared.debug("Retrying in \(delayMs)ms...")
                try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            }
        }

        throw WebhookDispatcherError.maxRetriesExceeded(lastError: lastError ?? WebhookDispatcherError.noResponse)
    }

    private func sendRequest(payload: DispatchPayload) async throws -> Bool {
        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(payload)

        var request = URLRequest(url: webhookURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebhookDispatcherError.noResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "empty"
            throw WebhookDispatcherError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        return true
    }
}