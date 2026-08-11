import Foundation

/// What tapping one of the reader's 9 screen zones does -- matches Legado's own configurable
/// tap-zone actions, scoped down to the subset that makes sense for a continuous-scroll reader: no
/// "next/prev page" since there are no pages, but chapter nav + TOC + the existing chrome-toggle
/// all carry over directly. Only governs `.scroll` mode (see `PageTurnStyle`) -- the 4 paginated
/// styles use their own fixed left/middle/right tap zones inside `PagedChapterReaderView` instead
/// of this configurable grid, since "turn a page, falling through to the next/previous chapter at
/// the boundary" doesn't map cleanly onto this type's fixed action set without adding new cases
/// this first pass doesn't need.
enum ReaderTapZoneAction: String, CaseIterable, Identifiable, Codable {
    case none, toggleChrome, previousChapter, nextChapter, openToc

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "无操作"
        case .toggleChrome: return "显示/隐藏菜单"
        case .previousChapter: return "上一章"
        case .nextChapter: return "下一章"
        case .openToc: return "打开目录"
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
