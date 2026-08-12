import SwiftUI
import UIKit
import BookSourceModel
import WebBookOrchestrator
import Persistence

/// Reader for a locally-imported .txt book. Deliberately simpler than `ReaderView`: no network
/// fetch (all chapter text is already in `book.chapters`), no read-aloud/TTS in this first
/// increment. Shares its typography/theme `@AppStorage` keys with `ReaderView` so font size and
/// theme choice carry over between network and local books rather than needing to be set twice.
struct LocalReaderView: View {
    let book: LocalBook

    @EnvironmentObject private var env: AppEnvironment
    @State private var currentIndex: Int
    @State private var isShowingStyleSheet = false
    @State private var isShowingMoreSettings = false
    @State private var isSettingsPanelVisible = false
    @State private var isCurrentChapterBookmarked = false
    @State private var matchedReplaceRules: [ReplaceRule] = []
    @State private var isShowingContentSearch = false
    @State private var isShowingAISummary = false
    @State private var isShowingDictLookup = false
    @State private var isShowingWebSearch = false
    @State private var isShowingToc = false
    @State private var isBrightnessVisible = false
    @State private var screenBrightness: Double = Double(UIScreen.main.brightness)
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(ReaderSettingsKey.fontSize) private var fontSize: Double = 18
    @AppStorage(ReaderSettingsKey.lineSpacing) private var lineSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.paragraphSpacing) private var paragraphSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.theme) private var theme: ReaderTheme = .day
    @AppStorage(ReaderSettingsKey.keepScreenOn) private var keepScreenOn: Bool = true
    @AppStorage(ReaderSettingsKey.chineseConversion) private var chineseConversion: ChineseConversionMode = .off
    @AppStorage(ReaderSettingsKey.volumeKeyPage) private var volumeKeyPageEnabled: Bool = false
    @State private var volumeButtonController = VolumeButtonPageTurnController()
    @State private var volumeScrollIndex = 0
    @AppStorage(ReaderSettingsKey.eyeCareEnabled) private var eyeCareEnabled: Bool = false
    @AppStorage(ReaderSettingsKey.eyeCareIntensity) private var eyeCareIntensity: Double = 0.35
    @AppStorage(ReaderSettingsKey.eyeCareScheduleEnabled) private var eyeCareScheduleEnabled: Bool = false
    @AppStorage(ReaderSettingsKey.eyeCareScheduleStartHour) private var eyeCareScheduleStartHour: Int = 20
    @AppStorage(ReaderSettingsKey.eyeCareScheduleEndHour) private var eyeCareScheduleEndHour: Int = 6
    @AppStorage(ReaderSettingsKey.customThemeBackgroundHex) private var customThemeBackgroundHex: String = "#FFFFFF"
    @AppStorage(ReaderSettingsKey.customThemeTextHex) private var customThemeTextHex: String = "#0D0D0D"
    @AppStorage(ReaderSettingsKey.pageTurnStyle) private var pageTurnStyle: PageTurnStyle = .scroll
    @AppStorage(ReaderSettingsKey.touchSlop) private var touchSlop: Double = 50
    @State private var pageAnchor: PageAnchor = .first
    @State private var pageTurnRequest: PageTurnRequest?
    @State private var pageJumpRequest: Int?
    @State private var pagedPageProgress: (current: Int, total: Int)?
    @State private var pageSeekDragValue: Double?
    @State private var scheduleTick = Date()
    private let scheduleTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var isEyeCareActive: Bool {
        eyeCareEnabled || (eyeCareScheduleEnabled && EyeCareSchedule.isActive(
            startHour: eyeCareScheduleStartHour, endHour: eyeCareScheduleEndHour, now: scheduleTick
        ))
    }

    /// `startChapterIndex` overrides the book's own last-read position -- used when jumping in from
    /// a bookmark, which names an exact chapter rather than "wherever I left off." `startWithTocOpen`
    /// exists purely for CI's screenshot workflow (see `RootView`'s `-uiTestingScreen
    /// localReaderToc`) -- there's no other way to get a screenshot of the drawer actually open,
    /// since CI can't tap anything.
    init(book: LocalBook, startChapterIndex: Int? = nil, startWithTocOpen: Bool = false) {
        self.book = book
        let fallback = book.lastReadChapterIndex.flatMap { book.chapters.indices.contains($0) ? $0 : nil } ?? 0
        let start = startChapterIndex.flatMap { book.chapters.indices.contains($0) ? $0 : nil } ?? fallback
        self._currentIndex = State(initialValue: start)
        self._isShowingToc = State(initialValue: startWithTocOpen)
    }

    private var chapter: LocalChapter { book.chapters[currentIndex] }
    private var paragraphs: [String] { purifiedText.components(separatedBy: "\n") }
    @State private var purifiedText: String = ""

    private var chapterProgressText: String {
        let chapterPart = "第 \(currentIndex + 1) / \(book.chapters.count) 章"
        guard pageTurnStyle.isPaginated, let pagedPageProgress else { return chapterPart }
        return "\(chapterPart) · 第 \(pagedPageProgress.current) / \(pagedPageProgress.total) 页"
    }

    private var pageSeekBinding: Binding<Double> {
        Binding(
            get: { pageSeekDragValue ?? Double((pagedPageProgress?.current ?? 1) - 1) },
            set: { pageSeekDragValue = $0 }
        )
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
        Group {
            if pageTurnStyle.isPaginated {
                PagedChapterReaderView(
                    text: purifiedText,
                    style: pageTurnStyle,
                    fontSize: fontSize,
                    lineSpacing: lineSpacing,
                    paragraphSpacing: paragraphSpacing,
                    textColor: theme.textColor(for: colorScheme, customText: Color(hex: customThemeTextHex)),
                    backgroundColor: theme.backgroundColor(for: colorScheme, customBackground: Color(hex: customThemeBackgroundHex)),
                    highlightRules: [],
                    readAloudParagraphIndex: nil,
                    initialAnchor: pageAnchor,
                    pageTurnRequest: $pageTurnRequest,
                    pageJumpRequest: $pageJumpRequest,
                    touchSlop: touchSlop,
                    onTapMiddle: {},
                    onRequestPreviousChapter: { goTo(currentIndex - 1, anchor: .last) },
                    onRequestNextChapter: { goTo(currentIndex + 1) },
                    onPageChanged: { current, total in pagedPageProgress = (current, total) }
                )
            } else {
        ScrollView {
            VStack(alignment: .leading, spacing: paragraphSpacing) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    Text(paragraph)
                        .font(.system(size: fontSize))
                        .lineSpacing(lineSpacing)
                        .foregroundStyle(theme.textColor(for: colorScheme, customText: Color(hex: customThemeTextHex)))
                        .padding(.horizontal, 4)
                        // See `ReaderView`'s matching change for why this stops at real selection
                        // (there was previously no way to copy text out of either reader) rather
                        // than also injecting a custom 净化/全文搜索/百科/网络搜索 menu -- that needs
                        // UIKit-level work this app can't risk shipping blind into a `ScrollView`'s
                        // gesture handling without a way to test it interactively.
                        .textSelection(.enabled)
                        .id(index)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
            }
        }
        .background(theme.backgroundColor(for: colorScheme, customBackground: Color(hex: customThemeBackgroundHex)))
        .overlay {
            if isEyeCareActive {
                Color(red: 1, green: 0.65, blue: 0.2)
                    .opacity(eyeCareIntensity * 0.35)
                    .allowsHitTesting(false)
            }
        }
        .onReceive(scheduleTimer) { scheduleTick = $0 }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                // Toggled by the "亮度" icon below, matching `ReaderView`'s equivalent (and the
                // reference reading app the user pointed at directly) -- not shown permanently.
                if isBrightnessVisible {
                    HStack(spacing: 12) {
                        Image(systemName: "sun.min")
                        Slider(value: $screenBrightness, in: 0...1)
                            .onChange(of: screenBrightness) { _, newValue in
                                UIScreen.main.brightness = CGFloat(newValue)
                            }
                        Image(systemName: "sun.max")
                    }
                }

                // Chapter-progress row -- prev/next chapter text flanking a real draggable seekbar
                // in paginated mode, same shape as `ReaderView`'s (see its own doc comment for why
                // `.scroll` mode stays text-only instead of a misleading approximate seekbar).
                HStack(spacing: 12) {
                    Button("上一章") { goTo(currentIndex - 1) }
                        .font(.caption)
                        .disabled(currentIndex <= 0)

                    if pageTurnStyle.isPaginated, let pagedPageProgress, pagedPageProgress.total > 1 {
                        Slider(
                            value: pageSeekBinding, in: 0...Double(pagedPageProgress.total - 1), step: 1,
                            onEditingChanged: { isEditing in
                                if !isEditing {
                                    if let pageSeekDragValue { pageJumpRequest = Int(pageSeekDragValue) }
                                    pageSeekDragValue = nil
                                }
                            }
                        )
                    } else {
                        Text(chapterProgressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }

                    Button("下一章") { goTo(currentIndex + 1) }
                        .font(.caption)
                        .disabled(currentIndex >= book.chapters.count - 1)
                }

                // Same inline-expanding-panel treatment as `ReaderView`'s "设置" icon -- see that
                // file's `inlineSettingsPanel` doc comment. Only 2 shortcuts here (not 4): this
                // reader has neither auto-scroll nor its own tap-zone grid yet, so there's nothing
                // real for "自动阅读"/"点击区域" shortcuts to open -- a fake button that opens
                // nothing would be worse than just not having it.
                if isSettingsPanelVisible {
                    inlineSettingsPanel
                }

                // Matches `ReaderView`'s primary row shape exactly: 目录/亮度/深色/设置. 书签
                // moved up to the top bar instead (see `.toolbar` below) since this reader has no
                // TOC entry point at all yet and gaining one here is worth more than keeping
                // bookmark in this row -- unlike `ReaderView`'s top bar, this one wasn't crowded
                // enough to need an overflow menu for it.
                HStack {
                    bottomFunctionButton(icon: "list.bullet", label: "目录") {
                        isShowingToc = true
                    }
                    Spacer()
                    bottomFunctionButton(icon: isBrightnessVisible ? "sun.max.fill" : "sun.max", label: "亮度") {
                        isBrightnessVisible.toggle()
                    }
                    Spacer()
                    bottomFunctionButton(icon: theme == .night ? "moon.fill" : "moon", label: "深色") {
                        theme = theme == .night ? .day : .night
                    }
                    Spacer()
                    bottomFunctionButton(icon: "gearshape", label: "设置") {
                        isSettingsPanelVisible.toggle()
                    }
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        // Matches `ReaderView`'s same fix -- without this, the main app's 书架/发现/订阅/我的 tab
        // bar stayed visible underneath this reader's own bottom chrome.
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await toggleBookmark() }
                } label: {
                    Image(systemName: isCurrentChapterBookmarked ? "bookmark.fill" : "bookmark")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isShowingContentSearch = true
                    } label: {
                        Label("搜索本书内", systemImage: "magnifyingglass")
                    }
                    Button {
                        isShowingAISummary = true
                    } label: {
                        Label("AI 摘要", systemImage: "sparkles")
                    }
                    Button {
                        isShowingDictLookup = true
                    } label: {
                        Label("查词", systemImage: "character.book.closed")
                    }
                    Button {
                        isShowingWebSearch = true
                    } label: {
                        Label("网页搜索", systemImage: "globe")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task(id: currentIndex) { await load() }
        .overlay {
            ReaderTocDrawerView(
                isPresented: $isShowingToc,
                chapters: book.chapters.indices.map { ReaderTocDrawerView.ChapterItem(id: $0, title: book.chapters[$0].title) },
                currentIndex: currentIndex,
                bookIdentifier: book.id,
                bookmarkStore: env.bookmarkStore,
                matchedReplaceRules: matchedReplaceRules,
                loadChaptersForSearch: {
                    book.chapters.enumerated().map { index, chapter in (index: index, title: chapter.title, text: chapter.text) }
                },
                onSelectChapter: { index in goTo(index) }
            )
        }
        .sheet(isPresented: $isShowingStyleSheet) {
            LocalReaderStyleSheet()
        }
        .sheet(isPresented: $isShowingMoreSettings) {
            LocalReaderMoreSettingsSheet()
        }
        .sheet(isPresented: $isShowingContentSearch) {
            ChapterContentSearchView(
                loadChapters: {
                    book.chapters.enumerated().map { index, chapter in (index: index, title: chapter.title, text: chapter.text) }
                },
                onSelect: { index in goTo(index) }
            )
        }
        .sheet(isPresented: $isShowingAISummary) {
            AIChapterSummaryView(chapterTitle: chapter.title, chapterText: purifiedText)
        }
        .sheet(isPresented: $isShowingDictLookup) {
            DictLookupView()
        }
        .sheet(isPresented: $isShowingWebSearch) {
            WebSearchPanelView()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepScreenOn
            startVolumeButtonPagingIfEnabled(proxy: scrollProxy)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            volumeButtonController.stop()
        }
        .onChange(of: keepScreenOn) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
        .onChange(of: volumeKeyPageEnabled) { _, isEnabled in
            if isEnabled {
                startVolumeButtonPagingIfEnabled(proxy: scrollProxy)
            } else {
                volumeButtonController.stop()
            }
        }
        .onChange(of: currentIndex) { _, _ in
            volumeScrollIndex = 0
            pagedPageProgress = nil
        }
        }
    }

    private func startVolumeButtonPagingIfEnabled(proxy: ScrollViewProxy) {
        guard volumeKeyPageEnabled else { return }
        guard let window = Self.keyWindow() else { return }
        volumeButtonController.onVolumeUp = { handleVolumeKeyTurn(direction: -1, proxy: proxy) }
        volumeButtonController.onVolumeDown = { handleVolumeKeyTurn(direction: 1, proxy: proxy) }
        volumeButtonController.start(in: window)
    }

    private func handleVolumeKeyTurn(direction: Int, proxy: ScrollViewProxy) {
        guard !pageTurnStyle.isPaginated else {
            pageTurnRequest = direction > 0 ? .next : .previous
            return
        }
        guard !paragraphs.isEmpty else { return }
        let step = 4
        volumeScrollIndex = min(max(volumeScrollIndex + direction * step, 0), paragraphs.count - 1)
        withAnimation {
            proxy.scrollTo(volumeScrollIndex, anchor: .top)
        }
    }

    /// Icon-over-label button, matching `ReaderView`'s equivalent -- see its doc comment for why
    /// (bare unlabeled icons were part of what made the previous chrome hard to use at a glance).
    @ViewBuilder
    private func bottomFunctionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption2)
            }
        }
    }

    private var inlineSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSwatchPicker(theme: $theme)

            HStack {
                Text("字号").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Stepper(value: $fontSize, in: 12...32, step: 1) {
                    Text("\(Int(fontSize))").font(.caption).monospacedDigit().frame(minWidth: 20)
                }
                .fixedSize()
            }
            HStack {
                Text("行距").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Stepper(value: $lineSpacing, in: 0...24, step: 1) {
                    Text("\(Int(lineSpacing))").font(.caption).monospacedDigit().frame(minWidth: 20)
                }
                .fixedSize()
            }

            Divider()

            HStack {
                settingsQuickLink(icon: "rectangle.on.rectangle", label: "翻页动画") {
                    isShowingStyleSheet = true
                }
                Spacer()
                settingsQuickLink(icon: "ellipsis", label: "更多") {
                    isShowingMoreSettings = true
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    private func settingsQuickLink(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.body)
                Text(label).font(.caption2)
            }
        }
    }

    private static func keyWindow() -> UIView? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    private func goTo(_ index: Int, anchor: PageAnchor = .first) {
        guard book.chapters.indices.contains(index) else { return }
        pageAnchor = anchor
        currentIndex = index
    }

    private func applyChineseConversion(_ text: String) -> String {
        switch chineseConversion {
        case .off: return text
        case .toTraditional: return ChineseTextConverter.convert(text, direction: .simplifiedToTraditional)
        case .toSimplified: return ChineseTextConverter.convert(text, direction: .traditionalToSimplified)
        }
    }

    private func load() async {
        let replaceRules = (try? await env.replaceRuleStore.enabled()) ?? []
        let purified = ReplaceRuleApplier.applyReportingMatches(replaceRules, to: chapter.text, sourceUrl: "")
        purifiedText = applyChineseConversion(purified.result)
        matchedReplaceRules = purified.matchedRules
        try? await env.localBookStore.updateProgress(id: book.id, chapterIndex: currentIndex)
        isCurrentChapterBookmarked = (try? await env.bookmarkStore.isBookmarked(
            bookIdentifier: book.id, chapterIndex: currentIndex
        )) ?? false
    }

    private func toggleBookmark() async {
        if isCurrentChapterBookmarked {
            try? await env.bookmarkStore.remove(bookIdentifier: book.id, chapterIndex: currentIndex)
            isCurrentChapterBookmarked = false
        } else {
            let bookmark = Bookmark(
                isLocal: true, bookIdentifier: book.id, bookTitle: book.title,
                chapterIndex: currentIndex, chapterTitle: chapter.title
            )
            try? await env.bookmarkStore.add(bookmark)
            isCurrentChapterBookmarked = true
        }
    }
}

