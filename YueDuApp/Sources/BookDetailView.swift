import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import Persistence
import NetworkClient

/// Book detail screen -- reachable both from a fresh search result (fallback fields come from
/// `SearchResult`) and from an already-shelved book (fallback fields come from `ShelfBook`), which
/// is why the initializer takes plain fallback fields rather than either type directly: neither
/// context has the other type's value on hand, and both have enough to show something before
/// `BookInfoService` finishes its own network fetch.
struct BookDetailView: View {
    let source: BookSource
    let bookUrl: String
    let fallbackName: String
    let fallbackAuthor: String?
    let fallbackCoverUrl: String?
    let fallbackIntro: String?
    let fallbackLastChapter: String?

    @EnvironmentObject private var env: AppEnvironment
    @State private var bookInfo: BookInfo?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isInShelf = false
    @State private var previewChapters: [BookChapter] = []

    init(
        source: BookSource, bookUrl: String, fallbackName: String, fallbackAuthor: String? = nil,
        fallbackCoverUrl: String? = nil, fallbackIntro: String? = nil, fallbackLastChapter: String? = nil
    ) {
        self.source = source
        self.bookUrl = bookUrl
        self.fallbackName = fallbackName
        self.fallbackAuthor = fallbackAuthor
        self.fallbackCoverUrl = fallbackCoverUrl
        self.fallbackIntro = fallbackIntro
        self.fallbackLastChapter = fallbackLastChapter
    }

    /// Convenience initializer for the search-results flow, where every fallback field already
    /// lives on a `SearchResult`.
    init(source: BookSource, searchResult: SearchResult) {
        self.init(
            source: source, bookUrl: searchResult.bookUrl, fallbackName: searchResult.name,
            fallbackAuthor: searchResult.author, fallbackCoverUrl: searchResult.coverUrl,
            fallbackIntro: searchResult.intro, fallbackLastChapter: searchResult.lastChapter
        )
    }

    /// Convenience initializer for the shelf flow, where every fallback field already lives on a
    /// `ShelfBook`.
    init(source: BookSource, shelfBook: ShelfBook) {
        self.init(
            source: source, bookUrl: shelfBook.bookUrl, fallbackName: shelfBook.name,
            fallbackAuthor: shelfBook.author, fallbackCoverUrl: shelfBook.coverUrl,
            fallbackIntro: shelfBook.intro, fallbackLastChapter: shelfBook.lastChapterTitle
        )
    }

    private var name: String { bookInfo?.name ?? fallbackName }
    private var author: String? { bookInfo?.author ?? fallbackAuthor }
    private var coverUrl: String? { bookInfo?.coverUrl ?? fallbackCoverUrl }
    private var intro: String? { bookInfo?.intro ?? fallbackIntro }
    private var lastChapter: String? { bookInfo?.lastChapter ?? fallbackLastChapter }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let errorMessage {
                    ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else {
                    header
                    statsRow
                    actionButtons

                    if let intro, !intro.isEmpty {
                        Divider()
                        Text(intro).font(.body)
                    }

                    if !previewChapters.isEmpty {
                        Divider()
                        chapterPreview
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if isLoading { ProgressView() }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: coverUrl.flatMap(URL.init(string:))) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay { Image(systemName: "book.closed").foregroundStyle(.secondary) }
                }
            }
            .frame(width: 100, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(name).font(.title2.bold())
                if let author, !author.isEmpty {
                    Text(author).font(.subheadline).foregroundStyle(.secondary)
                }
                if let lastChapter, !lastChapter.isEmpty {
                    Text("最新: \(lastChapter)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }

    private var statsRow: some View {
        HStack {
            statColumn(title: "字数", value: bookInfo?.wordCount ?? "未知")
            Divider().frame(height: 30)
            statColumn(title: "来源", value: source.bookSourceName)
            if let kind = bookInfo?.kind, !kind.isEmpty {
                Divider().frame(height: 30)
                statColumn(title: "类型", value: kind)
            }
        }
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.bold()).lineLimit(1)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var actionButtons: some View {
        HStack {
            Button {
                Task { await toggleShelf() }
            } label: {
                Label(isInShelf ? "已在书架" : "加入书架", systemImage: isInShelf ? "checkmark" : "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isInShelf || bookInfo == nil)

            if let bookInfo {
                NavigationLink {
                    TocView(source: source, tocURL: bookInfo.tocUrl, bookUrl: bookUrl, bookTitle: name)
                } label: {
                    Label("目录", systemImage: "list.bullet")
                }
                .buttonStyle(.bordered)

                NavigationLink {
                    TocView(source: source, tocURL: bookInfo.tocUrl, bookUrl: bookUrl, bookTitle: name, resumeChapterIndex: 0)
                } label: {
                    Label("立即阅读", systemImage: "book")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var chapterPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("章节预览（共 \(previewChapters.count) 章）").font(.headline)
            ForEach(previewChapters.prefix(5)) { chapter in
                Text(chapter.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let info = try await BookInfoService.fetchBookInfo(source: source, bookURL: bookUrl, httpClient: env.httpClient)
            bookInfo = info
            isInShelf = (try? await env.shelfStore.book(bookUrl: bookUrl)) != nil
            previewChapters = (try? await TocService.fetchChapterList(
                source: source, tocURL: info.tocUrl, httpClient: env.httpClient
            )) ?? []
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
    }

    private func toggleShelf() async {
        guard let bookInfo else { return }
        let book = ShelfBook(
            bookSourceUrl: source.bookSourceUrl, bookUrl: bookUrl,
            name: bookInfo.name ?? fallbackName, author: bookInfo.author ?? fallbackAuthor,
            coverUrl: bookInfo.coverUrl ?? fallbackCoverUrl, intro: bookInfo.intro ?? fallbackIntro,
            tocUrl: bookInfo.tocUrl, lastChapterTitle: bookInfo.lastChapter ?? fallbackLastChapter
        )
        try? await env.shelfStore.addOrUpdate(book)
        isInShelf = true
    }
}
