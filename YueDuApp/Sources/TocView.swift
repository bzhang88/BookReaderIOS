import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import NetworkClient

struct TocView: View {
    let source: BookSource
    let tocURL: String
    let bookUrl: String
    let bookTitle: String
    /// When set (from the shelf's "resume reading" entry point) and valid once chapters load,
    /// auto-navigates straight into the reader at this chapter instead of leaving the user to
    /// re-browse the whole table of contents.
    var resumeChapterIndex: Int? = nil

    @EnvironmentObject private var env: AppEnvironment
    @State private var chapters: [BookChapter] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var shouldPresentResume = false

    var body: some View {
        List(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
            NavigationLink {
                ReaderView(
                    source: source, bookUrl: bookUrl, chapters: chapters, currentIndex: index, bookTitle: bookTitle
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
            ReaderView(
                source: source, bookUrl: bookUrl, chapters: chapters,
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
            if let resumeChapterIndex, chapters.indices.contains(resumeChapterIndex) {
                shouldPresentResume = true
            }
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
    }
}
