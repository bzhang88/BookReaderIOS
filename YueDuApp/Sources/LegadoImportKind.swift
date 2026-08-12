import Foundation

/// The 7 `legado://import/<kind>` path segments, confirmed against `FileAssociationActivity.kt`'s
/// real dispatch (not guessed) -- `httpTts` and `theme` are recognized (so tapping such a link
/// shows a clear "not supported" message rather than silently doing nothing) but not actually
/// importable: real Legado `httpTts` URLs use the same `{{ }}`-JS-eval + POST-body templating book
/// sources' `searchUrl` does (confirmed against `assets/defaultData/httpTTS.json`'s real built-in
/// entries, which use `{{speakText}}` inside JS expressions, sometimes with a whole OAuth-signing
/// `loginUrl` script) -- a materially bigger feature than this app's `HttpTTSEngine`, which only
/// does a plain `{{text}}` string substitution; importing one of these and claiming it "works" would
/// produce an engine that silently fails the moment it's actually used. `theme` still isn't
/// importable, but NOT because this app has no theme system anymore -- `ReaderTheme.CustomThemeEditor`
/// already has its own RGB-picker custom theme with JSON export/import. The real blocker is a format
/// mismatch: confirmed against Legado_Max's actual `ThemeConfig.Config` (`themeName`/`isNightTheme`/
/// `primaryColor`/`accentColor`/`backgroundColor`/`bottomBackground`/`transparentNavBar`/
/// `backgroundImgPath`/`backgroundImgBlur`) that real Legado themes describe the *whole app's* UI
/// chrome (toolbar/accent/nav-bar/background-image), not just a reader page's background+text pair --
/// this app has no app-wide primary/accent/bottom-bar/background-image theming to map those fields
/// onto, so even a "successful" import would have to silently drop most of the real file's content.
enum LegadoImportKind {
    case bookSource, rssSource, replaceRule, txtRule, dictRule
    case httpTts, theme

    private static let byPath: [String: LegadoImportKind] = [
        "/booksource": .bookSource,
        "/rsssource": .rssSource,
        "/replacerule": .replaceRule,
        "/txtrule": .txtRule,
        "/dictrule": .dictRule,
        "/httptts": .httpTts,
        "/theme": .theme
    ]

    init?(path: String) {
        guard let kind = Self.byPath[path.lowercased()] else { return nil }
        self = kind
    }

    var isSupported: Bool {
        switch self {
        case .httpTts, .theme: return false
        default: return true
        }
    }

    var displayName: String {
        switch self {
        case .bookSource: return "书源"
        case .rssSource: return "订阅源"
        case .replaceRule: return "替换净化规则"
        case .txtRule: return "TXT 分章规则"
        case .dictRule: return "词典规则"
        case .httpTts: return "朗读引擎"
        case .theme: return "主题"
        }
    }
}
