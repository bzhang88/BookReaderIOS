import SwiftUI
import UIKit

enum ReaderTheme: String, CaseIterable, Identifiable {
    case system, day, night, sepia, green, gray, custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .day: return "日间"
        case .night: return "夜间"
        case .sepia: return "护眼"
        case .green: return "森绿"
        case .gray: return "灰调"
        case .custom: return "自定义"
        }
    }

    /// `.system` isn't a real palette of its own -- it resolves to `.night`'s exact look in dark
    /// mode and `.day`'s in light mode, so switching iOS appearance switches the reader too without
    /// the user having to remember to flip the swatch by hand. `.custom`'s actual color lives
    /// outside this enum (see `ReaderSettingsKey.customThemeBackgroundHex`/`customThemeTextHex`) --
    /// callers that render `.custom` pass the live color in; ones that don't care (most existing
    /// call sites, rendering a swatch for a *different* preset) just get the fallback default.
    func backgroundColor(for colorScheme: ColorScheme, customBackground: Color? = nil) -> Color {
        switch self {
        case .system: return colorScheme == .dark ? ReaderTheme.night.backgroundColor(for: colorScheme) : ReaderTheme.day.backgroundColor(for: colorScheme)
        case .day: return Color(red: 1, green: 1, blue: 1)
        case .night: return Color(red: 0.08, green: 0.08, blue: 0.08)
        case .sepia: return Color(red: 0.96, green: 0.93, blue: 0.84)
        case .green: return Color(red: 0.80, green: 0.90, blue: 0.78)
        case .gray: return Color(red: 0.20, green: 0.20, blue: 0.22)
        case .custom: return customBackground ?? Color(red: 1, green: 1, blue: 1)
        }
    }

    func textColor(for colorScheme: ColorScheme, customText: Color? = nil) -> Color {
        switch self {
        case .system: return colorScheme == .dark ? ReaderTheme.night.textColor(for: colorScheme) : ReaderTheme.day.textColor(for: colorScheme)
        case .day: return Color(red: 0.05, green: 0.05, blue: 0.05)
        case .night: return Color(red: 0.82, green: 0.82, blue: 0.82)
        case .sepia: return Color(red: 0.30, green: 0.22, blue: 0.10)
        case .green: return Color(red: 0.10, green: 0.25, blue: 0.10)
        case .gray: return Color(red: 0.80, green: 0.80, blue: 0.82)
        case .custom: return customText ?? Color(red: 0.05, green: 0.05, blue: 0.05)
        }
    }
}