/// "界面" -- matches `ReaderStyleSheet`'s split (theme/typography/page-turn-style only, see its
/// doc comment for why); `LocalReaderView` has no read-aloud button in this increment, so there's
/// no TTS section to omit differently from the network reader here.
struct LocalReaderStyleSheet: View {
    @AppStorage(ReaderSettingsKey.fontSize) private var fontSize: Double = 18
    @AppStorage(ReaderSettingsKey.lineSpacing) private var lineSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.paragraphSpacing) private var paragraphSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.theme) private var theme: ReaderTheme = .day
    @AppStorage(ReaderSettingsKey.pageTurnStyle) private var pageTurnStyle: PageTurnStyle = .scroll

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("主题") {
                    ThemeSwatchPicker(theme: $theme)
                    CustomThemeEditor(theme: $theme)
                }

                Section("翻页") {
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
}

/// "设置" -- matches `ReaderMoreSettingsSheet`'s split (everything not visual/typographic). Which
/// purification rules matched the current chapter lives only in the TOC drawer's own 净化规则 tab
/// now (see `ReaderMoreSettingsSheet`'s doc comment for why the old duplicate section here was
/// removed).
struct LocalReaderMoreSettingsSheet: View {
    @AppStorage(ReaderSettingsKey.keepScreenOn) private var keepScreenOn: Bool = true
    @AppStorage(ReaderSettingsKey.chineseConversion) private var chineseConversion: ChineseConversionMode = .off
    @AppStorage(ReaderSettingsKey.volumeKeyPage) private var volumeKeyPageEnabled: Bool = false
    @AppStorage(ReaderSettingsKey.eyeCareEnabled) private var eyeCareEnabled: Bool = false
    @AppStorage(ReaderSettingsKey.eyeCareIntensity) private var eyeCareIntensity: Double = 0.35
    @AppStorage(ReaderSettingsKey.eyeCareScheduleEnabled) private var eyeCareScheduleEnabled: Bool = false
    @AppStorage(ReaderSettingsKey.eyeCareScheduleStartHour) private var eyeCareScheduleStartHour: Int = 20
    @AppStorage(ReaderSettingsKey.eyeCareScheduleEndHour) private var eyeCareScheduleEndHour: Int = 6

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        LocalReaderStyleSheet()
                    } label: {
                        Label("界面（主题/字体/翻页动画）", systemImage: "textformat.size")
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
                }
            }
            .navigationTitle("设置")
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
