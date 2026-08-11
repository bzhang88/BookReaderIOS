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
    @State private var text: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingSettings = false
    @State private var isShowingChangeSource = false
    @State private var isShowingChapterSourceSwitch = false
    @State private var isShowingToc = false
    @State private var isShowingContentSearch = false
    @State private var isShowingAISummary = false
    @State private var isShowingDictLookup = false
    @State private var isShowingContentEdit = false
    @State private var isShowingWebSearch = false
    @State private var isChromeVisible = true
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

    var body: some View {
        ScrollViewReader { scrollProxy in
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
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard hypot(value.translation.width, value.translation.height) <= touchSlop else { return }
                        handleTap(at: value.location)
                    }
            )
        }
        .background(theme.backgroundColor(for: colorScheme))
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
        .onReceive(scheduleTimer) { scheduleTick = $0 }
        .safeAreaInset(edge: .bottom) {
            if isChromeVisible {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "sun.min")
                        Slider(value: $screenBrightness, in: 0...1)
                            .onChange(of: screenBrightness) { _, newValue in
                                UIScreen.main.brightness = CGFloat(newValue)
                            }
                        Image(systemName: "sun.max")
                    }
                    Text("第 \(currentIndex + 1) / \(chapters.count) 章")
                        .font(.caption)
                        .foregroundStyle(.secondary)

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

                    // Utility row -- matches Legado's row of small circular tool buttons above the
                    // chapter-nav row (search-in-book/auto-page/replace-toggle/night-theme there;
                    // 目录/书签/换源/自动滚动 here, since that's this app's closest equivalent set).
                    HStack(spacing: 28) {
                        Spacer()
                        Button {
                            isShowingToc = true
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        Button {
                            Task { await toggleBookmark() }
                        } label: {
                            Image(systemName: isCurrentChapterBookmarked ? "bookmark.fill" : "bookmark")
                        }
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
                        Button {
                            toggleAutoScroll(proxy: scrollProxy)
                        } label: {
                            Image(systemName: isAutoScrolling ? "pause.circle" : "arrow.down.circle")
                        }
                        Button {
                            isShowingContentEdit = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        Spacer()
                    }
                    .font(.title3)

                    // Chapter-nav row -- prev/next chapter flanking read-aloud + settings, matching
                    // Legado's bottom-most row shape (though without a real draggable in-chapter
                    // progress bar in between: this reader is continuous-scroll per chapter, not
                    // paginated, so there's no character-offset position to back a seek control
                    // with -- "第 X / Y 章" above already covers the equivalent progress info).
                    HStack {
                        Button {
                            goTo(currentIndex - 1)
                        } label: {
                            Label("上一章", systemImage: "chevron.left")
                        }
                        .disabled(currentIndex <= 0)

                        Spacer()

                        Button {
                            startOrStopReadAloud()
                        } label: {
                            Image(systemName: isReadAloudSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                        }

                        Button {
                            isShowingSettings = true
                        } label: {
                            Image(systemName: "textformat.size")
                        }

                        Spacer()

                        Button {
                            goTo(currentIndex + 1)
                        } label: {
                            Label("下一章", systemImage: "chevron.right")
                        }
                        .disabled(currentIndex >= chapters.count - 1)
                    }
                }
                .padding()
                .background(.bar)
            }
        }
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isChromeVisible ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingContentSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAISummary = true
                } label: {
                    Image(systemName: "sparkles")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingDictLookup = true
                } label: {
                    Image(systemName: "character.book.closed")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingWebSearch = true
                } label: {
                    Image(systemName: "globe")
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isChromeVisible)
        // Keyed on source+index (not just index) so switching source always triggers a reload even
        // on the rare occasion the new chapter index happens to numerically match the old one --
        // `.task(id:)` only refires when its id value actually changes.
        .task(id: "\(source.bookSourceUrl)#\(currentIndex)") { await load() }
        .task { httpTTSEngines = (try? await env.httpTTSEngineStore.all()) ?? [] }
        .sheet(isPresented: $isShowingSettings) {
            ReaderSettingsSheet(matchedRules: matchedReplaceRules)
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

    private func goTo(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
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
                return partial + Text(segment.text).foregroundStyle(theme.textColor(for: colorScheme))
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
