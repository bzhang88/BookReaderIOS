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
    /// Which of the 5 page-turn presentations (`PageTurnStyle`) the reader uses -- defaults to
    /// `.scroll` so upgrading doesn't silently change anyone's existing reading behavior.
    static let pageTurnStyle = "reader.pageTurnStyle"
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
