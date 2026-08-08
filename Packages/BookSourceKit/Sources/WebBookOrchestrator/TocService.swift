import Foundation
import BookSourceModel
import RuleEngine
import NetworkClient

/// Fetches and merges a book's table of contents, mirroring Legado's `BookChapterList` flow.
///
/// `nextTocUrl` pagination is a genuine three-way branch in the real implementation, not a
/// design choice: zero next-page URLs means the list is done; exactly one means "follow this
/// single link repeatedly" (serial, since each page usually only reveals the *next* link once
/// fetched); two or more means the source handed back an explicit, complete list of page URLs
/// up front, safe to fetch concurrently. Supporting only one shape under-fetches or infinite-loops
/// on sources built the other way.
public enum TocService {
    public static func fetchChapterList(
        source: BookSource,
        tocURL: String,
        httpClient: HTTPClient
    ) async throws -> [BookChapter] {
        let rule = source.ruleToc ?? TocRule()

        if let preUpdateJs = rule.preUpdateJs, !preUpdateJs.isEmpty {
            throw RuleEngineError.notYetImplemented("ruleToc.preUpdateJs (planned alongside Phase 2 JS work)")
        }

        let (chapterListRule, reversed) = ListRulePrefix.strip(rule.chapterList ?? "")
        guard !chapterListRule.isEmpty else { return [] }

        let firstResponse = try await httpClient.fetch(HTTPRequest(url: tocURL, headers: source.parsedHeaders()))
        let firstContent = try RuleContent.parse(body: firstResponse.body, baseURL: firstResponse.finalURL)
        let firstPage = try extractPage(rule: rule, chapterListRule: chapterListRule, content: firstContent, baseURL: firstResponse.finalURL)

        var chapters: [BookChapter] = []
        var seenURLs = Set<String>()
        appendUnique(firstPage.chapters, to: &chapters, seen: &seenURLs)

        var visitedPages: Set<String> = [firstResponse.finalURL]

        switch firstPage.nextURLs.count {
        case 0:
            break

        case 1:
            var nextURL: String? = firstPage.nextURLs[0]
            while let url = nextURL, !visitedPages.contains(url) {
                visitedPages.insert(url)
                let response = try await httpClient.fetch(HTTPRequest(url: url, headers: source.parsedHeaders()))
                let content = try RuleContent.parse(body: response.body, baseURL: response.finalURL)
                let page = try extractPage(rule: rule, chapterListRule: chapterListRule, content: content, baseURL: response.finalURL)
                appendUnique(page.chapters, to: &chapters, seen: &seenURLs)
                nextURL = page.nextURLs.first
            }

        default:
            let urls = firstPage.nextURLs.filter { !visitedPages.contains($0) }
            var pagesByIndex: [Int: [BookChapter]] = [:]
            try await withThrowingTaskGroup(of: (Int, [BookChapter]).self) { group in
                for (offset, url) in urls.enumerated() {
                    group.addTask {
                        let response = try await httpClient.fetch(HTTPRequest(url: url, headers: source.parsedHeaders()))
                        let content = try RuleContent.parse(body: response.body, baseURL: response.finalURL)
                        let page = try extractPage(rule: rule, chapterListRule: chapterListRule, content: content, baseURL: response.finalURL)
                        return (offset, page.chapters)
                    }
                }
                for try await (offset, pageChapters) in group {
                    pagesByIndex[offset] = pageChapters
                }
            }
            for offset in 0..<urls.count {
                appendUnique(pagesByIndex[offset] ?? [], to: &chapters, seen: &seenURLs)
            }
        }

        if reversed { chapters.reverse() }
        return chapters.enumerated().map { $0.element.reindexed($0.offset) }
    }

    // MARK: - Single-page extraction

    private struct Page {
        var chapters: [BookChapter]
        var nextURLs: [String]
    }

    private static func extractPage(
        rule: TocRule, chapterListRule: String, content: RuleContent, baseURL: String
    ) throws -> Page {
        let items = try RuleEngine.extractItems(chapterListRule, from: content)

        var chapters: [BookChapter] = []
        for item in items {
            let title = try RuleEngine.extractString(rule.chapterName ?? "", from: item) ?? ""
            guard let rawURL = try RuleEngine.extractString(rule.chapterUrl ?? "", from: item), !rawURL.isEmpty else {
                continue
            }
            let url = URLResolver.resolve(rawURL, against: baseURL)
            let tag = try? RuleEngine.extractString(rule.updateTime ?? "", from: item)
            let isVolume = (try? RuleEngine.extractString(rule.isVolume ?? "", from: item)).isTrueFlag()
            let isVip = (try? RuleEngine.extractString(rule.isVip ?? "", from: item)).isTrueFlag()
            let isPay = (try? RuleEngine.extractString(rule.isPay ?? "", from: item)).isTrueFlag()
            chapters.append(BookChapter(
                index: chapters.count, title: title, url: url,
                isVolume: isVolume, isVip: isVip, isPay: isPay, tag: tag
            ))
        }

        var nextURLs: [String] = []
        if let nextRule = rule.nextTocUrl, !nextRule.isEmpty {
            nextURLs = try RuleEngine.extractStringList(nextRule, from: content)
                .map { URLResolver.resolve($0, against: baseURL) }
        }

        return Page(chapters: chapters, nextURLs: nextURLs)
    }

    private static func appendUnique(_ newChapters: [BookChapter], to chapters: inout [BookChapter], seen: inout Set<String>) {
        for chapter in newChapters where !seen.contains(chapter.url) {
            seen.insert(chapter.url)
            chapters.append(chapter)
        }
    }
}
