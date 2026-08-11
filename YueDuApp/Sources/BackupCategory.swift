import Foundation

/// One selectable slice of what "备份"/"恢复" can include -- lets the user opt out of categories
/// they don't care about (or that are large/sensitive) instead of every backup always being
/// everything. Each case maps to exactly one JSON file on the WebDAV server, matching this app's
/// existing one-store-one-file convention.
enum BackupCategory: String, CaseIterable, Identifiable {
    case bookSources, shelf, replaceRules, highlightRules, tagGroupRules, txtSplitRules, rssSources
    case bookmarks, localBooks, aiProviders

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bookSources: return "书源"
        case .shelf: return "书架"
        case .replaceRules: return "净化规则"
        case .highlightRules: return "高亮规则"
        case .tagGroupRules: return "分组规则"
        case .txtSplitRules: return "TXT 分章规则"
        case .rssSources: return "RSS 订阅源"
        case .bookmarks: return "书签"
        case .localBooks: return "本地书籍（含全文，体积较大）"
        case .aiProviders: return "AI 服务商配置（不含 API Key）"
        }
    }

    /// Local books carry each book's full text and can be genuinely large; everything else here is
    /// small metadata/rules. Only this one defaults to off, so a first-time backup doesn't silently
    /// become a slow, large upload the user didn't ask for.
    var defaultEnabled: Bool { self != .localBooks }

    var fileName: String {
        switch self {
        case .bookSources: return "book_sources.json"
        case .shelf: return "shelf.json"
        case .replaceRules: return "replace_rules.json"
        case .highlightRules: return "highlight_rules.json"
        case .tagGroupRules: return "tag_group_rules.json"
        case .txtSplitRules: return "txt_split_rules.json"
        case .rssSources: return "rss_sources.json"
        case .bookmarks: return "bookmarks.json"
        case .localBooks: return "local_books.json"
        case .aiProviders: return "ai_providers.json"
        }
    }
}