/// Minimal hex <-> Color bridging for the custom theme's `ColorPicker`s and its export/import JSON
/// -- SwiftUI's `Color` has no built-in hex support.
extension Color {
    init?(hex: String) {
        let sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard sanitized.count == 6, let rgb = UInt32(sanitized, radix: 16) else { return nil }
        self = Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    /// Resolves through `UIColor` to read back RGB components -- `Color` itself doesn't expose them
    /// directly.
    func toHex() -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}

/// Horizontally scrollable row of circular color swatches for picking a `ReaderTheme` -- shared by
/// `ReaderStyleSheet` and `LocalReaderStyleSheet` so the two readers' "界面" sheets stay visually
/// identical without duplicating this view.
struct ThemeSwatchPicker: View {
    @Binding var theme: ReaderTheme
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ReaderSettingsKey.customThemeBackgroundHex) private var customBackgroundHex: String = "#FFFFFF"
    @AppStorage(ReaderSettingsKey.customThemeTextHex) private var customTextHex: String = "#0D0D0D"

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(ReaderTheme.allCases) { option in
                    swatch(option)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func swatch(_ option: ReaderTheme) -> some View {
        let isSelected = theme == option
        return Button {
            theme = option
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(option.backgroundColor(for: colorScheme, customBackground: Color(hex: customBackgroundHex)))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text("阅")
                            .font(.caption2)
                            .foregroundStyle(option.textColor(for: colorScheme, customText: Color(hex: customTextHex)))
                    )
                    .overlay(
                        Circle().strokeBorder(
                            isSelected ? Color.accentColor : Color.gray.opacity(0.3),
                            lineWidth: isSelected ? 3 : 1
                        )
                    )
                Text(option.displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Only visible when `.custom` is the selected theme -- RGB pickers for its background/text color,
/// plus a lightweight export/import via the system pasteboard (copy a small JSON blob out, paste
/// one back in) so a hand-tuned theme can be shared or carried to a reinstall without needing a
/// full file-picker UI. Shared by both readers' settings sheets, same pattern as `ThemeSwatchPicker`.
struct CustomThemeEditor: View {
    @Binding var theme: ReaderTheme
    @AppStorage(ReaderSettingsKey.customThemeBackgroundHex) private var customBackgroundHex: String = "#FFFFFF"
    @AppStorage(ReaderSettingsKey.customThemeTextHex) private var customTextHex: String = "#0D0D0D"
    @State private var statusMessage: String?

    var body: some View {
        if theme == .custom {
            VStack(alignment: .leading, spacing: 12) {
                ColorPicker("背景色", selection: Binding(
                    get: { Color(hex: customBackgroundHex) ?? .white },
                    set: { customBackgroundHex = $0.toHex() }
                ))
                ColorPicker("文字色", selection: Binding(
                    get: { Color(hex: customTextHex) ?? .black },
                    set: { customTextHex = $0.toHex() }
                ))
                HStack {
                    Button("复制主题") { copyTheme() }
                    Spacer()
                    Button("从剪贴板导入") { importTheme() }
                }
                .font(.caption)
                if let statusMessage {
                    Text(statusMessage).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func copyTheme() {
        let export = CustomThemeExport(backgroundHex: customBackgroundHex, textHex: customTextHex)
        guard let data = try? JSONEncoder().encode(export), let json = String(data: data, encoding: .utf8) else { return }
        UIPasteboard.general.string = json
        statusMessage = "已复制到剪贴板"
    }

    private func importTheme() {
        guard let text = UIPasteboard.general.string, let data = text.data(using: .utf8),
              let imported = try? JSONDecoder().decode(CustomThemeExport.self, from: data) else {
            statusMessage = "剪贴板内容不是有效的主题"
            return
        }
        customBackgroundHex = imported.backgroundHex
        customTextHex = imported.textHex
        statusMessage = "导入成功"
    }
}

struct CustomThemeExport: Codable {
    var backgroundHex: String
    var textHex: String
}

/// Keys shared verbatim between `ReaderView` and its `ReaderStyleSheet`/`ReaderMoreSettingsSheet`
/// (and the `LocalReaderView` equivalents) so all of them stay in sync via plain `@AppStorage`
/// (same UserDefaults key, no custom ObservableObject needed -- avoids the well-known gotcha where
/// `@AppStorage` inside a hand-rolled ObservableObject doesn't actually propagate change
/// notifications on its own).
enum ReaderSettingsKey {
    static let fontSize = "reader.fontSize"
    static let lineSpacing = "reader.lineSpacing"
    static let paragraphSpacing = "reader.paragraphSpacing"
    static let theme = "reader.theme"
    static let keepScreenOn = "reader.keepScreenOn"
    /// 0.0...1.0, matches `AVSpeechUtterance.rate`'s range (`AVSpeechUtteranceDefaultSpeechRate`
    /// is 0.5) -- stored as a plain Double since `@AppStorage` doesn't support Float directly.
    static let readAloudRate = "reader.readAloudRate"
    static let chineseConversion = "reader.chineseConversion"
    /// Seconds between each auto-scroll step -- one paragraph per step, not a continuous pixel
    /// scroll (see `ReaderView`'s auto-scroll doc comment for why paragraph granularity was chosen).
    static let autoScrollInterval = "reader.autoScrollInterval"
    /// JSON-encoded `ReaderTapZoneGrid` -- a struct rather than 9 primitive keys since `@AppStorage`
    /// properties can't be declared dynamically in a loop.
    static let tapZoneGrid = "reader.tapZoneGrid"
    /// Off by default -- matches Legado's own `volumeKeyPage` being opt-in, since hijacking the
    /// hardware volume buttons is surprising behavior if the user didn't ask for it.
    static let volumeKeyPage = "reader.volumeKeyPage"
    /// Eye-care color-temperature filter -- separate from `theme`'s day/night/eye-protect presets:
    /// a warm-tint overlay that can layer on top of *any* theme, optionally on its own schedule,
    /// rather than being just another fixed color scheme to switch to manually.
    static let eyeCareEnabled = "reader.eyeCareEnabled"
    static let eyeCareIntensity = "reader.eyeCareIntensity"
    static let eyeCareScheduleEnabled = "reader.eyeCareScheduleEnabled"
    static let eyeCareScheduleStartHour = "reader.eyeCareScheduleStartHour"
    static let eyeCareScheduleEndHour = "reader.eyeCareScheduleEndHour"
    /// Confirmed against Legado_Max's real `AppConfig.pageTouchSlop` (overrides the system's
    /// `scaledTouchSlop` in `ReadView.kt`) -- how far a finger can drift during a touch-down/up and
    /// still count as a tap rather than a scroll/drag attempt. This app's tap-zone gesture (see
    /// `ReaderView.handleTap`) previously had no such tolerance check at all, so the *default* here
    /// is deliberately generous (50pt) rather than a tight value, to avoid silently changing already
    /// -shipped tap behavior for existing users -- this is a new tunable, not a bug fix.
    static let touchSlop = "reader.touchSlop"
    /// Empty string (the default) means "use the system `AVSpeechSynthesizer` voice" -- a non-empty
    /// value naming a configured `HttpTTSEngine`'s id switches the 朗读 button over to
    /// `HttpReadAloudController` instead. Kept as a single id rather than a bool + separate id pair
    /// since "which engine" and "whether to use a custom one at all" are the same choice here.
    static let selectedHttpTTSEngineID = "reader.selectedHttpTTSEngineID"
    /// `ReaderTheme.custom`'s actual colors, as `#RRGGBB` hex strings -- kept outside the
    /// `ReaderTheme` enum itself since `@AppStorage` needs the enum's raw value to be the *whole*
    /// state, which can't carry an associated color value cleanly.
    static let customThemeBackgroundHex = "reader.customThemeBackgroundHex"
    static let customThemeTextHex = "reader.customThemeTextHex"
    /// App-wide text scale via SwiftUI's native `.dynamicTypeSize(_:)`, applied once at the root
    /// view -- confirmed against Legado_Max's real `PreferKey.fontScale`/`AppContextWrapper` that
    /// this is meant to scale the *whole app's* UI, not just the reader (which already has its own
    /// separate `fontSize` control). Stored as a `DynamicTypeSize` case name string.
    static let appFontScale = "app.fontScale"
    /// Stores an `AppAppearanceMode` raw value -- see `YueDuApp.swift` for the enum and where this
    /// gets applied (`.preferredColorScheme` at the root `WindowGroup`).
    static let appAppearanceMode = "app.appearanceMode"
    /// `#RRGGBB`, or empty string for "use the system default blue" -- real usage feedback: 浅色/
    /// 深色 alone still only gave 2 fixed states, this is the actual "choose the color I want" lever
    /// (applied via `.tint` at the root, see `YueDuApp.swift`).
    static let appAccentColorHex = "app.accentColorHex"
    /// Which of the 5 page-turn presentations (`PageTurnStyle`) the reader uses -- defaults to
    /// `.scroll` so upgrading doesn't silently change anyone's existing reading behavior.
    static let pageTurnStyle = "reader.pageTurnStyle"
    /// How many chapters *ahead* of the current one to speculatively fetch into `ChapterCacheStore`
    /// in the background -- 0 disables prefetching entirely. Defaults to 1 (just the very next
    /// chapter, the overwhelmingly common next action) rather than something larger, to keep the
    /// default behavior's extra network usage modest.
    static let prefetchChapterCount = "reader.prefetchChapterCount"
    /// Backward mirror of `prefetchChapterCount` -- confirmed against Legado_Max's own `ReadBook.
    /// preDownload`, which warms raw chapter text on *both* sides of the resident reading window
    /// (`backwardPreDownloadNum`, not just `preDownloadNum`). Also defaults to 1: scrolling back up
    /// past where you started (re-reading, or continuing a backward scroll) was only ever cache-warm
    /// one chapter back (whichever `prevChapterPreview` itself already fetched) before this existed,
    /// unlike going forward.
    static let backwardPrefetchChapterCount = "reader.backwardPrefetchChapterCount"
    /// Independent top/bottom/leading/trailing page margins -- real usage feedback wanted all 4
    /// adjustable separately, not just one shared padding value. Each defaults to 16 (matching what
    /// the previous hardcoded `.padding()` used).
    static let pageMarginTop = "reader.pageMarginTop"
    static let pageMarginBottom = "reader.pageMarginBottom"
    static let pageMarginLeading = "reader.pageMarginLeading"
    static let pageMarginTrailing = "reader.pageMarginTrailing"
    /// How many full-width space characters ("　", not a regular ASCII space -- matches real Chinese
    /// print typesetting) to prepend to every paragraph. Defaults to 2, the conventional "首行缩进
    /// 两个字符" real Chinese novels use -- previously this only ever happened by accident, when a
    /// book source's own optional `replaceRegex` rule happened to add it (see `ContentService
    /// .applyReplaceRegex`'s doc comment), so most books had no indent at all.
    static let paragraphIndent = "reader.paragraphIndent"
    /// Stores a `ReaderOrientationLock` raw value -- see that enum's doc comment for the mapping to
    /// `UIInterfaceOrientationMask`, and `OrientationLock`/`AppDelegate.swift` for how it's actually
    /// enforced (Info.plist alone can't do per-screen locking, only a global allowed set).
    static let screenOrientationLock = "reader.screenOrientationLock"
    /// Stores a `LocalImportCharset` raw value -- see that enum's doc comment for why this is a
    /// global default rather than Legado's own per-book `Book.charset` (re-editable any time).
    static let localImportCharset = "reader.localImportCharset"
    /// Stores a `ProgressBarBehavior` raw value -- see that enum's doc comment. Matches Legado's own
    /// `AppConfig.progressBarBehavior` ("page"/"chapter") default of "page".
    static let progressBarBehavior = "reader.progressBarBehavior"
}

/// What dragging the reader's bottom progress seekbar does -- confirmed against Legado_Max's own
/// `AppConfig.progressBarBehavior`: `.page` (the existing, default behavior) jumps within the
/// current chapter's pages, released immediately with no confirmation. `.chapter` repurposes the
/// same seekbar to jump across the *whole book's* chapters instead -- a much bigger, harder-to-undo
/// jump, which is why `ReadMenu.kt`'s "chapter" branch shows a one-time-per-session confirmation
/// alert before actually committing (see `ReaderView.requestChapterJump`).
enum ProgressBarBehavior: String, CaseIterable, Identifiable, Codable {
    case page, chapter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .page: return "页内跳转"
        case .chapter: return "章节跳转"
        }
    }
}

/// Confirmed against Legado_Max's own `BaseReadBookActivity.showCharsetConfig()`/`ReadBook.
/// setCharset` -- real .txt files from Chinese novel sites are frequently GBK/GB18030, not UTF-8,
/// and `CharsetDetector.decodeAutodetectingBytes`'s heuristic (try strict UTF-8, then GB18030) can
/// still guess wrong for a genuinely ambiguous file. Deliberately a *global default* applied at
/// import time, not Legado's per-book `charset` field re-editable after the fact: `LocalBook` only
/// ever stores the already-decoded, already-chapter-split text (see `LocalBookListView.handleImport`)
/// -- unlike Legado, which keeps the original file path and can freely re-decode raw bytes on
/// demand, this app deliberately does *not* hold onto a security-scoped file reference past import
/// (those are fragile across app relaunches/file moves/offline iCloud files), so there are no raw
/// bytes left to re-decode once a book exists. A wrongly-imported book's real fix is re-importing
/// with the right charset picked here -- less convenient than Legado's "edit and it just re-decodes,"
/// but honest about what this app's storage model can actually support.
enum LocalImportCharset: String, CaseIterable, Identifiable, Codable {
    case auto, utf8, gbk, gb18030, big5

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "自动检测"
        case .utf8: return "UTF-8"
        case .gbk: return "GBK"
        case .gb18030: return "GB18030"
        case .big5: return "Big5"
        }
    }

    /// `nil` for `.auto` -- callers branch to `CharsetDetector.decodeAutodetectingBytes` instead of
    /// calling `decode(_:charset:)` at all in that case. Everything else is handed straight to
    /// `CharsetDetector.decode(_:charset:)`, which already normalizes case/hyphens/underscores.
    var charsetIdentifier: String? {
        switch self {
        case .auto: return nil
        case .utf8: return "utf8"
        case .gbk: return "gbk"
        case .gb18030: return "gb18030"
        case .big5: return "big5"
        }
    }
}

/// Confirmed against Legado_Max's own `AppConfig.screenOrientation`
/// (`BaseReadBookActivity.setOrientation`, `ReadConstants`-adjacent) -- a per-reader-session
/// orientation lock, independent of whatever orientation the rest of the app (书架/发现/我的) uses.
/// Only takes effect while a reader screen is on-screen: `ReaderView`/`LocalReaderView` write
/// `OrientationLock.mask` on `.onAppear` and reset it back to `.allButUpsideDown` on `.onDisappear`,
/// exactly like `BaseReadBookActivity` only calls `setOrientation()` for itself, not app-wide.
enum ReaderOrientationLock: String, CaseIterable, Identifiable, Codable {
    case followSystem, portrait, landscape, autoRotate, portraitUpsideDown, landscapeReverse

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .followSystem: return "跟随系统"
        case .portrait: return "竖屏"
        case .landscape: return "横屏"
        case .autoRotate: return "自动旋转"
        case .portraitUpsideDown: return "反向竖屏"
        case .landscapeReverse: return "反向横屏"
        }
    }

    /// iOS has no literal "unspecified" orientation the way Android's `SCREEN_ORIENTATION_UNSPECIFIED`
    /// does -- `.allButUpsideDown` (portrait + both landscapes, no upside-down) is the standard iPhone
    /// default every stock app effectively behaves as, so `.followSystem` maps to that rather than
    /// `.all`.
    var mask: UIInterfaceOrientationMask {
        switch self {
        case .followSystem: return .allButUpsideDown
        case .portrait: return .portrait
        case .landscape: return .landscape
        case .autoRotate: return .all
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeReverse: return .landscapeRight
        }
    }
}

/// The actual enforcement mechanism behind `ReaderOrientationLock`: SwiftUI's `App`/`Scene` has no
/// API of its own for restricting orientation, so this app needs a minimal `UIApplicationDelegate`
/// (see `AppDelegate.swift`) whose `application(_:supportedInterfaceOrientationsFor:)` is the one
/// hook UIKit actually consults. That delegate method can't read `@AppStorage`/SwiftUI state
/// directly (it's called by UIKit outside any SwiftUI view context), so this plain static var is the
/// hand-off point: `ReaderView`/`LocalReaderView` write it, the delegate reads it. UIKit only
/// re-queries `supportedInterfaceOrientationsFor:` on specific triggers (a view controller
/// presentation, or an explicit `setNeedsUpdateOfSupportedInterfaceOrientations()`/
/// `requestGeometryUpdate` call) -- it does NOT observe this var changing on its own, so every write
/// here is paired with `OrientationLock.applyToActiveScene()` to force that re-query immediately.
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .allButUpsideDown

    @MainActor
    static func applyToActiveScene() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }
}

/// Whether (and which direction) to run chapter text through `ChineseTextConverter` before
/// display -- separate from `ReplaceRule`/`HighlightRule` since this isn't a user-authored pattern,
/// it's a single built-in on/off/direction choice.
enum ChineseConversionMode: String, CaseIterable, Identifiable {
    case off, toTraditional, toSimplified

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "不转换"
        case .toTraditional: return "简转繁"
        case .toSimplified: return "繁转简"
        }
    }
}
