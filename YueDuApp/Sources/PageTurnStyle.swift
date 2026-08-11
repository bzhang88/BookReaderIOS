import Foundation

/// The 5 page-turn presentations, matching Legado's own set exactly per the user's explicit request
/// (无动画/滑动/覆盖/仿真/滚动) -- `.scroll` is this reader's original continuous-scroll-per-chapter
/// behavior (unchanged, and still the default so nobody's reading experience silently changes), the
/// other four all sit on top of `ChapterPaginator`'s real, TextKit-measured page breaks.
enum PageTurnStyle: String, CaseIterable, Identifiable, Codable {
    case scroll, none, slide, cover, curl

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scroll: return "滚动"
        case .none: return "无动画"
        case .slide: return "滑动"
        case .cover: return "覆盖"
        case .curl: return "仿真"
        }
    }

    /// Whether this style renders through the paginated pipeline at all -- `.scroll` keeps using
    /// the reader's original `ScrollView`-per-chapter body untouched.
    var isPaginated: Bool { self != .scroll }
}
