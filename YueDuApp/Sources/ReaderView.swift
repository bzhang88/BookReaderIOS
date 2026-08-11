import SwiftUI
import UIKit
import BookSourceModel
import WebBookOrchestrator
import Persistence

struct ReaderView: View {
    // These start as constructor params but can change in place when the user switches source
    // mid-read (see `switchSource`) -- kept as @State rather than the `let`s this started as so the
    // reader itself can adopt a new source/book/chapter-list without popping back and re-pushing a
    // whole new ReaderView (which would need a shared NavigationPath this view doesn't have access
    // to, given how deeply it's already nested under Shelf/Toc navigation).
    @State private var source: BookSource
    @State private var bookUrl: String
    @State private var tocUrl: String
    @State private var chapters: [BookChapter]
    @State private var bookTitle: String
    @State private var currentIndex: Int

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingStyleSheet = false
    @State private var isShowingMoreSettings = false
    @State private var isShowingChangeSource = false
    @State private var isShowingChapterSourceSwitch = false
    @State private var isShowingToc = false
    @State private var isShowingContentSearch = false
    @State private var isShowingAISummary = false
    @State private var isShowingDictLookup = false
    @State private var isShowingContentEdit = false
    @State private var isShowingWebSearch = false
    @State private var isShowingReplaceRules = false
    @State private var isChromeVisible = true
    // Brightness is a toggleable quick-access row (tap the "亮度" icon to reveal/hide it), not a
    // permanently-visible slider -- matches the reference reading app the user pointed at directly
    // (a slider taking up a full row at all times, whether or not anyone's about to touch it, was
    // part of what made the previous chrome feel cluttered).
    @State private var isBrightnessVisible = false
    // Guards auto-advance so a chapter that's short enough to fit on screen without scrolling
    // doesn't fire the moment it loads (the bottom sentinel would already be within the visible
    // scroll bounds from the very first layout pass, before the user has read anything) -- reset
    // to false on every chapter change, flips true after a short grace period.
    @State private var canAutoAdvance = false
    @State private var isCurrentChapterBookmarked = false
    @State private var matchedReplaceRules: [ReplaceRule] = []
    @State private var screenBrightness: Double = Double(UIScreen.main.brightness)
    @State private var highlightRules: [HighlightRule] = []
    @State private var isAutoScrolling = false
    @State private var autoScrollTask: Task<Void, Never>?
    @StateObject private var readAloud = ReadAloudController()
    @StateObject private var httpReadAloud = HttpReadAloudController()
    @State private var httpTTSEngines: [HttpTTSEngine] = []
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(ReaderSettingsKey.fontSize) private var fontSize: Double = 18
    @AppStorage(ReaderSettingsKey.lineSpacing) private var lineSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.paragraphSpacing) private var paragraphSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.theme) private var theme: ReaderTheme = .day
    @AppStorage(ReaderSettingsKey.keepScreenOn) private var keepScreenOn: Bool = true
    @AppStorage(ReaderSettingsKey.readAloudRate) private var readAloudRate: Double = 0.5
    @AppStorage(ReaderSettingsKey.chineseConversion) private var chineseConversion: ChineseConversionMode = .off
    @AppStorage(ReaderSettingsKey.autoScrollInterval) private var autoScrollInterval: Double = 3.0
    @AppStorage(ReaderSettingsKey.tapZoneGrid) private var tapZoneGridRaw: String = ReaderTapZoneGrid.standardEncoded
    @AppStorage(ReaderSettingsKey.volumeKeyPage) private var volumeKeyPageEnabled: Bool = false
    @State private var volumeButtonController = VolumeButtonPageTurnController()
    // Not real character/pixel scroll position -- a simple step counter over paragraph indices,
    // same "honest approximation" the auto-scroll feature already uses (see its own doc comment).
    // Resets to 0 on every chapter change.
    @State private var volumeScrollIndex = 0
    @AppStorage(ReaderSettingsKey.eyeCareEnabled) private var eyeCareEnabled: Bool = false
    @AppStorage(ReaderSettingsKey.eyeCareIntensity) private var eyeCareIntensity: Double = 0.35
    @AppStorage(ReaderSettingsKey.eyeCareScheduleEnabled) private var eyeCareScheduleEnabled: Bool = false
    @AppStorage(ReaderSettingsKey.eyeCareScheduleStartHour) private var eyeCareScheduleStartHour: Int = 20
    @AppStorage(ReaderSettingsKey.eyeCareScheduleEndHour) private var eyeCareScheduleEndHour: Int = 6
    @AppStorage(ReaderSettingsKey.touchSlop) private var touchSlop: Double = 50
    @AppStorage(ReaderSettingsKey.selectedHttpTTSEngineID) private var selectedHttpTTSEngineID: String = ""
    @AppStorage(ReaderSettingsKey.customThemeBackgroundHex) private var customThemeBackgroundHex: String = "#FFFFFF"
    @AppStorage(ReaderSettingsKey.customThemeTextHex) private var customThemeTextHex: String = "#0D0D0D"
    @AppStorage(ReaderSettingsKey.pageTurnStyle) private var pageTurnStyle: PageTurnStyle = .scroll
    // Only ever set to `.last` right before `goTo` steps backward across a paginated chapter's
    // boundary (see `goTo`'s doc comment) -- every other navigation path defaults back to `.first`.
    @State private var pageAnchor: PageAnchor = .first
    @State private var pageTurnRequest: PageTurnRequest?
    @State private var pageJumpRequest: Int?
    @State private var pagedPageProgress: (current: Int, total: Int)?
    // Local override while the user is actively dragging the progress seekbar -- lets the slider
    // show the finger's live position instead of snapping back to the real page on every tiny
    // movement; cleared (reverting to tracking `pagedPageProgress` again) once the drag ends and
    // `pageJumpRequest` has been sent.
    @State private var pageSeekDragValue: Double?
    @State private var isAutoPaging = false
    @State private var autoPageTask: Task<Void, Never>?
    // Re-evaluated every minute so a schedule-only filter actually turns on/off while the reader
    // stays open across the boundary, not just whenever the view happens to redraw for other reasons.
    @State private var scheduleTick = Date()
    private let scheduleTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var isEyeCareActive: Bool {
        eyeCareEnabled || (eyeCareScheduleEnabled && EyeCareSchedule.isActive(
            startHour: eyeCareScheduleStartHour, endHour: eyeCareScheduleEndHour, now: scheduleTick
        ))
    }

    init(source: BookSource, bookUrl: String, tocUrl: String, chapters: [BookChapter], currentIndex: Int, bookTitle: String) {
        self._source = State(initialValue: source)
        self._bookUrl = State(initialValue: bookUrl)
        self._tocUrl = State(initialValue: tocUrl)
        self._chapters = State(initialValue: chapters)
        self._bookTitle = State(initialValue: bookTitle)
        self._currentIndex = State(initialValue: currentIndex)
    }

    private var chapter: BookChapter { chapters[currentIndex] }
    private var paragraphs: [String] { text.components(separatedBy: "\n") }

    private var chapterProgressText: String {
        let chapterPart = "第 \(currentIndex + 1) / \(chapters.count) 章"
        guard pageTurnStyle.isPaginated, let pagedPageProgress else { return chapterPart }
        return "\(chapterPart) · 第 \(pagedPageProgress.current) / \(pagedPageProgress.total) 页"
    }

    /// Drives the paginated-mode progress seekbar -- while a drag is in flight, shows the finger's
    /// live position (`pageSeekDragValue`) instead of the real current page, so the slider doesn't
    /// fight the user's touch; reverts to tracking `pagedPageProgress` once the drag ends and the
    /// actual jump (`pageJumpRequest`) has been sent. Matches Legado's real "page" progress-bar
    /// mode: jump immediately on release, no confirmation (confirmed via `ReadMenu.kt` research).
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
                    text: text,
                    style: pageTurnStyle,
                    fontSize: fontSize,
                    lineSpacing: lineSpacing,
                    paragraphSpacing: paragraphSpacing,
                    textColor: theme.textColor(for: colorScheme, customText: Color(hex: customThemeTextHex)),
                    backgroundColor: theme.backgroundColor(for: colorScheme, customBackground: Color(hex: customThemeBackgroundHex)),
                    highlightRules: highlightRules,
                    readAloudParagraphIndex: isReadAloudSpeaking ? readAloudCurrentParagraphIndex : nil,
                    initialAnchor: pageAnchor,
                    pageTurnRequest: $pageTurnRequest,
                    pageJumpRequest: $pageJumpRequest,
                    touchSlop: touchSlop,
                    onTapMiddle: { isChromeVisible.toggle() },
                    onRequestPreviousChapter: { goTo(currentIndex - 1, anchor: .last) },
                    onRequestNextChapter: { goTo(currentIndex + 1) },
                    onPageChanged: { current, total in pagedPageProgress = (current, total) }
                )
            } else {
        ScrollView {
            VStack(alignment: .leading, spacing: paragraphSpacing) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    highlightedText(paragraph)
                        .font(.system(size: fontSize))
                        .lineSpacing(lineSpacing)
                        .padding(.horizontal, 4)
                        .background(
                            isReadAloudSpeaking && index == readAloudCurrentParagraphIndex
                                ? Color.accentColor.opacity(0.15) : Color.clear
                        )
                        .id(index)
                }
                // Invisible sentinel below the last paragraph -- its appearance means the user has
                // scrolled (or the chapter was short enough to start fully visible) to the bottom.
                // Real-device feedback specifically asked for chapters to "just connect" without an
                // explicit tap, matching this rather than a full continuous multi-chapter scroll
                // buffer, which would need a much larger rewrite of how content is rendered.
                Color.clear
                    .frame(height: 1)
                    .onAppear { attemptAutoAdvance() }
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height, alignment: .topLeading)
            .contentShape(Rectangle())
            // A zero-distance DragGesture rather than .onTapGesture -- SwiftUI's plain tap gesture
            // doesn't expose *where* the tap landed, and the 3x3 zone grid needs that location to
            // pick which of the 9 regions was hit (see `handleTap`). `touchSlop` filters out
            // releases too far from where the finger went down -- a scroll attempt that only moved
            // a little shouldn't also register as a tap-zone tap.
            //
            // `.simultaneousGesture`, not `.gesture` -- a plain `.gesture(DragGesture(minimumDistance:
            // 0))` on content *inside* a `ScrollView` can win the touch outright and starve the
            // ScrollView's own built-in pan/scroll gesture of it, which reads as "scrolling just
            // doesn't work" (real-device feedback: the page never moves at all in `.scroll` mode).
            // `.simultaneousGesture` lets both this tap-zone recognizer and the ScrollView's native
            // scrolling see the same touch instead of one exclusively claiming it.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard hypot(value.translation.width, value.translation.height) <= touchSlop else { return }
                        handleTap(at: value.location)
                    }
            )
        }
            }
        }
        .background(theme.backgroundColor(for: colorScheme, customBackground: Color(hex: customThemeBackgroundHex)))
        .overlay {
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            }
        }
        // A warm, hit-testing-disabled tint layered on top of whichever theme is active -- eye
        // care is a filter you can combine with any theme, not a theme choice of its own.
        .overlay {
            if isEyeCareActive {
                Color(red: 1, green: 0.65, blue: 0.2)
                    .opacity(eyeCareIntensity * 0.35)
                    .allowsHitTesting(false)
            }
        }
        // Floating quick-access read-aloud button -- matches the reference reading app's own
        // small circular "听" button, sitting just above the bottom bar rather than making 朗读
        // compete for one of the 4 primary bottom-row icon slots. Only shown alongside the rest of
        // the chrome (not in the fully-hidden minimal-footer state) and hidden while already
        // speaking, since the read-aloud controls row already covers play/pause/stop then.
        .overlay(alignment: .bottomTrailing) {
            if isChromeVisible && !isReadAloudSpeaking {
                Button {
                    startOrStopReadAloud()
                } label: {
                    Image(systemName: "headphones")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Color.accentColor, in: Circle())
                        .shadow(radius: 3, y: 1)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 8)
            }
        }
        .onReceive(scheduleTimer) { scheduleTick = $0 }
        // `.overlay`, not `.safeAreaInset` -- real usage feedback: opening/closing the menu was
        // visibly shifting where the text sat on screen, because `.safeAreaInset` *reserves* space
        // for its content, shrinking the reading area (and reflowing every line in it) every time
        // the menu toggled. An overlay draws on top of the reading area without changing its size at
        // all -- the menu can cover the last few lines of text while it's open, which is fine, but
        // the lines that stay visible never move. Paired with the matching `.overlay(alignment:
        // .top)` fix above for the same reason on the top bar.
        .overlay(alignment: .bottom) {
            if isChromeVisible {
                VStack(spacing: 10) {
                    // Toggled by the "亮度" icon below, not shown permanently -- matches the
                    // reference reading app the user pointed at directly (a screenshot of its menu
                    // has no always-on brightness row; brightness is one of the 4 primary icons and
                    // only reveals a slider on demand).
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

                    if isReadAloudSpeaking {
                        HStack(spacing: 20) {
                            Button {
                                readAloudPreviousParagraph()
                            } label: {
                                Image(systemName: "backward.end")
                            }
                            Button {
                                toggleReadAloudPause()
                            } label: {
                                Image(systemName: isReadAloudPaused ? "play.fill" : "pause.fill")
                            }
                            Button {
                                readAloudNextParagraph()
                            } label: {
                                Image(systemName: "forward.end")
                            }
                            Button(role: .destructive) {
                                stopReadAloud()
                            } label: {
                                Image(systemName: "stop.fill")
                            }
                        }
                        .font(.title3)
                    }

                    // Chapter-progress row -- prev/next chapter text flanking a real draggable
                    // seekbar in paginated mode, matching the reference app's own prominent
                    // progress bar in this exact position (jumps immediately on release, no
                    // confirmation). `.scroll` mode has no equivalent accurate position to seek
                    // (there's nowhere this reader tracks *real* scroll offset, only the step-wise
                    // `volumeScrollIndex` approximation used elsewhere) -- showing a seekbar there
                    // would risk being actively misleading rather than just plain, so it stays as
                    // text-only progress for that mode.
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
                            .disabled(currentIndex >= chapters.count - 1)
                    }

                    // Bottom-most primary-function row -- matches the reference reading app's own
                    // 4-icon row exactly (目录/亮度/深色/设置), not Legado_Max's stock 目录/朗读/
                    // 界面/设置: the user pointed at a real screenshot of the app they like using,
                    // which weighs more than what the Legado source code documents. 朗读 gets its
                    // own floating quick button instead (see `body`'s `.overlay`, matching that same
                    // reference screenshot's floating "听" button); 界面 now opens from inside
                    // "设置" (its first row) instead of claiming a 5th icon slot; 搜索本书内 and
                    // 自动翻页/自动滚动 moved into the top bar's "…" overflow to keep this row to
                    // exactly the 4 the reference shows.
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
                            isShowingMoreSettings = true
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.bar)
            } else {
                // A slim, always-on footer (chapter title/progress) even while the rest of the
                // chrome is hidden -- confirmed against Legado_Max's real `ReadView`/`PageView`
                // that its reading screen is never truly blank by default: a low-contrast footer
                // with chapter name + page count stays up regardless of menu state, and only the
                // *menu* (brightness/buttons/settings) is fully absent until tapped. Previously
                // this reader dropped the progress text entirely the moment chrome was hidden, so
                // there was no way to glance at "where am I" without reopening the whole menu.
                Text(chapterProgressText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        // Permanently hidden (not conditional on `isChromeVisible`) -- a custom `.overlay(alignment:
        // .top)` below draws the same buttons instead. Toggling the *native* bar's visibility was
        // the other half of the "menu open/closed changes where the safe area starts, so the text
        // itself visibly shifts" bug real usage feedback flagged (`.safeAreaInset` on the bottom was
        // the other half, fixed the same way just below): showing/hiding a real navigation bar
        // changes how much vertical space is reserved above the content, which is exactly the kind
        // of layout-affecting toggle that has to go if the reading area's size is to stay constant
        // regardless of chrome state. An overlay draws on top without reserving any space at all.
        .toolbar(.hidden, for: .navigationBar)
        // The reader is meant to take over the whole screen -- real usage feedback was that the
        // main app's 书架/发现/订阅/我的 tab bar was still visible at the bottom while reading,
        // underneath (and confusingly separate from) this reader's own bottom chrome. Pushing a
        // view via `NavigationLink` inside a `TabView`'s tab keeps the tab bar showing by default
        // unless a pushed view explicitly hides it, which nothing in this app did before.
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .top) {
            if isChromeVisible {
                HStack(spacing: 16) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    Text(chapter.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Menu {
                        Button {
                            isShowingChangeSource = true
                        } label: {
                            Label("换源（整本书）", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button {
                            isShowingChapterSourceSwitch = true
                        } label: {
                            Label("本章换源", systemImage: "doc.badge.arrow.up")
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Menu {
                        Button {
                            Task { await toggleBookmark() }
                        } label: {
                            Label(
                                isCurrentChapterBookmarked ? "移除书签" : "加入书签",
                                systemImage: isCurrentChapterBookmarked ? "bookmark.fill" : "bookmark"
                            )
                        }
                        Button {
                            isShowingContentEdit = true
                        } label: {
                            Label("编辑正文", systemImage: "pencil")
                        }
                        Button {
                            isShowingContentSearch = true
                        } label: {
                            Label("搜索本书内", systemImage: "magnifyingglass")
                        }
                        Button {
                            isShowingReplaceRules = true
                        } label: {
                            Label("替换净化", systemImage: "wand.and.stars")
                        }
                        Button {
                            if pageTurnStyle.isPaginated {
                                toggleAutoPage()
                            } else {
                                toggleAutoScroll(proxy: scrollProxy)
                            }
                        } label: {
                            let isRunning = pageTurnStyle.isPaginated ? isAutoPaging : isAutoScrolling
                            Label(
                                isRunning ? "停止自动翻页" : "自动翻页",
                                systemImage: isRunning ? "pause.circle" : "play.circle"
                            )
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
                .padding(.horizontal)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.bar)
            } else {
                // Matches the reference reading app's chrome-hidden state: a slim chapter-name
                // readout stays up top even with the rest of the menu gone (paired with the
                // symmetric bottom-edge footer below).
                HStack {
                    Text(chapter.title)
                        .lineLimit(1)
                    Spacer()
                    Text(bookTitle)
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isChromeVisible)
        // Keyed on source+index (not just index) so switching source always triggers a reload even
        // on the rare occasion the new chapter index happens to numerically match the old one --
        // `.task(id:)` only refires when its id value actually changes.
        .task(id: "\(source.bookSourceUrl)#\(currentIndex)") { await load() }
        .task { httpTTSEngines = (try? await env.httpTTSEngineStore.all()) ?? [] }
        .sheet(isPresented: $isShowingStyleSheet) {
            ReaderStyleSheet()
        }
        .sheet(isPresented: $isShowingMoreSettings) {
            ReaderMoreSettingsSheet(matchedRules: matchedReplaceRules)
        }
        .sheet(isPresented: $isShowingReplaceRules) {
            NavigationStack {
                ReplaceRuleListView()
            }
        }
        .sheet(isPresented: $isShowingChangeSource) {
            NavigationStack {
                ChangeSourceView(
                    currentBookSourceUrl: source.bookSourceUrl, bookName: bookTitle, bookAuthor: nil
                ) { newSource, match in
                    await switchSource(to: newSource, match: match)
                }
            }
        }
        .sheet(isPresented: $isShowingChapterSourceSwitch) {
            NavigationStack {
                ChangeSourceView(
                    currentBookSourceUrl: source.bookSourceUrl, bookName: bookTitle, bookAuthor: nil
                ) { newSource, match in
                    await switchChapterSource(to: newSource, match: match)
                }
            }
        }
        .sheet(isPresented: $isShowingToc) {
            tocSheet
        }
        .sheet(isPresented: $isShowingContentSearch) {
            ChapterContentSearchView(
                loadChapters: { await loadCachedChaptersForSearch() },
                onSelect: { index in goTo(index) },
                scopeNotice: "仅搜索已下载缓存的章节，未下载的章节不在搜索范围内"
            )
        }
        .sheet(isPresented: $isShowingAISummary) {
            AIChapterSummaryView(chapterTitle: chapter.title, chapterText: text)
        }
        .sheet(isPresented: $isShowingDictLookup) {
            DictLookupView()
        }
        .sheet(isPresented: $isShowingContentEdit) {
            ChapterEditView(source: source, chapter: chapter, bookUrl: bookUrl, currentText: text) { edited in
                text = edited
            }
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
            stopReadAloud()
            stopAutoScroll()
            stopAutoPage()
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
        .onChange(of: readAloudRate) { _, newValue in
            // AVSpeechSynthesizer can't change an utterance's rate mid-speech -- this takes effect
            // starting with the next paragraph, not a jarring restart of the current one.
            readAloud.setRate(Float(newValue))
        }
        .onChange(of: currentIndex) { _, _ in
            // Chapter navigation (prev/next buttons, or a lock-screen "next track" tap while at the
            // chapter's last paragraph in a future increment) invalidates whatever was being read
            // from the old chapter's text -- stopping is simpler and safer than trying to carry
            // read-aloud state across a chapter reload for this first version.
            stopReadAloud()
            // Same reasoning as read-aloud: an auto-scroll loop mid-flight is walking paragraph
            // indices that belonged to the chapter that just got replaced, so it has to stop too
            // rather than silently continuing to scroll a chapter that no longer matches its state.
            stopAutoScroll()
            volumeScrollIndex = 0
            pagedPageProgress = nil
        }
        }
    }

    /// Volume Up steps back, Volume Down steps forward -- Legado's own convention wasn't confirmed
    /// during research (its volume-key handling just maps to the same "previous/next" actions a
    /// paginated reader already has, without a documented up/down convention to match exactly), so
    /// this picked the mapping that reads as intuitive for a reading gesture (down = further into
    /// the content) rather than copying an unverified assumption.
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

    private static func keyWindow() -> UIView? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    /// `anchor` only matters in paginated mode (see `PagedChapterReaderView`'s doc comment) --
    /// `.last` is for the one case where continuing to page backward past a chapter's first page
    /// should land on the new chapter's *last* page, matching where a physical book would be;
    /// every other caller (explicit chapter-list/search/bookmark jumps, the toolbar's 上一章/下一章
    /// buttons, paging forward across a boundary) wants the default `.first`.
    private func goTo(_ index: Int, anchor: PageAnchor = .first) {
        guard chapters.indices.contains(index) else { return }
        pageAnchor = anchor
        currentIndex = index
    }

    // MARK: - Read-aloud routing
    //
    // Two independent controllers exist (`readAloud` wraps AVSpeechSynthesizer, `httpReadAloud`
    // fetches audio from a configured HttpTTSEngine) rather than one shared abstraction -- see
    // `HttpReadAloudController`'s doc comment for why. `selectedHttpTTSEngineID` (empty = system
    // voice) picks which one is "active"; these helpers are the single place that branches on it,
    // so the rest of the view just calls e.g. `stopReadAloud()` without needing to know which
    // underlying controller is actually running.

    private var isUsingHttpTTS: Bool { !selectedHttpTTSEngineID.isEmpty }
    private var isReadAloudSpeaking: Bool { isUsingHttpTTS ? httpReadAloud.isSpeaking : readAloud.isSpeaking }
    private var isReadAloudPaused: Bool { isUsingHttpTTS ? httpReadAloud.isPaused : readAloud.isPaused }
    private var readAloudCurrentParagraphIndex: Int {
        isUsingHttpTTS ? httpReadAloud.currentParagraphIndex : readAloud.currentParagraphIndex
    }

    private func startOrStopReadAloud() {
        if isReadAloudSpeaking {
            stopReadAloud()
        } else if isUsingHttpTTS, let engine = httpTTSEngines.first(where: { $0.id == selectedHttpTTSEngineID }) {
            httpReadAloud.start(
                paragraphs: paragraphs, engine: engine, cache: env.httpTTSCache,
                bookTitle: bookTitle, chapterTitle: chapter.title
            )
        } else {
            readAloud.setRate(Float(readAloudRate))
            readAloud.start(paragraphs: paragraphs, bookTitle: bookTitle, chapterTitle: chapter.title)
        }
    }

    private func stopReadAloud() {
        readAloud.stop()
        httpReadAloud.stop()
    }

    private func toggleReadAloudPause() {
        if isUsingHttpTTS { httpReadAloud.togglePause() } else { readAloud.togglePause() }
    }

    private func readAloudPreviousParagraph() {
        if isUsingHttpTTS { httpReadAloud.previousParagraph() } else { readAloud.previousParagraph() }
    }

    private func readAloudNextParagraph() {
        if isUsingHttpTTS { httpReadAloud.nextParagraph() } else { readAloud.nextParagraph() }
    }

    /// Icon-over-label button matching Legado's real bottom-most row style (`ll_catalog` etc. in
    /// `view_read_menu.xml` are icon+text, not bare icons) -- a plain icon-only button doesn't say
    /// what it does until you've already memorized it, which was part of what made the previous
    /// all-icon utility row hard to use at a glance.
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

    /// Resolves a raw tap location to one of the 3x3 zones and runs whatever action the user has
    /// configured for it (default: side columns turn chapters, middle column toggles chrome --
    /// see `ReaderTapZoneGrid.standard`). Zones are measured against the screen bounds rather than
    /// a `GeometryReader`-measured local size, matching the same approximation already used for the
    /// scroll content's `minHeight` a few lines up in `body`.
    private func handleTap(at location: CGPoint) {
        let screenSize = UIScreen.main.bounds.size
        let col = min(2, max(0, Int(location.x / (screenSize.width / 3))))
        let row = min(2, max(0, Int(location.y / (screenSize.height / 3))))
        perform(ReaderTapZoneGrid.decode(tapZoneGridRaw).action(row: row, col: col))
    }

    private func perform(_ action: ReaderTapZoneAction) {
        switch action {
        case .none:
            break
        case .toggleChrome:
            isChromeVisible.toggle()
        case .previousChapter:
            goTo(currentIndex - 1)
        case .nextChapter:
            goTo(currentIndex + 1)
        case .openToc:
            isShowingToc = true
        }
    }

    /// A lightweight in-session chapter picker, deliberately *not* a reused `TocView` -- that view
    /// fetches its own chapter list over the network and, on tap, pushes a brand-new `ReaderView`
    /// via `NavigationLink`. Presented from inside an already-open reader as a sheet, that would
    /// nest a second reader inside the sheet's own stack instead of just jumping the current
    /// session to a different chapter. This reuses the `chapters` this reader already has in memory
    /// and just moves `currentIndex`.
    @ViewBuilder
    private var tocSheet: some View {
        NavigationStack {
            List(chapters) { chapterItem in
                Button {
                    goTo(chapterItem.index)
                    isShowingToc = false
                } label: {
                    HStack {
                        Text(chapterItem.title)
                        Spacer()
                        if chapterItem.index == currentIndex {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { isShowingToc = false }
                }
            }
        }
    }

    private func toggleAutoScroll(proxy: ScrollViewProxy) {
        if isAutoScrolling {
            stopAutoScroll()
        } else {
            startAutoScroll(proxy: proxy)
        }
    }

    /// Advances one paragraph per `autoScrollInterval` seconds, hands-free -- not a continuous
    /// pixel-by-pixel scroll (SwiftUI's `ScrollViewProxy` only exposes anchor-based `scrollTo`, not
    /// an arbitrary offset), so this reads more like an auto-advancing teleprompter than a smoothly
    /// gliding page. Stops on its own at the last paragraph rather than rolling into the next
    /// chapter automatically -- chapter auto-advance already has its own distinct trigger (the
    /// bottom sentinel in `attemptAutoAdvance`), and conflating the two risked skipping the user
    /// past a chapter boundary while they weren't looking at the screen.
    private func startAutoScroll(proxy: ScrollViewProxy) {
        autoScrollTask?.cancel()
        isAutoScrolling = true
        autoScrollTask = Task {
            var index = 0
            while !Task.isCancelled && index < paragraphs.count {
                withAnimation {
                    proxy.scrollTo(index, anchor: .top)
                }
                index += 1
                try? await Task.sleep(nanoseconds: UInt64(max(autoScrollInterval, 0.5) * 1_000_000_000))
            }
            if !Task.isCancelled {
                isAutoScrolling = false
            }
        }
    }

    private func stopAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        isAutoScrolling = false
    }

    /// Paginated-mode equivalent of auto-scroll -- Legado's real "自动翻页" (`AutoPager`) works this
    /// way regardless of page-turn style since its reader is always page-based; this reader only
    /// has a real page concept in the 4 non-`.scroll` styles, so this is the paginated-only half of
    /// the same "hands-free reading" feature, reusing the same `autoScrollInterval` setting and the
    /// `pageTurnRequest` channel volume keys already drive.
    private func toggleAutoPage() {
        if isAutoPaging {
            stopAutoPage()
        } else {
            startAutoPage()
        }
    }

    private func startAutoPage() {
        autoPageTask?.cancel()
        isAutoPaging = true
        autoPageTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(max(autoScrollInterval, 0.5) * 1_000_000_000))
                guard !Task.isCancelled else { break }
                pageTurnRequest = .next
            }
        }
    }

    private func stopAutoPage() {
        autoPageTask?.cancel()
        autoPageTask = nil
        isAutoPaging = false
    }

    private func applyChineseConversion(_ text: String) -> String {
        switch chineseConversion {
        case .off: return text
        case .toTraditional: return ChineseTextConverter.convert(text, direction: .simplifiedToTraditional)
        case .toSimplified: return ChineseTextConverter.convert(text, direction: .traditionalToSimplified)
        }
    }

    /// Feeds `ChapterContentSearchView` -- only chapters already saved to `chapterCacheStore` (via
    /// the "缓存全本"/per-chapter caching flow) are searchable, since fetching every remaining
    /// chapter over the network on-demand just to search it would be slow and wasteful.
    private func loadCachedChaptersForSearch() async -> [(index: Int, title: String, text: String)] {
        var result: [(index: Int, title: String, text: String)] = []
        for chapter in chapters {
            if let cached = try? await env.chapterCacheStore.chapter(bookUrl: bookUrl, index: chapter.index) {
                result.append((index: chapter.index, title: chapter.title, text: cached.text))
            }
        }
        return result
    }

    /// Advances to the next chapter without requiring an explicit tap on "下一章" -- guarded by
    /// `canAutoAdvance`'s grace period, and skipped while read-aloud is active (its own chapter
    /// change already stops speech via `onChange(of: currentIndex)`; auto-advancing mid-sentence
    /// while the user is listening, rather than reading, would be jarring rather than helpful).
    private func attemptAutoAdvance() {
        guard canAutoAdvance, !isReadAloudSpeaking, !isLoading else { return }
        guard currentIndex < chapters.count - 1 else { return }
        goTo(currentIndex + 1)
    }

    /// Adopts a different source for the book currently being read, in place -- fetches the new
    /// source's own table of contents, carries the chapter *index* over as a best-effort
    /// approximation (same convention `ShelfView.switchSource` already uses: chapter numbering is
    /// usually close enough across sources for the same book, clamped if the new list is shorter),
    /// and updates the shelf entry too if this book happens to be shelved -- reading a book doesn't
    /// require it to be on the shelf (e.g. reached via "立即阅读" from the detail page), so that part
    /// is skipped when there's nothing to update.
    private func switchSource(to newSource: BookSource, match: SearchResult) async {
        let oldBookUrl = bookUrl
        let bookInfo = try? await BookInfoService.fetchBookInfo(source: newSource, bookURL: match.bookUrl, httpClient: env.httpClient)
        guard let tocUrl = bookInfo?.tocUrl else { return }
        let newChapters = (try? await TocService.fetchChapterList(source: newSource, tocURL: tocUrl, httpClient: env.httpClient)) ?? []
        guard !newChapters.isEmpty else { return }

        let newIndex = min(currentIndex, newChapters.count - 1)
        source = newSource
        bookUrl = match.bookUrl
        self.tocUrl = tocUrl
        chapters = newChapters
        bookTitle = bookInfo?.name ?? match.name
        currentIndex = newIndex

        if let existing = try? await env.shelfStore.book(bookUrl: oldBookUrl) {
            let updated = ShelfBook(
                bookSourceUrl: newSource.bookSourceUrl,
                bookUrl: match.bookUrl,
                name: bookInfo?.name ?? match.name,
                author: bookInfo?.author ?? match.author,
                coverUrl: bookInfo?.coverUrl ?? match.coverUrl,
                intro: bookInfo?.intro ?? match.intro,
                tocUrl: tocUrl,
                lastChapterTitle: bookInfo?.lastChapter ?? match.lastChapter,
                addedAt: existing.addedAt,
                group: existing.group,
                lastReadChapterIndex: newIndex,
                lastReadChapterTitle: newChapters[newIndex].title,
                lastReadCharacterOffset: 0,
                lastReadAt: existing.lastReadAt,
                totalChapterCount: newChapters.count
            )
            try? await env.shelfStore.remove(bookUrl: oldBookUrl)
            try? await env.shelfStore.addOrUpdate(updated)
        }
    }

    /// Fixes just the chapter currently on screen without switching the book's source for anything
    /// else -- finds this chapter's title in another source's table of contents (falling back to
    /// the same index if no title matches), fetches its content from there, and saves it into
    /// `chapterCacheStore` under the *original* book/index. `load()`'s existing cache-first lookup
    /// then picks it up transparently, exactly as if the chapter had been downloaded normally, so
    /// the fix persists across relaunches without any new loading path.
    private func switchChapterSource(to newSource: BookSource, match: SearchResult) async {
        let originalIndex = chapter.index
        let originalTitle = chapter.title
        isLoading = true
        do {
            let bookInfo = try await BookInfoService.fetchBookInfo(source: newSource, bookURL: match.bookUrl, httpClient: env.httpClient)
            let altChapters = try await TocService.fetchChapterList(source: newSource, tocURL: bookInfo.tocUrl, httpClient: env.httpClient)
            let byTitle = altChapters.first(where: { $0.title == originalTitle })
            let fallback: BookChapter? = altChapters.indices.contains(originalIndex) ? altChapters[originalIndex] : altChapters.first
            guard let matchedChapter = byTitle ?? fallback else {
                errorMessage = "对方书源没有可用章节"
                isLoading = false
                return
            }
            let content = try await ContentService.fetchContent(source: newSource, chapter: matchedChapter, httpClient: env.httpClient)
            try await env.chapterCacheStore.save(bookUrl: bookUrl, index: originalIndex, content: content)
        } catch {
            errorMessage = "本章换源失败: \(error)"
            isLoading = false
            return
        }
        await load()
    }

    /// Builds one paragraph's flowing text as a concatenation of styled `Text` runs -- SwiftUI's
    /// `Text + Text` only carries text-level attributes (color/weight/etc.) across the join, not
    /// view-level ones like `.background()`, so highlighted spans are set apart with color+bold
    /// rather than a literal background tint.
    private func highlightedText(_ paragraph: String) -> Text {
        let segments = HighlightRuleApplier.segments(highlightRules, in: paragraph)
        return segments.reduce(Text("")) { partial, segment in
            if segment.isHighlighted {
                return partial + Text(segment.text).foregroundStyle(.orange).bold()
            } else {
                return partial + Text(segment.text).foregroundStyle(theme.textColor(for: colorScheme, customText: Color(hex: customThemeTextHex)))
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        canAutoAdvance = false
        do {
            let cached = try? await env.chapterCacheStore.chapter(bookUrl: bookUrl, index: chapter.index)
            let content: ChapterContent
            if let cached {
                content = cached
            } else {
                content = try await ContentService.fetchContent(source: source, chapter: chapter, httpClient: env.httpClient)
            }
            let replaceRules = (try? await env.replaceRuleStore.enabled()) ?? []
            let purified = ReplaceRuleApplier.applyReportingMatches(replaceRules, to: content.text, sourceUrl: source.bookSourceUrl)
            text = applyChineseConversion(purified.result)
            matchedReplaceRules = purified.matchedRules
            highlightRules = (try? await env.highlightRuleStore.enabled()) ?? []
            try? await env.shelfStore.updateProgress(
                bookUrl: bookUrl, chapterIndex: chapter.index, chapterTitle: chapter.title, characterOffset: 0
            )
            isCurrentChapterBookmarked = (try? await env.bookmarkStore.isBookmarked(
                bookIdentifier: bookUrl, chapterIndex: chapter.index
            )) ?? false
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
        armAutoAdvance()
    }

    /// Bookmarks are chapter-level (this reader doesn't track a finer scroll position anywhere),
    /// so the button is a simple toggle -- one bookmark per (book, chapter) at most.
    private func toggleBookmark() async {
        if isCurrentChapterBookmarked {
            try? await env.bookmarkStore.remove(bookIdentifier: bookUrl, chapterIndex: chapter.index)
            isCurrentChapterBookmarked = false
        } else {
            let bookmark = Bookmark(
                isLocal: false, bookSourceUrl: source.bookSourceUrl, bookIdentifier: bookUrl,
                tocUrl: tocUrl, bookTitle: bookTitle, chapterIndex: chapter.index, chapterTitle: chapter.title
            )
            try? await env.bookmarkStore.add(bookmark)
            isCurrentChapterBookmarked = true
        }
    }

    /// Runs once per chapter load (both the reader's very first chapter and every subsequent
    /// transition, since this is called from `load()` rather than `.onChange(of: currentIndex)`,
    /// which never fires for a view's initial state) -- the delay gives a short-enough-to-fit-on
    /// -one-screen chapter a moment before the bottom sentinel's mere presence can trigger another
    /// auto-advance.
    private func armAutoAdvance() {
        let loadedIndex = currentIndex
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, currentIndex == loadedIndex else { return }
            canAutoAdvance = true
        }
    }
}
