import SwiftUI

@main
struct YueDuApp: App {
    @StateObject private var environment = AppEnvironment()
    @AppStorage(ReaderSettingsKey.appFontScale) private var appFontScale: AppFontScale = .standard
    @AppStorage(ReaderSettingsKey.appAppearanceMode) private var appAppearanceMode: AppAppearanceMode = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .dynamicTypeSize(appFontScale.dynamicTypeSize)
                // Applied once here at the root, so it reaches every screen including the reader --
                // real usage feedback was that the reader's own day/night theme (see `ReaderTheme`)
                // could end up looking nothing like the rest of the app (书架/发现/我的 etc, which
                // previously had no in-app control at all and just silently followed the raw OS
                // setting), which read as jarring switching back and forth. `ReaderTheme.system`
                // resolves off `@Environment(\.colorScheme)`, and `.preferredColorScheme` is exactly
                // what overrides that environment value for every descendant view -- so forcing the
                // app into dark mode here also makes a reader left on "跟随系统" render as night,
                // without needing to duplicate this picker inside the reader's own settings too.
                // `.system` maps to `nil`, which per SwiftUI's documented behavior just lets the real
                // OS appearance flow through unchanged.
                .preferredColorScheme(appAppearanceMode.colorScheme)
        }
    }
}

/// Confirmed against Legado_Max's real `PreferKey.fontScale` that this is meant to scale the whole
/// app's UI (not just the reader, which already has its own separate `fontSize` slider) -- backed
/// by SwiftUI's native `.dynamicTypeSize(_:)` applied once at the root, rather than a custom
/// per-view font multiplier. A small named enum rather than exposing all 12 raw `DynamicTypeSize`
/// cases (including the accessibility sizes meant for the system-wide accessibility setting, not a
/// per-app preference) keeps the picker to a handful of sensible steps.
enum AppFontScale: String, CaseIterable, Identifiable {
    case small, standard, large, extraLarge, huge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: return "小"
        case .standard: return "标准"
        case .large: return "大"
        case .extraLarge: return "特大"
        case .huge: return "超大"
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: return .small
        case .standard: return .large
        case .large: return .xLarge
        case .extraLarge: return .xxLarge
        case .huge: return .xxxLarge
        }
    }
}

/// App-wide light/dark override, independent of (but able to *drive*) the reader's own `ReaderTheme`
/// -- see `YueDuApp.body`'s doc comment for why forcing this also forces a "跟随系统" reader theme
/// to match, which is the whole point: before this existed, the rest of the app had no in-app
/// appearance control at all and just followed the raw OS setting silently.
enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    /// `nil` is `.preferredColorScheme`'s documented way of saying "don't override" -- only
    /// `.light`/`.dark` actually force one.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
