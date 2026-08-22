import SwiftUI
import UIKit
import BookSourceModel
import WebBookOrchestrator
import Persistence

/// Same idea as `ReaderView`'s `ParagraphTopOffsetKey`, kept as a separate type (not shared) since
/// the two readers' coordinate spaces are named differently and there's no other reason to couple
/// them.
private struct LocalParagraphTopOffsetKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Reader for a locally-imported .txt book. Deliberately simpler than `ReaderView`: no network
/// fetch (all chapter text is already in `book.chapters`), no read-aloud/TTS in this first
/// increment. Shares its typography/theme `@AppStorage` keys with `ReaderView` so font size and
/// theme choice carry over between network and local books rather than needing to be set twice.
/// Deliberately does *not* get `ReaderView`'s new continuous-chapter-connection feature (chapters
/// visually flowing into each other while scrolling) -- local books have no auto-advance/bottom-
/// sentinel mechanism to begin with, and building that pairing twice in one pass (once for the
/// network reader, which needed an async fetch+purify preview step; once here, which wouldn't) was
/// more risk than this batch of fixes could responsibly take on at once. Real reading-position
/// tracking (item 7) and page margins/paragraph indent (item 2) are still fully implemented here.
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
    // See `ReaderView`'s matching properties -- same custom long-press paragraph menu, mirrored here
    // (`localParagraphContextMenuItems`) since nothing about the reasoning that made `.contextMenu`
    // safe for `ReaderView` (a SwiftUI-native primitive, not a UIKit gesture bolted on) is specific
    // to that reader -- if anything this one's simpler: local scroll mode renders straight from
    // `paragraphs`, with no `ChapterPageLayout`/neighboring-chapter-preview slot to ever confuse a
    // long-pressed paragraph's chapter with, so there's no `isCurrentChapter`-style gating needed.
    @State private var paragraphMenuText = ""
    @State private var isShowingReplaceRuleSeed = false
    @State private var isShowingParagraphShareSheet = false
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
    @AppStorage(ReaderSettingsKey.screenOrientationLock) private var screenOrientationLock: ReaderOrientationLock = .followSystem
    @AppStorage(ReaderSettingsKey.progressBarBehavior) private var progressBarBehavior: ProgressBarBehavior = .page
    @State private var pageAnchor: PageAnchor = .first
    @State private var pageTurnRequest: PageTurnRequest?
    @State private var pageJumpRequest: Int?
    @State private var pagedPageProgress: (current: Int, total: Int)?
    @State private var pageSeekDragValue: Double?
    // See `ReaderView`'s matching properties for the full reasoning (`.chapter` progress-bar mode).
    @State private var chapterSeekDragValue: Double?
    @State private var hasConfirmedChapterJumpThisSession = false
    @State private var pendingChapterJumpIndex: Int?
    @State private var scheduleTick = Date()
    private let scheduleTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    /// See `ReaderView`'s matching properties for the full reasoning -- same real-usage-feedback fix
    /// (reopening a book always landed at the *start* of the last-read chapter, never the exact
    /// spot), same mechanism, scoped to `.scroll` mode only.
    @State private var pendingResumeCharacterOffset: Int?
    @State private var pendingScrollToParagraph: Int?
    @State private var currentTopParagraphIndex = 0

    @AppStorage(ReaderSettingsKey.pageMarginTop) private var pageMarginTop: Double = 16
    @AppStorage(ReaderSettingsKey.pageMarginBottom) private var pageMarginBottom: Double = 16
    @AppStorage(ReaderSettingsKey.pageMarginLeading) private var pageMarginLeading: Double = 16
    @AppStorage(ReaderSettingsKey.pageMarginTrailing) private var pageMarginTrailing: Double = 16
    @AppStorage(ReaderSettingsKey.paragraphIndent) private var paragraphIndent: Int = 2

    private var isEyeCareActive: Bool {
        eyeCareEnabled || (eyeCareScheduleEnabled && EyeCareSchedule.isActive(
            startHour: eyeCareScheduleStartHour, endHour: eyeCareScheduleEndHour, now: scheduleTick
        ))
    }

    /// `startChapterIndex` overrides the book's own last-read position -- used when jumping in from
    /// a bookmark, which names an exact chapter rather than "wherever I left off." `startCharacterOffset`
    /// carries a bookmark's own `Bookmark.characterOffset` (distinct from the book's last-read
    /// position below) so a bookmark saved mid-chapter lands on its exact spot, not the chapter's
    /// first paragraph. `startWithTocOpen` exists purely for CI's screenshot workflow (see
    /// `RootView`'s `-uiTestingScreen localReaderToc`) -- there's no other way to get a screenshot of
    /// the drawer actually open, since CI can't tap anything.
    init(book: LocalBook, startChapterIndex: Int? = nil, startCharacterOffset: Int? = nil, startWithTocOpen: Bool = false) {
        self.book = book
        let fallback = book.lastReadChapterIndex.flatMap { book.chapters.indices.contains($0) ? $0 : nil } ?? 0
        let start = startChapterIndex.flatMap { book.chapters.indices.contains($0) ? $0 : nil } ?? fallback
        self._currentIndex = State(initialValue: start)
        self._isShowingToc = State(initialValue: startWithTocOpen)
        if let startCharacterOffset, startCharacterOffset > 0 {
            self._pendingResumeCharacterOffset = State(initialValue: startCharacterOffset)
        } else if startChapterIndex == nil, book.lastReadChapterIndex == start, let offset = book.lastReadCharacterOffset, offset > 0 {
            // Only resume to a saved mid-chapter position when actually landing on the book's own
            // last-read chapter via the natural fallback path -- an explicit `startChapterIndex` (e.g.
            // a bookmark jump with no offset of its own) means "start this specific chapter from the
            // top," not "continue where I left off," even if that happens to be the same chapter index.
            self._pendingResumeCharacterOffset = State(initialValue: offset)
        }
    }

    private var chapter: LocalChapter { book.chapters[currentIndex] }
    private var paragraphs: [String] { purifiedText.components(separatedBy: "\n") }
    @State private var purifiedText: String = ""

    /// See `ReaderView.indentedText`'s matching doc comment -- including why leading whitespace is
    /// stripped before reapplying `paragraphIndent`. Same risk applies here via a different route:
    /// local `.txt` novels commonly already have "　　" manually typed at the start of every
    /// paragraph in the raw file itself (the traditional plain-text convention), which would
    /// otherwise stack with this setting's own indent instead of being controlled by it.
    private func indentedText(_ paragraph: String) -> Text {
        let normalized = String(paragraph.drop(while: \.isWhitespace))
        guard paragraphIndent > 0 else { return Text(normalized) }
        return Text(String(repeating: "　", count: paragraphIndent) + normalized)
    }

    /// See `ReaderView.chapterHeading`'s matching doc comment -- same real usage feedback applies
    /// here regardless of reader type.
    private func chapterHeading(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(theme.textColor(for: colorScheme, customText: Color(hex: customThemeTextHex)))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
            .padding(.bottom, 12)
            .padding(.horizontal, 4)
    }

    private var chapterProgressText: String {
        let chapterPart = "第 \(currentIndex + 1) / \(book.chapters.count) 章"
        if pageTurnStyle.isPaginated, let pagedPageProgress {
            return "\(chapterPart) · 第 \(pagedPageProgress.current) / \(pagedPageProgress.total) 页 · \(wholeBookProgressText)"
        }
        return "\(chapterPart) · \(wholeBookProgressText)"
    }

    /// See `ReaderView.wholeBookProgressText`'s doc comment for the formula and its Legado source.
    /// `.scroll` mode here has no page concept (this view still scrolls by raw paragraph position,
    /// not the pixel-offset/page-layout model `ReaderView` was rewritten to use) -- `paragraphs.count`
    /// / `currentTopParagraphIndex` stand in for `pageSize`/`pageIndex` as the closest equivalent
    /// "how far into this chapter" fraction available here.
    private var wholeBookProgressText: String {
        let chapterSize = book.chapters.count
        guard chapterSize > 0 else { return "0.0%" }
        let pageIndex: Int
        let pageSize: Int
        if pageTurnStyle.isPaginated, let pagedPageProgress {
            pageIndex = pagedPageProgress.current - 1
            pageSize = pagedPageProgress.total
        } else if !paragraphs.isEmpty {
            pageIndex = currentTopParagraphIndex
            pageSize = paragraphs.count
        } else {
            pageIndex = 0
            pageSize = 0
        }
        guard pageSize > 0 else {
            return String(format: "%.1f%%", Double(currentIndex + 1) / Double(chapterSize) * 100)
        }
        let percent = Double(currentIndex) / Double(chapterSize)
            + (1 / Double(chapterSize)) * Double(pageIndex + 1) / Double(pageSize)
        let formatted = String(format: "%.1f%%", percent * 100)
        let isTrulyLast = currentIndex + 1 == chapterSize && pageIndex + 1 == pageSize
        return (formatted == "100.0%" && !isTrulyLast) ? "99.9%" : formatted
    }

    private var pageSeekBinding: Binding<Double> {
        Binding(
            get: { pageSeekDragValue ?? Double((pagedPageProgress?.current ?? 1) - 1) },
            set: { pageSeekDragValue = $0 }
        )
    }

    private var chapterSeekBinding: Binding<Double> {
        Binding(
            get: { chapterSeekDragValue ?? Double(currentIndex) },
            set: { chapterSeekDragValue = $0 }
        )
    }

    /// See `ReaderView`'s matching properties -- same fix for the same CI-only ("the compiler is
    /// unable to type-check this expression in reasonable time") failure.
    private var showsChapterSeekbar: Bool {
        progressBarBehavior == .chapter && book.chapters.count > 1
    }

    private var showsPageSeekbar: Bool {
        guard progressBarBehavior == .page, pageTurnStyle.isPaginated, let pagedPageProgress else { return false }
        return pagedPageProgress.total > 1
    }

    private var chapterSeekbar: some View {
        Slider(
            value: chapterSeekBinding, in: 0...Double(book.chapters.count - 1), step: 1,
            onEditingChanged: { isEditing in
                if !isEditing {
                    if let chapterSeekDragValue { requestChapterJump(to: Int(chapterSeekDragValue)) }
                    chapterSeekDragValue = nil
                }
            }
        )
    }

    private var pageSeekbar: some View {
        Slider(
            value: pageSeekBinding, in: 0...Double((pagedPageProgress?.total ?? 1) - 1), step: 1,
            onEditingChanged: { isEditing in
                if !isEditing {
                    if let pageSeekDragValue { pageJumpRequest = Int(pageSeekDragValue) }
                    pageSeekDragValue = nil
                }
            }
        )
    }

    /// See `ReaderView.requestChapterJump`'s doc comment.
    private func requestChapterJump(to index: Int) {
        guard book.chapters.indices.contains(index), index != currentIndex else { return }
        if hasConfirmedChapterJumpThisSession {
            goTo(index)
        } else {
            pendingChapterJumpIndex = index
        }
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
                chapterHeading(chapter.title)
                    .id(-1)

                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    indentedText(paragraph)
                        .font(.system(size: fontSize))
                        .lineSpacing(lineSpacing)
                        .foregroundStyle(theme.textColor(for: colorScheme, customText: Color(hex: customThemeTextHex)))
                        .padding(.horizontal, 4)
                        // See `ReaderView.pageBlock`'s matching `.contextMenu` doc comment -- same
                        // custom long-press menu, replacing the plain system Copy/Look Up/Share menu
                        // `.textSelection(.enabled)` used to show here.
                        .contextMenu {
                            localParagraphContextMenuItems(index: index, text: paragraph)
                        }
                        .id(index)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: LocalParagraphTopOffsetKey.self,
                                    value: [index: geo.frame(in: .named("localReaderScroll")).minY]
                                )
                            }
                        )
                }
            }
            .padding(EdgeInsets(top: pageMarginTop, leading: pageMarginLeading, bottom: pageMarginBottom, trailing: pageMarginTrailing))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .coordinateSpace(name: "localReaderScroll")
        .onPreferenceChange(LocalParagraphTopOffsetKey.self) { offsets in
            if let closest = offsets.min(by: { abs($0.value) < abs($1.value) }) {
                currentTopParagraphIndex = closest.key
            }
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
        .onReceive(scheduleTimer) { scheduleTick = $0; saveReadingProgress() }
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
                HStack(spacing: 4) {
                    Button("上一章") { goTo(currentIndex - 1) }
                        .font(.caption)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                        .disabled(currentIndex <= 0)

                    if showsChapterSeekbar {
                        chapterSeekbar
                    } else if showsPageSeekbar {
                        pageSeekbar
                    } else {
                        Text(chapterProgressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }

                    Button("下一章") { goTo(currentIndex + 1) }
                        .font(.caption)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
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
                        paragraphMenuText = ""
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
                        paragraphMenuText = ""
                        isShowingDictLookup = true
                    } label: {
                        Label("查词", systemImage: "character.book.closed")
                    }
                    Button {
                        paragraphMenuText = ""
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
                onSelectChapter: { index, offset in
                    if let offset, offset > 0 { pendingResumeCharacterOffset = offset }
                    goTo(index)
                }
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
                onSelect: { index in goTo(index) },
                initialKeyword: paragraphMenuText
            )
        }
        .sheet(isPresented: $isShowingAISummary) {
            AIChapterSummaryView(chapterTitle: chapter.title, chapterText: purifiedText)
        }
        .sheet(isPresented: $isShowingDictLookup) {
            DictLookupView(initialWord: paragraphMenuText)
        }
        .sheet(isPresented: $isShowingWebSearch) {
            WebSearchPanelView(initialQuery: paragraphMenuText)
        }
        .sheet(isPresented: $isShowingReplaceRuleSeed) {
            // See `ReaderView`'s matching sheet's doc comment for why `rule:` is non-nil (seeds the
            // form) yet `onSave` still goes through `.add`, not `.update`.
            ReplaceRuleEditView(rule: ReplaceRule(name: "", pattern: paragraphMenuText, isRegex: false)) { newRule in
                Task { try? await env.replaceRuleStore.add(newRule) }
            }
        }
        .sheet(isPresented: $isShowingParagraphShareSheet) {
            ShareSheet(items: [paragraphMenuText])
        }
        .alert(
            "章节跳转确认", isPresented: Binding(get: { pendingChapterJumpIndex != nil }, set: { if !$0 { pendingChapterJumpIndex = nil } })
        ) {
            Button("取消", role: .cancel) { pendingChapterJumpIndex = nil }
            Button("确定") {
                if let index = pendingChapterJumpIndex {
                    hasConfirmedChapterJumpThisSession = true
                    goTo(index)
                }
                pendingChapterJumpIndex = nil
            }
        } message: {
            Text("确定要跳转章节吗？")
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepScreenOn
            startVolumeButtonPagingIfEnabled(proxy: scrollProxy)
            OrientationLock.mask = screenOrientationLock.mask
            OrientationLock.applyToActiveScene()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            volumeButtonController.stop()
            saveReadingProgress()
            OrientationLock.mask = .allButUpsideDown
            OrientationLock.applyToActiveScene()
        }
        .onChange(of: keepScreenOn) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
        .onChange(of: screenOrientationLock) { _, newValue in
            OrientationLock.mask = newValue.mask
            OrientationLock.applyToActiveScene()
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
            // See `ReaderView`'s matching fix for why this works despite firing before the new
            // chapter's content has rendered -- `ScrollView` position is a raw offset, not tied to
            // which content is currently showing.
            if !pageTurnStyle.isPaginated {
                withAnimation(nil) {
                    // -1 is the chapter heading's id, not paragraph 0 -- see `ReaderView`'s matching
                    // comment.
                    scrollProxy.scrollTo(-1, anchor: .top)
                }
            }
        }
        .onChange(of: purifiedText) { _, _ in
            // Resuming mid-chapter (see `init`'s doc comment) -- picked up once `purifiedText`
            // actually updates (guaranteed to fire after `load()` sets it), unlike `ReaderView`
            // there's no `isLoading` flag here to hook since a local book's `load()` has no network
            // wait to speak of.
            guard let target = pendingScrollToParagraph else { return }
            pendingScrollToParagraph = nil
            guard !pageTurnStyle.isPaginated else { return }
            DispatchQueue.main.async {
                withAnimation(nil) {
                    scrollProxy.scrollTo(target, anchor: .top)
                }
            }
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
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
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
            HStack {
                Text("段距").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Stepper(value: $paragraphSpacing, in: 0...32, step: 1) {
                    Text("\(Int(paragraphSpacing))").font(.caption).monospacedDigit().frame(minWidth: 20)
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
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
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
        let purified = ReplaceRuleApplier.applyReportingMatches(replaceRules, to: chapter.text, bookName: book.title, sourceUrl: "")
        purifiedText = applyChineseConversion(purified.result)
        matchedReplaceRules = purified.matchedRules
        try? await env.localBookStore.updateProgress(id: book.id, chapterIndex: currentIndex)
        isCurrentChapterBookmarked = (try? await env.bookmarkStore.isBookmarked(
            bookIdentifier: book.id, chapterIndex: currentIndex
        )) ?? false
        if let offset = pendingResumeCharacterOffset {
            pendingResumeCharacterOffset = nil
            pendingScrollToParagraph = paragraphIndex(forCharacterOffset: offset)
        }
    }

    private func characterOffset(forParagraphIndex index: Int) -> Int {
        guard index > 0, index <= paragraphs.count else { return 0 }
        return paragraphs.prefix(index).reduce(0) { $0 + $1.count + 1 }
    }

    private func paragraphIndex(forCharacterOffset offset: Int) -> Int {
        guard offset > 0, !paragraphs.isEmpty else { return 0 }
        var accumulated = 0
        for (index, paragraph) in paragraphs.enumerated() {
            accumulated += paragraph.count + 1
            if accumulated > offset { return index }
        }
        return max(0, paragraphs.count - 1)
    }

    /// See `ReaderView.saveReadingProgress`'s matching doc comment.
    private func saveReadingProgress() {
        guard !pageTurnStyle.isPaginated else { return }
        let offset = characterOffset(forParagraphIndex: currentTopParagraphIndex)
        Task {
            try? await env.localBookStore.updateProgress(id: book.id, chapterIndex: currentIndex, characterOffset: offset)
        }
    }

    private func toggleBookmark() async {
        if isCurrentChapterBookmarked {
            try? await env.bookmarkStore.remove(bookIdentifier: book.id, chapterIndex: currentIndex)
            isCurrentChapterBookmarked = false
        } else {
            let offset: Int? = pageTurnStyle.isPaginated ? nil : characterOffset(forParagraphIndex: currentTopParagraphIndex)
            let excerpt = paragraphs.indices.contains(currentTopParagraphIndex)
                ? Bookmark.makeExcerpt(from: paragraphs[currentTopParagraphIndex]) : nil
            let bookmark = Bookmark(
                isLocal: true, bookIdentifier: book.id, bookTitle: book.title,
                chapterIndex: currentIndex, chapterTitle: chapter.title, characterOffset: offset, excerpt: excerpt
            )
            try? await env.bookmarkStore.add(bookmark)
            isCurrentChapterBookmarked = true
        }
    }

    /// The custom long-press menu's items -- see `ReaderView.paragraphContextMenuItems`'s doc
    /// comment for the overall reasoning. No "朗读，从这里开始" here: this reader has no read-aloud
    /// feature at all (see `LocalReaderMoreSettingsSheet`'s doc comment).
    @ViewBuilder
    private func localParagraphContextMenuItems(index: Int, text: String) -> some View {
        Button {
            UIPasteboard.general.string = text
        } label: {
            Label("复制", systemImage: "doc.on.doc")
        }
        Button {
            paragraphMenuText = text
            isShowingParagraphShareSheet = true
        } label: {
            Label("分享", systemImage: "square.and.arrow.up")
        }
        Button {
            addBookmark(forParagraphIndex: index)
        } label: {
            Label("添加书签", systemImage: "bookmark")
        }
        Button {
            paragraphMenuText = text
            isShowingDictLookup = true
        } label: {
            Label("查词典", systemImage: "character.book.closed")
        }
        Button {
            paragraphMenuText = text
            isShowingContentSearch = true
        } label: {
            Label("搜索本书", systemImage: "magnifyingglass")
        }
        Button {
            paragraphMenuText = text
            isShowingWebSearch = true
        } label: {
            Label("网络搜索", systemImage: "globe")
        }
        Button {
            paragraphMenuText = text
            isShowingReplaceRuleSeed = true
        } label: {
            Label("新建净化规则", systemImage: "wand.and.stars")
        }
    }

    /// Always adds a fresh bookmark (matching Legado's `menu_bookmark` -- see `ReaderView.
    /// addBookmark(forParagraph:)`'s matching doc comment), independent of `toggleBookmark`'s
    /// current-top-of-screen-paragraph toggle.
    private func addBookmark(forParagraphIndex index: Int) {
        let excerpt = paragraphs.indices.contains(index) ? Bookmark.makeExcerpt(from: paragraphs[index]) : nil
        let bookmark = Bookmark(
            isLocal: true, bookIdentifier: book.id, bookTitle: book.title,
            chapterIndex: currentIndex, chapterTitle: chapter.title,
            characterOffset: characterOffset(forParagraphIndex: index), excerpt: excerpt
        )
        Task {
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
                    Stepper("首行缩进（段落缩进）: \(paragraphIndent) 字符", value: $paragraphIndent, in: 0...4)
                }

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
    @AppStorage(ReaderSettingsKey.screenOrientationLock) private var screenOrientationLock: ReaderOrientationLock = .followSystem
    @AppStorage(ReaderSettingsKey.progressBarBehavior) private var progressBarBehavior: ProgressBarBehavior = .page

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

                Section {
                    Picker("屏幕方向", selection: $screenOrientationLock) {
                        ForEach(ReaderOrientationLock.allCases) { lock in
                            Text(lock.displayName).tag(lock)
                        }
                    }
                } footer: {
                    Text("仅在阅读界面生效，退出阅读后恢复跟随系统。")
                }

                Section {
                    Picker("进度条拖动", selection: $progressBarBehavior) {
                        ForEach(ProgressBarBehavior.allCases) { behavior in
                            Text(behavior.displayName).tag(behavior)
                        }
                    }
                } footer: {
                    Text("章节跳转：拖动进度条直接跳到本书的任意一章，松手前会先确认一次（每次进入阅读界面只确认一次）。")
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
