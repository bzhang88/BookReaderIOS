import Foundation
import NetworkClient
import Persistence

/// Shared app-wide dependencies (persistence stores, network client), created once and injected
/// into the view hierarchy via `.environmentObject`.
@MainActor
final class AppEnvironment: ObservableObject {
    let bookSourceStore: BookSourceStore
    let bookSourceTrashStore: BookSourceTrashStore
    let bookSourceSubscriptionStore: BookSourceSubscriptionStore
    let shelfStore: ShelfStore
    let replaceRuleStore: ReplaceRuleStore
    let rssSourceStore: RssSourceStore
    let aiProviderStore: AIProviderStore
    let highlightRuleStore: HighlightRuleStore
    let tagGroupRuleStore: TagGroupRuleStore
    let localBookStore: LocalBookStore
    let searchHistoryStore: SearchHistoryStore
    let chapterCacheStore: ChapterCacheStore
    let bookmarkStore: BookmarkStore
    let txtSplitRuleStore: TxtSplitRuleStore
    let loginCookieStore: LoginCookieStore
    let shelfGroupStore: ShelfGroupStore
    let dictRuleStore: DictRuleStore
    let webSearchEngineStore: WebSearchEngineStore
    let httpClient: any HTTPClient
    #if canImport(Network)
    let lanWebServer: LANWebServer
    #endif

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        bookSourceStore = BookSourceStore(fileURL: appSupport.appendingPathComponent("book_sources.json"))
        bookSourceTrashStore = BookSourceTrashStore(fileURL: appSupport.appendingPathComponent("book_source_trash.json"))
        bookSourceSubscriptionStore = BookSourceSubscriptionStore(fileURL: appSupport.appendingPathComponent("book_source_subscriptions.json"))
        shelfStore = ShelfStore(fileURL: appSupport.appendingPathComponent("shelf.json"))
        replaceRuleStore = ReplaceRuleStore(fileURL: appSupport.appendingPathComponent("replace_rules.json"))
        rssSourceStore = RssSourceStore(fileURL: appSupport.appendingPathComponent("rss_sources.json"))
        aiProviderStore = AIProviderStore(fileURL: appSupport.appendingPathComponent("ai_providers.json"))
        highlightRuleStore = HighlightRuleStore(fileURL: appSupport.appendingPathComponent("highlight_rules.json"))
        tagGroupRuleStore = TagGroupRuleStore(fileURL: appSupport.appendingPathComponent("tag_group_rules.json"))
        localBookStore = LocalBookStore(fileURL: appSupport.appendingPathComponent("local_books.json"))
        searchHistoryStore = SearchHistoryStore(fileURL: appSupport.appendingPathComponent("search_history.json"))
        chapterCacheStore = ChapterCacheStore(directory: appSupport.appendingPathComponent("chapter_cache", isDirectory: true))
        bookmarkStore = BookmarkStore(fileURL: appSupport.appendingPathComponent("bookmarks.json"))
        txtSplitRuleStore = TxtSplitRuleStore(fileURL: appSupport.appendingPathComponent("txt_split_rules.json"))
        loginCookieStore = LoginCookieStore(fileURL: appSupport.appendingPathComponent("login_cookies.json"))
        shelfGroupStore = ShelfGroupStore(fileURL: appSupport.appendingPathComponent("shelf_groups.json"))
        dictRuleStore = DictRuleStore(fileURL: appSupport.appendingPathComponent("dict_rules.json"))
        webSearchEngineStore = WebSearchEngineStore(fileURL: appSupport.appendingPathComponent("web_search_engines.json"))
        httpClient = URLSessionHTTPClient()
        #if canImport(Network)
        lanWebServer = LANWebServer(
            shelfStore: shelfStore, bookSourceStore: bookSourceStore,
            chapterCacheStore: chapterCacheStore, httpClient: httpClient
        )
        #endif

        let cookieStore = loginCookieStore
        Task { await Self.reinjectSavedCookies(from: cookieStore) }
    }

    /// A WebView's cookie jar and `URLSession`'s `HTTPCookieStorage.shared` are separate stores on
    /// iOS -- cookies captured during a book-source login (see `SourceLoginView`) get copied into
    /// the shared storage right after capture, but that copy only lives in memory for the current
    /// process. This repopulates it from disk once at launch so a login from a previous session
    /// keeps working without the user having to log in again every time the app restarts.
    private static func reinjectSavedCookies(from store: LoginCookieStore) async {
        guard let all = try? await store.allCookies() else { return }
        for (_, cookies) in all {
            for saved in cookies {
                var properties: [HTTPCookiePropertyKey: Any] = [
                    .name: saved.name,
                    .value: saved.value,
                    .domain: saved.domain,
                    .path: saved.path,
                    .secure: saved.isSecure
                ]
                if let expiresAt = saved.expiresAt {
                    properties[.expires] = expiresAt
                }
                if let cookie = HTTPCookie(properties: properties) {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
            }
        }
    }
}
