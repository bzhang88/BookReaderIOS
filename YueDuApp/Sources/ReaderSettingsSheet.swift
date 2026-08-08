import SwiftUI

/// Reading typography/theme settings. Shares its `@AppStorage` keys directly with `ReaderView` --
/// no separate settings object to keep in sync, changes here are visible live behind the sheet
/// since both views read the same UserDefaults-backed keys.
struct ReaderSettingsSheet: View {
    @AppStorage(ReaderSettingsKey.fontSize) private var fontSize: Double = 18
    @AppStorage(ReaderSettingsKey.lineSpacing) private var lineSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.paragraphSpacing) private var paragraphSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.theme) private var theme: ReaderTheme = .day
    @AppStorage(ReaderSettingsKey.keepScreenOn) private var keepScreenOn: Bool = true
    @AppStorage(ReaderSettingsKey.readAloudRate) private var readAloudRate: Double = 0.5

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("主题") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            ForEach(ReaderTheme.allCases) { option in
                                themeSwatch(option)
                            }
                        }
                        .padding(.vertical, 4)
                    }
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

                Section("其他") {
                    Toggle("阅读时屏幕常亮", isOn: $keepScreenOn)
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

    private func themeSwatch(_ option: ReaderTheme) -> some View {
        let isSelected = theme == option
        return Button {
            theme = option
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(option.backgroundColor)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text("阅")
                            .font(.caption2)
                            .foregroundStyle(option.textColor)
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
