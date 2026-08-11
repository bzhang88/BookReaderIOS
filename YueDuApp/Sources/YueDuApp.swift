import SwiftUI

@main
struct YueDuApp: App {
    @StateObject private var environment = AppEnvironment()
    @AppStorage(ReaderSettingsKey.appFontScale) private var appFontScale: AppFontScale = .standard

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .dynamicTypeSize(appFontScale.dynamicTypeSize)
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
