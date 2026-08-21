import Foundation

/// What tapping one of the reader's 9 screen zones does -- matches Legado's own configurable
/// tap-zone actions (`ClickActionConfigDialog.kt`'s 14-entry `actions` map). Only governs `.scroll`
/// mode (see `PageTurnStyle`) -- the 4 paginated styles use their own fixed left/middle/right tap
/// zones inside `PagedChapterReaderView` instead of this configurable grid. `.nextPage`/
/// `.previousPage` are the scroll-mode reader's honest approximation of "turn a page" -- there's no
/// real page boundary to speak of in continuous text, so these just step forward/backward by a few
/// paragraphs, reusing the exact same mechanism the volume-key paging feature already uses (see
/// `ReaderView.handleVolumeKeyTurn`).
///
/// Deliberately omits 2 of Legado's 14: `sync_book_progress_t` (manual "sync reading progress" tap)
/// has nothing to bind to -- this app has no cloud/WebDAV sync feature at all, unlike Legado. And
/// `replace_state_change` (`ReadBook.book.useReplaceRule` toggle -- a per-book on/off switch,
/// persisted on the book itself) maps to `togglePurification` here but only *opens* the existing
/// 净化规则 panel rather than replicating the per-book bool: this app has no such field on its book
/// models yet, and adding one is a persistence-layer change in its own right, not a tap-zone wiring
/// task.
enum ReaderTapZoneAction: String, CaseIterable, Identifiable, Codable {
    case none, toggleChrome, previousChapter, nextChapter, openToc, nextPage, previousPage, exitReader
    case readAloudPreviousParagraph, readAloudNextParagraph, toggleReadAloudPauseResume
    case toggleBookmark, editContent, togglePurification, contentSearch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "无操作"
        case .toggleChrome: return "显示/隐藏菜单"
        case .previousChapter: return "上一章"
        case .nextChapter: return "下一章"
        case .openToc: return "打开目录"
        case .nextPage: return "下一页（向下滚动几段）"
        case .previousPage: return "上一页（向上滚动几段）"
        case .exitReader: return "退出阅读"
        case .readAloudPreviousParagraph: return "朗读上一段"
        case .readAloudNextParagraph: return "朗读下一段"
        case .toggleReadAloudPauseResume: return "朗读暂停/继续"
        case .toggleBookmark: return "添加/取消书签"
        case .editContent: return "编辑本章内容"
        case .togglePurification: return "净化规则"
        case .contentSearch: return "搜索本书内容"
        }
    }
}

/// A 3×3 grid of tap-zone actions, row-major (index 0 = top-left, 8 = bottom-right) -- mirrors
/// Legado's own `ClickActionConfigDialog` tap-region model (tl/tc/tr/ml/mc/mr/bl/bc/br), just with
/// a smaller action set (see `ReaderTapZoneAction`'s doc comment for why). Stored as a JSON string
/// via `@AppStorage` rather than 9 separate keys, since `@AppStorage` property wrappers can't be
/// declared dynamically in a loop.
struct ReaderTapZoneGrid: Codable, Equatable {
    var actions: [ReaderTapZoneAction]

    /// Classic "middle column toggles chrome, side columns turn chapters" layout -- the same
    /// default shape Legado itself ships (center tap = menu, left/right thirds = prev/next), just
    /// substituting chapter-nav for page-nav since this reader has no pages.
    static let standard = ReaderTapZoneGrid(actions: [
        .toggleChrome, .toggleChrome, .toggleChrome,
        .previousChapter, .toggleChrome, .nextChapter,
        .previousChapter, .toggleChrome, .nextChapter
    ])

    func action(row: Int, col: Int) -> ReaderTapZoneAction {
        let index = row * 3 + col
        guard actions.indices.contains(index) else { return .toggleChrome }
        return actions[index]
    }

    mutating func setAction(_ action: ReaderTapZoneAction, row: Int, col: Int) {
        let index = row * 3 + col
        guard actions.indices.contains(index) else { return }
        actions[index] = action
    }

    func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self), let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    static let standardEncoded: String = standard.encoded()

    static func decode(_ raw: String) -> ReaderTapZoneGrid {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ReaderTapZoneGrid.self, from: data),
              decoded.actions.count == 9 else {
            return .standard
        }
        return decoded
    }
}
