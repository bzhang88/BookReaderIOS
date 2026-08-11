import Foundation
import BookSourceModel
import NetworkClient

public enum AIChatError: Error, Equatable {
    /// A non-2xx HTTP response -- `message` is the provider's own error text when the response body
    /// parses as the common `{"error": {"message": ...}}` shape, otherwise a truncated raw body so
    /// there's still something actionable to show rather than just a bare status code.
    case httpError(statusCode: Int, message: String)
    /// A 2xx response whose body doesn't parse as the OpenAI-compatible `choices[0].message.content`
    /// shape this app targets -- most non-OpenAI-compatible providers will end up here rather than
    /// silently returning something misleading.
    case invalidResponse
}

/// Calls a configured `AIProvider`'s chat-completions endpoint -- the one piece of AI plumbing this
/// app actually exercises end-to-end (see `AIProvider`'s doc comment: everything before this was
/// configuration only, nothing called out to a real API). Targets the OpenAI-compatible
/// `/chat/completions` shape specifically since that's the lingua franca essentially every hosted
/// and self-hosted LLM gateway (OpenAI itself, most local servers, most third-party aggregators)
/// speaks, rather than trying to support every provider's own bespoke API shape.
public enum AIChatService {
    public static func complete(
        provider: AIProvider, apiKey: String, prompt: String, httpClient: any HTTPClient
    ) async throws -> String {
        let url = chatCompletionsURL(baseURL: provider.baseURL)
        let payload: [String: Any] = [
            "model": provider.modelName,
            "messages": [["role": "user", "content": prompt]]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = HTTPRequest(
            url: url,
            method: "POST",
            headers: [
                "Content-Type": "application/json",
                "Authorization": "Bearer \(apiKey)"
            ],
            body: body,
            timeout: 60
        )
        let response = try await httpClient.fetch(request)
        guard (200...299).contains(response.statusCode) else {
            throw AIChatError.httpError(statusCode: response.statusCode, message: errorMessage(from: response.body))
        }
        return try messageContent(from: response.body)
    }

    /// `baseURL` is stored as whatever the user typed (with or without a trailing slash, with or
    /// without the `/chat/completions` suffix already on it) -- normalizes both so either form works.
    static func chatCompletionsURL(baseURL: String) -> String {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if trimmed.hasSuffix("/chat/completions") {
            return trimmed
        }
        return trimmed + "/chat/completions"
    }

    static func messageContent(from jsonBody: String) throws -> String {
        guard let data = jsonBody.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty else {
            throw AIChatError.invalidResponse
        }
        return content
    }

    static func errorMessage(from jsonBody: String) -> String {
        if let data = jsonBody.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }
        return String(jsonBody.prefix(200))
    }
}
