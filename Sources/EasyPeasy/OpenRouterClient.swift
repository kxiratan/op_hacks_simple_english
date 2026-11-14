import Foundation

/// Errors surfaced to the widget. Each description is one short plain sentence.
enum AIError: LocalizedError {
    case invalidAPIKey
    case outOfCredits
    case permissionDenied
    case rateLimited(freeModel: Bool)
    case serverBusy
    case badRequest(String)
    case pageTooLarge
    case api(String)
    case network(String)
    case refused
    case truncated
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "That API key was not accepted. Check the key in your .env file."
        case .outOfCredits:
            return "Your OpenRouter account is out of credits."
        case .permissionDenied:
            return "This API key is not allowed to use that model."
        case .rateLimited(let freeModel):
            return freeModel
                ? "This free model is busy right now. Try again shortly, or set another OPENROUTER_MODEL in .env."
                : "Too many requests right now. Wait a moment and try again."
        case .serverBusy:
            return "The AI service is busy right now. Try again in a moment."
        case .badRequest(let message):
            return message.isEmpty ? "The request was not accepted." : "The request was not accepted: \(message)"
        case .pageTooLarge:
            return "This page is too large to send. Try a shorter page."
        case .api(let message):
            return message.isEmpty ? "The AI service returned an error. Try again." : "The AI service returned an error: \(message)"
        case .network(let message):
            return message.isEmpty ? "Could not reach the AI service. Check your connection." : "Could not reach the AI service: \(message)"
        case .refused:
            return "The AI declined to respond to this page."
        case .truncated:
            return "The reply was cut off because it got too long."
        case .invalidResponse:
            return "The AI service sent a response that could not be read. Try again."
        }
    }
}

/// Streaming client for OpenRouter's OpenAI-compatible chat completions API.
struct OpenRouterClient {
    /// Used when OPENROUTER_MODEL is not set. Any model slug from openrouter.ai/models works.
    static let defaultModel = "anthropic/claude-opus-5.5"

    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = OpenRouterClient.defaultModel) {
        self.apiKey = apiKey
        self.model = model
    }

    /// Streams the reply's text as it is generated.
    func streamText(system: String, user: String) -> AsyncThrowingStream<String, Error> {
        let apiKey = self.apiKey, model = self.model
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try Self.makeRequest(apiKey: apiKey, model: model, system: system, user: user)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw AIError.invalidResponse
                    }

                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count > 65_536 { break }
                        }
                        throw Self.httpError(status: http.statusCode, body: body, model: model)
                    }

                    // Server-Sent Events: `data: {json}` lines, `: comment` keep-alives,
                    // and a final `data: [DONE]`.
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                        else { continue }

                        // Errors after the stream has started arrive as a chunk with an `error` field.
                        if event["error"] != nil {
                            throw AIError.api(Self.errorMessage(event))
                        }

                        guard let choice = (event["choices"] as? [[String: Any]])?.first else { continue }
                        if let delta = choice["delta"] as? [String: Any],
                           let text = delta["content"] as? String,
                           !text.isEmpty {
                            continuation.yield(text)
                        }
                        switch choice["finish_reason"] as? String {
                        case "length": throw AIError.truncated
                        case "content_filter": throw AIError.refused
                        case "error": throw AIError.api("")
                        default: break
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch let error as URLError {
                    if error.code == .cancelled {
                        continuation.finish(throwing: CancellationError())
                    } else {
                        continuation.finish(throwing: AIError.network(Self.describe(error)))
                    }
                } catch {
                    continuation.finish(throwing: AIError.network(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Request

    private static func makeRequest(apiKey: String, model: String, system: String, user: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // Optional: the app name OpenRouter shows in its dashboard.
        request.setValue("Easy Peasy", forHTTPHeaderField: "X-Title")

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            // The user is waiting on a widget, so keep any model reasoning short.
            "reasoning": ["effort": "low"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Errors

    /// Pulls the message out of `{"error": {"code": ..., "message": "..."}}`.
    private static func errorMessage(_ object: [String: Any]) -> String {
        (object["error"] as? [String: Any])?["message"] as? String ?? ""
    }

    private static func httpError(status: Int, body: Data, model: String) -> AIError {
        let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let message = object.map(errorMessage) ?? ""

        switch status {
        case 401: return .invalidAPIKey
        case 402: return .outOfCredits
        case 403: return .permissionDenied
        case 429: return .rateLimited(freeModel: model.hasSuffix(":free"))
        case 400, 404: return .badRequest(message)
        case 413: return .pageTooLarge
        case 500...599: return .serverBusy
        default: return .api(message)
        }
    }

    private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return "you appear to be offline."
        case .timedOut:
            return "the request timed out."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "the server could not be reached."
        default:
            return error.localizedDescription
        }
    }
}
