import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import NetworkClient

/// The standalone, full-screen chapter list reached from `BookDetailView` (distinct from
/// `ReaderTocDrawerView`, the in-reader slide-in drawer, which already has its own search/bookmark
/// tabs). Real usage feedback (a Legado-comparison pass): this used to be a completely bare list --
/// no search, no way to reverse the order, no indication of which chapter you're already on, no
/// sign of which chapters are already cached offline. For a book with hundreds/thousands of
/// chapters, finding one by name or telling at a glance "where am I" was materially harder than in
/// Legado's own two-tab TOC screen.
struct TocView: View {
    let source: BookSource
    let tocURL: String
    let bookUrl: String
    let bookTitle: String
    /// Threaded through to `ReaderView` (via `BookOpenerView`) so its 换源 sheets can filter on a
    /// real author instead of always matching by title alone -- see `ReaderView.bookAuthor`'s doc
    /// comment.
    var bookAuthor: String? = nil
    /// When set (from the shelf's "resume reading" entry point, or `BookDetailView`'s "阅读" button)
    /// and valid once chapters load, auto-navigates straight into the reader at this chapter instead
    /// of leaving the user to re-browse the whole table of contents.
    var resumeChapterIndex: Int? = nil
    /// Which chapter to highlight and auto-scroll to when the list first appears -- "where you
    /// already are," shown for orientation regardless of whether this entry point *also*
    /// auto-navigates. Usually the same underlying value as `resumeChapterIndex` when both apply
    /// (`BookDetailView`'s "阅读"), but also set on its own from "查看" (no auto-navigate, just show
    /// me the list with my place in it marked).
    var currentChapterIndex: Int? = nil

    @EnvironmentObject private var env: AppEnvironment
    @State private var chapters: [BookChapter] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var shouldPresentResume = false
    // Real-usage bug: `.task` can re-run when this view becomes the top of the `NavigationStack`
    // again after popping back from the pushed reader (a documented SwiftUI quirk with
    // `NavigationLink`-provided destinations containing a `List`). Without this guard, `load()`
    // re-running would set `shouldPresentResume = true` again every time -- the user taps back from
    // the reader, sees this TOC list for a flash, and gets auto-navigated straight back into the
    // *same* chapter, effectively unable to ever land on the TOC to pick a different one. `@State`
    // (not a local variable in `load()`) is what makes this survive across those re-runs: it's tied
    // to this view's identity, not to any one call of `load()`.
    @State private var hasAutoNavigatedOnce = false
    @State private var searchKeyword = ""
    // Real bug found comparing against Legado: this used to be plain unpersisted `@State`, resetting
    // to normal order every time this view was recreated (e.g. leaving and reopening TOC). Legado's
    // own `reverseToc` persists by physically rewriting every `BookChapter.index` in its database --
    // deliberately not replicated here, since bookmarks/reading-progress in this app key off
    // `chapterIndex` values that assume the source's original ordering, and reindexing everything
    // that references a chapter by index is a much larger, riskier change than what this bug
    // actually needs. Persisting just the display preference (keyed per book) fixes the "resets on
    // reopen" bug without touching how chapters are identified anywhere else.
    @State private var isReversed = false
    @State private var downloadedIndices: Set<Int> = []

    private var reversedPreferenceKey: String { "toc.isReversed.\(bookUrl)" }

    /// A plain nominal type, not a `(index: Int, chapter: BookChapter)` tuple -- `List(_:id:)` needs
    /// a real `KeyPath`, and Swift key paths can't be formed to tuple labels the way they can to a
    /// stored property, so a tuple here would be a real compile error rather than a style choice.
    private struct DisplayedChapter: Identifiable {
        let index: Int
        let chapter: BookChapter
        var id: String { chapter.id }
    }

