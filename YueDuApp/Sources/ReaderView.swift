import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import Persistence

struct ReaderView: View {
    let source: BookSource
    let bookUrl: String
    let chapters: [BookChapter]
    let bookTitle: String
    @State private var currentIndex: Int

    @EnvironmentObject private var env: AppEnvironment
    @State private var text: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    init(source: BookSource, bookUrl: String, chapters: [BookChapter], currentIndex: Int, bookTitle: String) {
        self.source = source
        self.bookUrl = bookUrl
        self.chapters = chapters
        self.bookTitle = bookTitle
        self._currentIndex = State(initialValue: currentIndex)
    }

    private var chapter: BookChapter { chapters[currentIndex] }

    var body: some View {
        ScrollView {
            Text(text)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    goTo(currentIndex - 1)
                } label: {
                    Label("上一章", systemImage: "chevron.left")
                }
                .disabled(currentIndex <= 0)

                Spacer()

                Button {
                    goTo(currentIndex + 1)
                } label: {
                    Label("下一章", systemImage: "chevron.right")
                }
                .disabled(currentIndex >= chapters.count - 1)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: currentIndex) { await load() }
    }

    private func goTo(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        currentIndex = index
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let content = try await ContentService.fetchContent(source: source, chapter: chapter, httpClient: env.httpClient)
            text = content.text
            try? await env.shelfStore.updateProgress(
                bookUrl: bookUrl, chapterIndex: chapter.index, chapterTitle: chapter.title, characterOffset: 0
            )
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
    }
}
