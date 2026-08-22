import Foundation

/// A user-configured cloud text-to-speech engine -- confirmed against Legado_Max's real `HttpTTS`
/// entity that this is a name plus a URL template, structurally the same shape as `WebSearchEngine`
/// (a plain `{{text}}` placeholder substitution, not a scraping rule DSL) rather than the debug
/// console/import-dialog machinery around it, which this app doesn't replicate.
public struct HttpTTSEngine: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// `{{text}}` is substituted with the percent-encoded paragraph text; fetching this URL is
    /// expected to return audio bytes directly (the common shape for simple HTTP TTS APIs).
    public var urlTemplate: String
    /// A JSON-object-shaped string (e.g. `{"Referer": "..."}`), same convention as `BookSource
    /// .header` -- some TTS APIs 403 a plain unauthenticated request the same way book sources do.
    /// `Optional`, not defaulted to an empty string, so this decodes safely from any
    /// `http_tts_engines.json` written before this field existed.
    public var header: String?

    public init(id: String = UUID().uuidString, name: String, urlTemplate: String, header: String? = nil) {
        self.id = id
        self.name = name
        self.urlTemplate = urlTemplate
        self.header = header
    }

    public func url(forText text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let urlString = urlTemplate.replacingOccurrences(of: "{{text}}", with: encoded)
        return URL(string: urlString)
    }

    /// Same parsing convention as `BookSource.parsedHeaders()`: malformed or missing header JSON
    /// degrades to just the default User-Agent rather than failing the request outright.
    public func parsedHeaders() -> [String: String] {
        var result: [String: String] = ["User-Agent": BookSource.defaultUserAgent]
        guard let header, let data = header.data(using: .utf8) else { return result }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return result }
        for (key, value) in object {
            if let stringValue = value as? String {
                result[key] = stringValue
            } else if let convertible = value as? CustomStringConvertible {
                result[key] = convertible.description
            }
        }
        return result
    }
}
