import Foundation
import BookSourceModel
import RuleEngine
import NetworkClient

/// Fetches and extracts a chapter's readable text, mirroring Legado's `BookContent.analyzeContent`
/// flow. `nextContentUrl` pagination follows the same three-way branch as `TocService` (0/1/2+).
public enum ContentService {
    /// - Parameter nextChapterUrl: The URL of the chapter *after* `chapter` in the book's own
    ///   table of contents, if known -- passed through so the `nextContentUrl` pagination loop below
    ///   can tell "this source's in-chapter-page-turn link" apart from "this source reused/mislabeled
    ///   its actual next-*chapter* link as the page-turn rule." Both read as the exact same thing to
    ///   `nextContentUrl` (a link to follow, `RuleEngine`-extracted the same way either way); real
    ///   book-source data (confirmed against a live-imported source in this app's own library, whose
    ///   `nextContentUrl` rule literally reads `text.下一章@href` -- "next *chapter*") shows sources
    ///   do this. Legado guards against exactly this in `LazyContentManager`/`BookContent`
    ///   (`nextUrl == nextChapterUrl` stops pagination rather than following it) -- without an
    ///   equivalent check here, a source like that would keep chaining through every remaining
    ///   chapter's content, appending the entire rest of the book into what's nominally one chapter.
    ///   `nil` (the default) skips the check for callers that don't have a chapter list in hand
    ///   (single-chapter previews, debug/validation tooling) -- those already can't reach this failure
    ///   mode by construction, since nothing about a lone chapter fetch even implies "next chapter."
    public static func fetchContent(
        source: BookSource,
        chapter: BookChapter,
        httpClient: HTTPClient,
        nextChapterUrl: String? = nil
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
            while let url = nextURL, !visitedPages.contains(url), url != nextChapterUrl {
                visitedPages.insert(url)
                let response = try await httpClient.fetch(HTTPRequest(url: url, headers: source.parsedHeaders()))
                let content = try RuleContent.parse(body: response.body, baseURL: response.finalURL)
                pageTexts.append(contentsOf: try extractPageText(contentRule: contentRule, content: content))
                nextURL = try nextURLs(rule: rule, content: content, baseURL: response.finalURL).first
            }

        default:
            let urls = firstNextURLs.filter { !visitedPages.contains($0) && $0 != nextChapterUrl }
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
