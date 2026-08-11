import SwiftUI
import BookSourceModel

/// Reading typography/theme settings. Shares its `@AppStorage` keys directly with `ReaderView` --
/// no separate settings object to keep in sync, changes here are visible live behind the sheet
/// since both views read the same UserDefaults-backed keys.
struct ReaderSettingsSheet: View {
    /// Which of the user's purification rules actually fired on the chapter currently on screen --
    /// passed in rather than recomputed here, since the sheet has no access to the chapter text
    /// itself (only `ReaderView`/`LocalReaderView` do, right after fetching/loading it).
    var matchedRules: [ReplaceRule] = []

    @AppStorage(ReaderSettingsKey.fontSize) private var fontSize: Double = 18
    @AppStorage(ReaderSettingsKey.lineSpacing) private var lineSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.paragraphSpacing) private var paragraphSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.theme) private var theme: ReaderTheme = .day
    @AppStorage(ReaderSettingsKey.keepScreenOn) private var keepScreenOn: Bool = true
    @AppStorage(ReaderSettingsKey.readAloudRate) private var readAloudRate: Double = 0.5
    @AppStorage(ReaderSettingsKey.chineseConversion) private var chineseConversion: ChineseConversionMode = .off

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("主题") {
                    ThemeSwatchPicker(theme: $theme)
                }

                Section("字体") {
                    VStack(alignment: .leading) {
                        Text("字号: \(Int(fontSize))")
                        Slider(value: $fontSize, in: 12...32, step: 1)
                    }
                    VStack(alignment: .leading) {
                        Text("行间距: \(Int(lineSpacing))")
                        Slider(value: $lineSpacing, in: 0...24, step: 1)
                    }
                    VStack(alignment: .leading) {
                        Text("段间距: \(Int(paragraphSpacing))")
                        Slider(value: $paragraphSpacing, in: 0...32, step: 1)
                    }
                }

                Section("朗读") {
                    VStack(alignment: .leading) {
                        Text("语速: \(Int(readAloudRate * 100))%")
                        Slider(value: $readAloudRate, in: 0.1...1.0)
                    }
                }

                Section("简繁转换") {
                    Picker("简繁转换", selection: $chineseConversion) {
                        ForEach(ChineseConversionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("其他") {
                    Toggle("阅读时屏幕常亮", isOn: $keepScreenOn)
                }

                Section("本章生效的净化规则") {
                    if matchedRules.isEmpty {
                        Text("本章没有命中任何净化规则").foregroundStyle(.secondary)
                    } else {
                        ForEach(matchedRules) { rule in
                            Text(rule.name)
                        }
                    }
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
