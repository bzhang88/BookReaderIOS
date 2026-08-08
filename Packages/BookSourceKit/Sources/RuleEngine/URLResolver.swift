import Foundation

/// Resolves a rule-extracted URL-typed field (`bookUrl`, `coverUrl`, `chapterUrl`, ...), which is
/// frequently relative in real-world HTML (`/book/123`, `../chapter/4`), against the page it was
/// scraped from.
public enum URLResolver {
    public static func resolve(_ raw: String, against baseURL: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        // Already absolute (has a scheme) or a protocol-relative URL.
        if trimmed.contains("://") { return trimmed }
        if trimmed.hasPrefix("//"), let scheme = URL(string: baseURL)?.scheme {
            return "\(scheme):\(trimmed)"
        }

        guard let base = URL(string: baseURL),
              let resolved = URL(string: trimmed, relativeTo: base) else {
            return trimmed
        }
        return resolved.absoluteURL.absoluteString
    }
}
