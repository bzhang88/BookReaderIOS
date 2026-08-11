import Foundation
import NetworkClient
import Persistence

/// Shared app-wide dependencies (persistence stores, network client), created once and injected
/// into the view hierarchy via `.environmentObject`.
@MainActor
final class AppEnvironment: ObservableObject {
    let bookSourceStore: BookSourceStore
    let shelfStore: ShelfStore
    let replaceRuleStore: ReplaceRuleStore
    let rssSourceStore: RssSourceStore
    let aiProviderStore: AIProviderStore
    let highlightRuleStore: HighlightRuleStore
    let tagGroupRuleStore: TagGroupRuleStore
    let localBookStore: LocalBookStore
    let searchHistoryStore: SearchHistoryStore
    let chapterCacheStore: ChapterCacheStore
    let httpClient: any HTTPClient

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        bookSourceStore = BookSourceStore(fileURL: appSupport.appendingPathComponent("book_sources.json"))
        shelfStore = ShelfStore(fileURL: appSupport.appendingPathComponent("shelf.json"))
        replaceRuleStore = ReplaceRuleStore(fileURL: appSupport.appendingPathComponent("replace_rules.json"))
        rssSourceStore = RssSourceStore(fileURL: appSupport.appendingPathComponent("rss_sources.json"))
        aiProviderStore = AIProviderStore(fileURL: appSupport.appendingPathComponent("ai_providers.json"))
        highlightRuleStore = HighlightRuleStore(fileURL: appSupport.appendingPathComponent("highlight_rules.json"))
        tagGroupRuleStore = TagGroupRuleStore(fileURL: appSupport.appendingPathComponent("tag_group_rules.json"))
        localBookStore = LocalBookStore(fileURL: appSupport.appendingPathComponent("local_books.json"))
        searchHistoryStore = SearchHistoryStore(fileURL: appSupport.appendingPathComponent("search_history.json"))
        chapterCacheStore = ChapterCacheStore(directory: appSupport.appendingPathComponent("chapter_cache", isDirectory: true))
        httpClient = URLSessionHTTPClient()
    }
}
