import Foundation
import BookSourceModel
import RuleEngine
import NetworkClient

/// Fetches and extracts a chapter's readable text, mirroring Legado's `BookContent.analyzeContent`
/// flow. `nextContentUrl` pagination follows the same three-way branch as `TocService` (0/1/2+).
public enum ContentService {
    public static func fetchContent(
        source: BookSource,
        chapter: BookChapter,
        httpClient: HTTPClient
    ) async throws -> ChapterContent {
        let rule = source.ruleContent ?? ContentRule()

        guard let contentRule = rule.content, !contentRule.isEmpty else {
            return ChapterContent(text: chapter.url)
        }
        if chapter.isVolume {
            return ChapterContent(text: chapter.tag ?? chapter.title)
        }

        let firstResponse = try await httpClient.fetch(HTTPRequest(url: chapter.url, headers: source.parsedHeaders()))
        let firstContent = try RuleContent.parse(body: firstResponse.body, baseURL: firstResponse.finalURL)

        var pageTexts = try extractPageText(contentRule: contentRule, content: firstContent)
        var visitedPages: Set<String> = [firstResponse.finalURL]

        let firstNextURLs = try nextURLs(rule: rule, content: firstContent, baseURL: firstResponse.finalURL)

        switch firstNextURLs.count {
        case 0:
            break

        case 1:
            var nextURL: String? = firstNextURLs[0]
            while let url = nextURL, !visitedPages.contains(url) {
                visitedPages.insert(url)
                let response = try await httpClient.fetch(HTTPRequest(url: url, headers: source.parsedHeaders()))
                let content = try RuleContent.parse(body: response.body, baseURL: response.finalURL)
                pageTexts.append(contentsOf: try extractPageText(contentRule: contentRule, content: content))
                nextURL = try nextURLs(rule: rule, content: content, baseURL: response.finalURL).first
            }

        default:
            let urls = firstNextURLs.filter { !visitedPages.contains($0) }
            var pagesByIndex: [Int: [String]] = [:]
            try await withThrowingTaskGroup(of: (Int, [String]).self) { group in
                for (offset, url) in urls.enumerated() {
                    group.addTask {
                        let response = try await httpClient.fetch(HTTPRequest(url: url, headers: source.parsedHeaders()))
                        let content = try RuleContent.parse(body: response.body, baseURL: response.finalURL)
                        return (offset, try extractPageText(contentRule: contentRule, content: content))
                    }
                }
                for try await (offset, texts) in group {
                    pagesByIndex[offset] = texts
                }
            }
            for offset in 0..<urls.count {
                pageTexts.append(contentsOf: pagesByIndex[offset] ?? [])
            }
        }

        var fullText = pageTexts.joined(separator: "\n")

        if let subRule = rule.subContent, !subRule.isEmpty,
           let sub = try? RuleEngine.extractString(subRule, from: firstContent), !sub.isEmpty {
            if sub.lowercased().hasPrefix("http") {
                if let subResponse = try? await httpClient.fetch(HTTPRequest(url: sub, headers: source.parsedHeaders())) {
                    fullText += "\n" + subResponse.body
                }
            } else {
                fullText += "\n" + sub
            }
        }

        if let replacePattern = rule.replaceRegex, !replacePattern.isEmpty {
            fullText = applyReplaceRegex(replacePattern, to: fullText)
        }

        let titleOverride: String? = {
            guard let titleRule = rule.title, !titleRule.isEmpty else { return nil }
            return try? RuleEngine.extractString(titleRule, from: firstContent)
        }()

        return ChapterContent(text: fullText, titleOverride: titleOverride)
    }

    // MARK: - Helpers

    private static func extractPageText(contentRule: String, content: RuleContent) throws -> [String] {
        try RuleEngine.extractStringList(contentRule, from: content)
            .map { looksLikeHTML($0) ? HTMLTextFormatter.plainText(from: $0) : $0 }
    }

    private static func looksLikeHTML(_ text: String) -> Bool {
        text.contains("<") && text.contains(">")
    }

    private static func nextURLs(rule: ContentRule, content: RuleContent, baseURL: String) throws -> [String] {
        guard let nextRule = rule.nextContentUrl, !nextRule.isEmpty else { return [] }
        return try RuleEngine.extractStringList(nextRule, from: content)
            .map { URLResolver.resolve($0, against: baseURL) }
    }

    /// `replaceRegex`'s real semantics (verified against `BookContent.kt`): it's evaluated through
    /// the *same* rule pipeline as every other field (`analyzeRule.getString(replaceRegex, ...)`),
    /// which is why real-world values are conventionally written with a leading `##` — an empty
    /// selector followed by the regex suffix, e.g. `"##广告文字.*"` or `"##pattern##replacement"`.
    /// The regex runs once against the whole (line-trimmed) chapter text, then every resulting
    /// line — including blank ones — gets a full-width double-space indent.
    private static func applyReplaceRegex(_ raw: String, to text: String) -> String {
        let (_, suffix) = RegexSuffixParser.extract(from: raw)
        guard let suffix else { return text }

        let trimmedJoined = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")

        let purified = RegexSuffixParser.apply(suffix, to: trimmedJoined)

        return purified
            .components(separatedBy: "\n")
            .map { "\u{3000}\u{3000}" + $0 }
            .joined(separator: "\n")
    }
}
