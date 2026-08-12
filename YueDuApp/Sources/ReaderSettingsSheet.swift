import SwiftUI
import BookSourceModel

/// "界面" -- theme/typography/page-turn-style only. Confirmed against Legado_Max's real
/// `ReadStyleDialog` that this is deliberately a *narrow* dialog (color preset swatches, font/
/// spacing sliders, page-turn-animation picker) kept separate from the much longer "设置"
/// preference list (`ReaderMoreSettingsSheet`) -- previously this app crammed both into one giant
/// sheet behind a single unlabeled icon, which is exactly the kind of "too much at once, hard to
/// find anything" pattern real usage feedback flagged. Shares its `@AppStorage` keys directly with
/// `ReaderView`/`LocalReaderView` -- no separate settings object to keep in sync.
struct ReaderStyleSheet: View {
    @AppStorage(ReaderSettingsKey.fontSize) private var fontSize: Double = 18
    @AppStorage(ReaderSettingsKey.lineSpacing) private var lineSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.paragraphSpacing) private var paragraphSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.theme) private var theme: ReaderTheme = .day
    @AppStorage(ReaderSettingsKey.pageTurnStyle) private var pageTurnStyle: PageTurnStyle = .scroll
    @AppStorage(ReaderSettingsKey.pageMarginTop) private var pageMarginTop: Double = 16
    @AppStorage(ReaderSettingsKey.pageMarginBottom) private var pageMarginBottom: Double = 16
    @AppStorage(ReaderSettingsKey.pageMarginLeading) private var pageMarginLeading: Double = 16
    @AppStorage(ReaderSettingsKey.pageMarginTrailing) private var pageMarginTrailing: Double = 16
    @AppStorage(ReaderSettingsKey.paragraphIndent) private var paragraphIndent: Int = 2

    @Environment(\.dismiss) private var dismiss

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
                    Stepper("首行缩进: \(paragraphIndent) 字符", value: $paragraphIndent, in: 0...4)
                }

                // Real usage feedback wanted all 4 margins adjustable independently, not one shared
                // padding value -- matches print-book terminology (页边距) more than a single "边距"
                // slider would.
                Section("页边距") {
                    marginSlider("上边距", value: $pageMarginTop)
                    marginSlider("下边距", value: $pageMarginBottom)
                    marginSlider("左边距", value: $pageMarginLeading)
                    marginSlider("右边距", value: $pageMarginTrailing)
                }
            }
            .navigationTitle("界面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func marginSlider(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            Text("\(label): \(Int(value.wrappedValue))")
            Slider(value: value, in: 0...48, step: 2)
        }
    }
}

/// "设置" -- everything that isn't visual/typographic: read-aloud, simplified/traditional
/// conversion, auto-page/scroll timing, eye care, screen/touch behavior. Matches Legado_Max's real
/// `MoreConfigDialog`, a long scrollable preference list kept separate from "界面"
/// (`ReaderStyleSheet`). Which purification rules matched the current chapter now lives only in the
/// TOC drawer's own 净化规则 tab (`ReaderTocDrawerView`) -- this sheet used to show the exact same
/// `matchedRules` list a second time under different wording ("本章生效的净化规则" here vs. "本章
/// 命中的净化规则" there), which read as an accidental duplication rather than two deliberate entry
/// points once the drawer tab existed.
struct ReaderMoreSettingsSheet: View {
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
    @AppStorage(ReaderSettingsKey.prefetchChapterCount) private var prefetchChapterCount: Int = 1
    @AppStorage(ReaderSettingsKey.backwardPrefetchChapterCount) private var backwardPrefetchChapterCount: Int = 1

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var httpTTSEngines: [HttpTTSEngine] = []

    var body: some View {
        NavigationStack {
            Form {
                // "界面" no longer has its own bottom-row icon in the reader chrome (see
                // `ReaderView`'s redesign against the reference reading app the user pointed at
                // directly, whose menu screenshot only shows 4 primary icons: 目录/亮度/深色/设置)
                // -- reachable from here instead, as the first row, rather than dropped entirely.
                Section {
                    NavigationLink {
                        ReaderStyleSheet()
                    } label: {
                        Label("界面（主题/字体/翻页动画）", systemImage: "textformat.size")
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

                Section(pageTurnStyle.isPaginated ? "自动翻页" : "自动滚动") {
                    VStack(alignment: .leading) {
                        Text(pageTurnStyle.isPaginated ? "每页间隔: \(String(format: "%.1f", autoScrollInterval)) 秒" : "每段间隔: \(String(format: "%.1f", autoScrollInterval)) 秒")
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

                Section {
                    Toggle("阅读时屏幕常亮", isOn: $keepScreenOn)
                    Toggle("音量键翻页", isOn: $volumeKeyPageEnabled)
                    if pageTurnStyle.isPaginated {
                        // Previously this row just vanished with no explanation once the user
                        // switched to a paginated style -- `ReaderTapZoneGrid` only ever governed
                        // `.scroll` mode's 3x3 zones (the 4 paginated styles use their own fixed L/M/R
                        // zones), so a configured grid silently stopped applying with nothing telling
                        // the user why the row was gone. A disabled, explained row is more honest
                        // than pretending the setting doesn't exist.
                        HStack {
                            Text("点击区域设置")
                            Spacer()
                            Text("仅滚动模式可用").font(.caption).foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        NavigationLink("点击区域设置") {
                            TapZoneConfigView()
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("触控灵敏度: \(Int(touchSlop))")
                        Slider(value: $touchSlop, in: 10...100, step: 5)
                        Text("值越大，点击时手指有轻微移动也会当作有效点击")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Stepper("预下载章节数（下一章方向）: \(prefetchChapterCount)", value: $prefetchChapterCount, in: 0...5)
                    Stepper("预下载章节数（上一章方向）: \(backwardPrefetchChapterCount)", value: $backwardPrefetchChapterCount, in: 0...5)
                } header: {
                    Text("其他")
                } footer: {
                    Text("提前在后台下载前后几章的正文，翻章时可以直接秒开，不用等网络。设为 0 关闭对应方向。")
                }
            }
            .navigationTitle("设置")
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