    private var displayedChapters: [DisplayedChapter] {
        var items = chapters.enumerated().map { DisplayedChapter(index: $0.offset, chapter: $0.element) }
        let trimmed = searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items = items.filter { $0.chapter.title.localizedCaseInsensitiveContains(trimmed) }
        }
        if isReversed { items.reverse() }
        return items
    }

    var body: some View {
        ScrollViewReader { proxy in
            List(displayedChapters) { item in
                tocRow(item)
            }
            .searchable(text: $searchKeyword, prompt: "搜索章节")
            .overlay {
                if isLoading {
                    ProgressView()
                } else if let errorMessage {
                    ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else if chapters.isEmpty {
                    ContentUnavailableView("没有章节", systemImage: "list.bullet")
                } else if displayedChapters.isEmpty {
                    ContentUnavailableView.search(text: searchKeyword)
                }
            }
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isReversed.toggle()
                        UserDefaults.standard.set(isReversed, forKey: reversedPreferenceKey)
                    } label: {
                        Label(isReversed ? "倒序" : "正序", systemImage: isReversed ? "arrow.up" : "arrow.down")
                    }
                }
                if currentChapterIndex != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("当前") { scrollToCurrent(proxy: proxy) }
                    }
                }
            }
            .navigationDestination(isPresented: $shouldPresentResume) {
                BookOpenerView(
                    source: source, bookUrl: bookUrl, tocUrl: tocURL, chapters: chapters,
                    currentIndex: resumeChapterIndex ?? 0, bookTitle: bookTitle, bookAuthor: bookAuthor
                )
            }
            .task {
                isReversed = UserDefaults.standard.bool(forKey: reversedPreferenceKey)
                await load()
                // Same pattern `LocalReaderView` already uses for its own scroll-to-position:
                // `List`/`ScrollViewReader` needs its rows to have actually laid out before
                // `scrollTo` reliably lands, which `load()`'s `chapters` assignment alone doesn't
                // guarantee has happened by the very next line.
                DispatchQueue.main.async {
                    scrollToCurrent(proxy: proxy, animated: false)
                }
            }
        }
    }

    /// Real bug found comparing against Legado: a volume/section header row (`BookChapter.isVolume`)
    /// used to be a plain `NavigationLink` identical to a real chapter -- tapping it opened the
    /// reader on a synthetic "chapter" whose body is just the volume's own title/tag. Legado never
    /// lets a volume be "opened" as a chapter (it only toggles collapse/expand); rendering it as
    /// plain non-navigable text here is the minimal fix for that -- full collapse/expand grouping is
    /// a separate, larger feature, not this bug.
    @ViewBuilder
    private func tocRow(_ item: DisplayedChapter) -> some View {
        if item.chapter.isVolume {
            Text(item.chapter.title)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .id(item.index)
        } else {
            NavigationLink {
                BookOpenerView(
                    source: source, bookUrl: bookUrl, tocUrl: tocURL, chapters: chapters, currentIndex: item.index,
                    bookTitle: bookTitle, bookAuthor: bookAuthor
                )
            } label: {
                HStack {
                    Text(item.chapter.title)
                        .fontWeight(item.index == currentChapterIndex ? .semibold : .regular)
                        .foregroundStyle(item.index == currentChapterIndex ? Color.accentColor : .primary)
                    Spacer(minLength: 8)
                    // Real bug found comparing against Legado: this used to show the cloud glyph on
                    // *downloaded* chapters, backwards from `ReaderTocDrawerView.tocList`'s own
                    // (correct, Legado-matching) rendering of the exact same `downloadedIndices` data
                    // one screen over -- already-cached rows should read clean, only chapters that
                    // would still need a network fetch get the glyph.
                    if !downloadedIndices.contains(item.index) {
                        Image(systemName: "icloud")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .id(item.index)
        }
    }

    private func scrollToCurrent(proxy: ScrollViewProxy, animated: Bool = true) {
        guard let currentChapterIndex, chapters.indices.contains(currentChapterIndex) else { return }
        if animated {
            withAnimation { proxy.scrollTo(currentChapterIndex, anchor: .center) }
        } else {
            proxy.scrollTo(currentChapterIndex, anchor: .center)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            chapters = try await TocService.fetchChapterList(source: source, tocURL: tocURL, httpClient: env.httpClient)
            if !hasAutoNavigatedOnce, let resumeChapterIndex, chapters.indices.contains(resumeChapterIndex) {
                hasAutoNavigatedOnce = true
                shouldPresentResume = true
            }
        } catch {
            errorMessage = FriendlyError.message(for: error)
        }
        downloadedIndices = (try? await env.chapterCacheStore.downloadedIndices(bookUrl: bookUrl)) ?? []
        isLoading = false
    }
}
