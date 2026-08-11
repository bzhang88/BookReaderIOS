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

    public init(id: String = UUID().uuidString, name: String, urlTemplate: String) {
        self.id = id
        self.name = name
        self.urlTemplate = urlTemplate
    }

    public func url(forText text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let urlString = urlTemplate.replacingOccurrences(of: "{{text}}", with: encoded)
        return URL(string: urlString)
    }
}
