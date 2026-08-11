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
    @State private var chapters: [BookChapter]
    @State private var bookTitle: String
    @State private var currentIndex: Int

    @EnvironmentObject private var env: AppEnvironment
    @State private var text: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingSettings = false
    @State private var isShowingChangeSource = false
    @State private var isChromeVisible = true
    // Guards auto-advance so a chapter that's short enough to fit on screen without scrolling
    // doesn't fire the moment it loads (the bottom sentinel would already be within the visible
    // scroll bounds from the very first layout pass, before the user has read anything) -- reset
    // to false on every chapter change, flips true after a short grace period.
    @State private var canAutoAdvance = false
    @State private var screenBrightness: Double = Double(UIScreen.main.brightness)
    @State private var highlightRules: [HighlightRule] = []
    @StateObject private var readAloud = ReadAloudController()

    @AppStorage(ReaderSettingsKey.fontSize) private var fontSize: Double = 18
    @AppStorage(ReaderSettingsKey.lineSpacing) private var lineSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.paragraphSpacing) private var paragraphSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.theme) private var theme: ReaderTheme = .day
    @AppStorage(ReaderSettingsKey.keepScreenOn) private var keepScreenOn: Bool = true
    @AppStorage(ReaderSettingsKey.readAloudRate) private var readAloudRate: Double = 0.5

    init(source: BookSource, bookUrl: String, chapters: [BookChapter], currentIndex: Int, bookTitle: String) {
        self._source = State(initialValue: source)
        self._bookUrl = State(initialValue: bookUrl)
        self._chapters = State(initialValue: chapters)
        self._bookTitle = State(initialValue: bookTitle)
        self._currentIndex = State(initialValue: currentIndex)
    }

    private var chapter: BookChapter { chapters[currentIndex] }
    private var paragraphs: [String] { text.components(separatedBy: "\n") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: paragraphSpacing) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    highlightedText(paragraph)
                        .font(.system(size: fontSize))
                        .lineSpacing(lineSpacing)
                        .padding(.horizontal, 4)
                        .background(
                            readAloud.isSpeaking && index == readAloud.currentParagraphIndex
                                ? Color.accentColor.opacity(0.15) : Color.clear
                        )
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
            .onTapGesture {
                isChromeVisible.toggle()
            }
        }
        .background(theme.backgroundColor)
        .overlay {
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            }
        }
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

                    if readAloud.isSpeaking {
                        HStack(spacing: 20) {
                            Button {
                                readAloud.previousParagraph()
                            } label: {
                                Image(systemName: "backward.end")
                            }
                            Button {
                                readAloud.togglePause()
                            } label: {
                                Image(systemName: readAloud.isPaused ? "play.fill" : "pause.fill")
                            }
                            Button {
                                readAloud.nextParagraph()
                            } label: {
                                Image(systemName: "forward.end")
                            }
                            Button(role: .destructive) {
                                readAloud.stop()
                            } label: {
                                Image(systemName: "stop.fill")
                            }
                        }
                        .font(.title3)
                    }

                    HStack {
                        Button {
                            goTo(currentIndex - 1)
                        } label: {
                            Label("上一章", systemImage: "chevron.left")
                        }
                        .disabled(currentIndex <= 0)

                        Spacer()

                        Button {
                            if readAloud.isSpeaking {
                                readAloud.stop()
                            } else {
                                readAloud.setRate(Float(readAloudRate))
                                readAloud.start(paragraphs: paragraphs, bookTitle: bookTitle, chapterTitle: chapter.title)
                            }
                        } label: {
                            Image(systemName: readAloud.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                        }

                        Button {
                            isShowingChangeSource = true
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
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
        .animation(.easeInOut(duration: 0.2), value: isChromeVisible)
        // Keyed on source+index (not just index) so switching source always triggers a reload even
        // on the rare occasion the new chapter index happens to numerically match the old one --
        // `.task(id:)` only refires when its id value actually changes.
        .task(id: "\(source.bookSourceUrl)#\(currentIndex)") { await load() }
        .sheet(isPresented: $isShowingSettings) {
            ReaderSettingsSheet()
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
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepScreenOn }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            readAloud.stop()
        }
        .onChange(of: keepScreenOn) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
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
            readAloud.stop()
        }
    }

    private func goTo(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        currentIndex = index
    }

    /// Advances to the next chapter without requiring an explicit tap on "下一章" -- guarded by
    /// `canAutoAdvance`'s grace period, and skipped while read-aloud is active (its own chapter
    /// change already stops speech via `onChange(of: currentIndex)`; auto-advancing mid-sentence
    /// while the user is listening, rather than reading, would be jarring rather than helpful).
    private func attemptAutoAdvance() {
        guard canAutoAdvance, !readAloud.isSpeaking, !isLoading else { return }
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
                lastReadAt: existing.lastReadAt
            )
            try? await env.shelfStore.remove(bookUrl: oldBookUrl)
            try? await env.shelfStore.addOrUpdate(updated)
        }
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
                return partial + Text(segment.text).foregroundStyle(theme.textColor)
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
            text = ReplaceRuleApplier.apply(replaceRules, to: content.text, sourceUrl: source.bookSourceUrl)
            highlightRules = (try? await env.highlightRuleStore.enabled()) ?? []
            try? await env.shelfStore.updateProgress(
                bookUrl: bookUrl, chapterIndex: chapter.index, chapterTitle: chapter.title, characterOffset: 0
            )
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
        armAutoAdvance()
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
