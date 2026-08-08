import SwiftUI

enum ReaderTheme: String, CaseIterable, Identifiable {
    case day, night, sepia, green, gray

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .day: return "日间"
        case .night: return "夜间"
        case .sepia: return "护眼"
        case .green: return "森绿"
        case .gray: return "灰调"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .day: return Color(red: 1, green: 1, blue: 1)
        case .night: return Color(red: 0.08, green: 0.08, blue: 0.08)
        case .sepia: return Color(red: 0.96, green: 0.93, blue: 0.84)
        case .green: return Color(red: 0.80, green: 0.90, blue: 0.78)
        case .gray: return Color(red: 0.20, green: 0.20, blue: 0.22)
        }
    }

    var textColor: Color {
        switch self {
        case .day: return Color(red: 0.05, green: 0.05, blue: 0.05)
        case .night: return Color(red: 0.82, green: 0.82, blue: 0.82)
        case .sepia: return Color(red: 0.30, green: 0.22, blue: 0.10)
        case .green: return Color(red: 0.10, green: 0.25, blue: 0.10)
        case .gray: return Color(red: 0.80, green: 0.80, blue: 0.82)
        }
    }
}

/// Keys shared verbatim between `ReaderView` and `ReaderSettingsSheet` so both stay in sync via
/// plain `@AppStorage` (same UserDefaults key, no custom ObservableObject needed -- avoids the
/// well-known gotcha where `@AppStorage` inside a hand-rolled ObservableObject doesn't actually
/// propagate change notifications on its own).
enum ReaderSettingsKey {
    static let fontSize = "reader.fontSize"
    static let lineSpacing = "reader.lineSpacing"
    static let paragraphSpacing = "reader.paragraphSpacing"
    static let theme = "reader.theme"
    static let keepScreenOn = "reader.keepScreenOn"
    /// 0.0...1.0, matches `AVSpeechUtterance.rate`'s range (`AVSpeechUtteranceDefaultSpeechRate`
    /// is 0.5) -- stored as a plain Double since `@AppStorage` doesn't support Float directly.
    static let readAloudRate = "reader.readAloudRate"
}
