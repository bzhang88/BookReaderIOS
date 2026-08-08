import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import Persistence
import NetworkClient

struct BookDetailView: View {
    let source: BookSource
    let searchResult: SearchResult

    @EnvironmentObject private var env: AppEnvironment
    @State private var bookInfo: BookInfo?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isInShelf = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage {
                    ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else if let bookInfo {
                    Text(bookInfo.name ?? searchResult.name).font(.title.bold())
                    if let author = bookInfo.author, !author.isEmpty {
                        Text(author).foregroundStyle(.secondary)
                    }
                    if let kind = bookInfo.kind, !kind.isEmpty {
                        Text(kind).font(.caption).foregroundStyle(.secondary)
                    }
                    if let lastChapter = bookInfo.lastChapter, !lastChapter.isEmpty {
                        Text("最新章节: \(lastChapter)").font(.subheadline)
                    }

                    Button {
                        Task { await toggleShelf(bookInfo: bookInfo) }
                    } label: {
                        Label(isInShelf ? "已在书架" : "加入书架", systemImage: isInShelf ? "checkmark" : "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isInShelf)

                    NavigationLink {
                        TocView(
                            source: source, tocURL: bookInfo.tocUrl, bookUrl: searchResult.bookUrl,
                            bookTitle: bookInfo.name ?? searchResult.name
                        )
                    } label: {
                        Label("查看目录", systemImage: "list.bullet")
                    }
                    .buttonStyle(.bordered)

                    if let intro = bookInfo.intro, !intro.isEmpty {
                        Divider()
                        Text(intro).font(.body)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if isLoading { ProgressView() }
        }
        .navigationTitle(searchResult.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            bookInfo = try await BookInfoService.fetchBookInfo(
                source: source, bookURL: searchResult.bookUrl, httpClient: env.httpClient
            )
            isInShelf = (try? await env.shelfStore.book(bookUrl: searchResult.bookUrl)) != nil
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
    }

    private func toggleShelf(bookInfo: BookInfo) async {
        let book = ShelfBook(
            bookSourceUrl: source.bookSourceUrl, bookUrl: searchResult.bookUrl,
            name: bookInfo.name ?? searchResult.name, author: bookInfo.author,
            coverUrl: bookInfo.coverUrl, intro: bookInfo.intro, tocUrl: bookInfo.tocUrl,
            lastChapterTitle: bookInfo.lastChapter
        )
        try? await env.shelfStore.addOrUpdate(book)
        isInShelf = true
    }
}
