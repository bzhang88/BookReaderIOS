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
    @AppStorage(ReaderSettingsKey.autoScrollInterval) private var autoScrollInterval: Double = 3.0
    @AppStorage(ReaderSettingsKey.volumeKeyPage) private var volumeKeyPageEnabled: Bool = false
    @AppStorage(ReaderSettingsKey.eyeCareEnabled) private var eyeCareEnabled: Bool = false
    @AppStorage(ReaderSettingsKey.eyeCareIntensity) private var eyeCareIntensity: Double = 0.35
    @AppStorage(ReaderSettingsKey.eyeCareScheduleEnabled) private var eyeCareScheduleEnabled: Bool = false
    @AppStorage(ReaderSettingsKey.eyeCareScheduleStartHour) private var eyeCareScheduleStartHour: Int = 20
    @AppStorage(ReaderSettingsKey.eyeCareScheduleEndHour) private var eyeCareScheduleEndHour: Int = 6
    @AppStorage(ReaderSettingsKey.touchSlop) private var touchSlop: Double = 50
    @AppStorage(ReaderSettingsKey.selectedHttpTTSEngineID) private var selectedHttpTTSEngineID: String = ""
    @AppStorage(ReaderSettingsKey.pageTurnStyle) private var pageTurnStyle: PageTurnStyle = .scroll

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var httpTTSEngines: [HttpTTSEngine] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("主题") {
                    ThemeSwatchPicker(theme: $theme)
                    CustomThemeEditor(theme: $theme)
                }

                Section("翻页") {
                    // Not `.segmented` -- 5 two/three-character Chinese labels crammed into a
                    // segmented control read as too tight (the same reason `ReaderTheme`'s picker
                    // was switched to a swatch picker instead of staying segmented).
                    Picker("翻页动画", selection: $pageTurnStyle) {
                        ForEach(PageTurnStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
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
                    Picker("朗读引擎", selection: $selectedHttpTTSEngineID) {
                        Text("系统朗读").tag("")
                        ForEach(httpTTSEngines) { engine in
                            Text(engine.name).tag(engine.id)
                        }
                    }
                    NavigationLink("自定义朗读引擎管理") {
                        HttpTTSEngineListView()
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

                Section("自动滚动") {
                    VStack(alignment: .leading) {
                        Text("每段间隔: \(String(format: "%.1f", autoScrollInterval)) 秒")
                        Slider(value: $autoScrollInterval, in: 1...10, step: 0.5)
                    }
                }

                Section("护眼滤镜") {
                    Toggle("护眼滤镜", isOn: $eyeCareEnabled)
                    VStack(alignment: .leading) {
                        Text("强度: \(Int(eyeCareIntensity * 100))%")
                        Slider(value: $eyeCareIntensity, in: 0...1)
                    }
                    Toggle("按时间自动开启", isOn: $eyeCareScheduleEnabled)
                    if eyeCareScheduleEnabled {
                        Stepper("开始: \(eyeCareScheduleStartHour):00", value: $eyeCareScheduleStartHour, in: 0...23)
                        Stepper("结束: \(eyeCareScheduleEndHour):00", value: $eyeCareScheduleEndHour, in: 0...23)
                    }
                }

                Section("其他") {
                    Toggle("阅读时屏幕常亮", isOn: $keepScreenOn)
                    Toggle("音量键翻页", isOn: $volumeKeyPageEnabled)
                    NavigationLink("点击区域设置") {
                        TapZoneConfigView()
                    }
                    VStack(alignment: .leading) {
                        Text("触控灵敏度: \(Int(touchSlop))")
                        Slider(value: $touchSlop, in: 10...100, step: 5)
                        Text("值越大，点击时手指有轻微移动也会当作有效点击")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
            .task { httpTTSEngines = (try? await env.httpTTSEngineStore.all()) ?? [] }
        }
        .presentationDetents([.medium, .large])
    }
}
