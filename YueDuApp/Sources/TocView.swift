import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import NetworkClient

struct TocView: View {
    let source: BookSource
    let tocURL: String
    let bookUrl: String
    let bookTitle: String
    /// When set (from the shelf's "resume reading" entry point, or `BookDetailView`'s "阅读" button)
    /// and valid once chapters load, auto-navigates straight into the reader at this chapter instead
    /// of leaving the user to re-browse the whole table of contents.
    var resumeChapterIndex: Int? = nil

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

    var body: some View {
        List(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
            NavigationLink {
                BookOpenerView(
                    source: source, bookUrl: bookUrl, tocUrl: tocURL, chapters: chapters, currentIndex: index,
                    bookTitle: bookTitle
                )
            } label: {
                Text(chapter.title)
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if chapters.isEmpty {
                ContentUnavailableView("没有章节", systemImage: "list.bullet")
            }
        }
        .navigationTitle("目录")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $shouldPresentResume) {
            BookOpenerView(
                source: source, bookUrl: bookUrl, tocUrl: tocURL, chapters: chapters,
                currentIndex: resumeChapterIndex ?? 0, bookTitle: bookTitle
            )
        }
        .task { await load() }
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
        isLoading = false
    }
}
