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
    @State private var shelfCoverUrl: String?
    @State private var isShowingCoverPicker = false
    @State private var previewChapters: [BookChapter] = []
    @State private var downloadedCount = 0
    @State private var isDownloading = false
    @State private var downloadProgress = 0
    @State private var downloadTask: Task<Void, Never>?

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
    /// Once a book is shelved, its shelf-stored cover (which may be a manual override the user
    /// picked via `CoverPickerView`) takes priority over whatever the source's own detail page
    /// currently returns -- otherwise a manually-picked cover would silently revert to the
    /// source's default the very next time this screen re-fetches `bookInfo`.
    private var coverUrl: String? {
        if let shelfCoverUrl, !shelfCoverUrl.isEmpty { return shelfCoverUrl }
        return bookInfo?.coverUrl ?? fallbackCoverUrl
    }
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

                    if !previewChapters.isEmpty {
                        downloadSection
                    }

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
        .sheet(isPresented: $isShowingCoverPicker) {
            CoverPickerView(bookName: name) { newCoverUrl in
                await setCover(newCoverUrl)
            }
        }
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

            if isInShelf {
                Button {
                    isShowingCoverPicker = true
                } label: {
                    Label("更换封面", systemImage: "photo")
                }
                .buttonStyle(.bordered)
            }

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

    /// Offline download entry point (Legado's own detail page has an equivalent "缓存" button) --
    /// strictly opt-in, matching `ChapterCacheStore`'s own design: normal reading never silently
    /// caches anything, only this explicit action does.
    @ViewBuilder
    private var downloadSection: some View {
        if isDownloading {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(downloadProgress), total: Double(max(previewChapters.count, 1)))
                HStack {
                    Text("缓存中 \(downloadProgress)/\(previewChapters.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("取消") { downloadTask?.cancel() }
                        .font(.caption)
                }
            }
        } else if downloadedCount > 0 {
            HStack {
                Label("已缓存 \(downloadedCount)/\(previewChapters.count) 章", systemImage: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Spacer()
                if downloadedCount < previewChapters.count {
                    Button("继续缓存") { startDownload() }
                        .font(.caption)
                }
                Button("删除缓存", role: .destructive) {
                    Task { await deleteCache() }
                }
                .font(.caption)
            }
        } else {
            Button {
                startDownload()
            } label: {
                Label("缓存全本", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
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
            let existingShelfBook = try? await env.shelfStore.book(bookUrl: bookUrl)
            isInShelf = existingShelfBook != nil
            shelfCoverUrl = existingShelfBook?.coverUrl
            previewChapters = (try? await TocService.fetchChapterList(
                source: source, tocURL: info.tocUrl, httpClient: env.httpClient
            )) ?? []
            await refreshDownloadedCount()
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
    }

    private func refreshDownloadedCount() async {
        downloadedCount = (try? await env.chapterCacheStore.downloadedIndices(bookUrl: bookUrl).count) ?? 0
    }

    private func startDownload() {
        isDownloading = true
        downloadTask = Task {
            await downloadRemainingChapters()
            isDownloading = false
        }
    }

    /// Fetches every not-yet-cached chapter with bounded concurrency (a handful at a time, not all
    /// at once -- hammering a small book-source site with hundreds of simultaneous requests is
    /// both rude and likely to trip anti-bot protection) and saves each to `ChapterCacheStore` as
    /// it completes. Skips chapters already downloaded so re-running (e.g. after a previous
    /// download was cancelled partway) resumes rather than re-fetching everything.
    private func downloadRemainingChapters() async {
        let alreadyDownloaded = (try? await env.chapterCacheStore.downloadedIndices(bookUrl: bookUrl)) ?? []
        let remaining = previewChapters.filter { !alreadyDownloaded.contains($0.index) }
        downloadProgress = alreadyDownloaded.count

        let concurrency = 4
        var offset = 0
        while offset < remaining.count {
            if Task.isCancelled { break }
            let batch = Array(remaining[offset..<min(offset + concurrency, remaining.count)])
            await withTaskGroup(of: Void.self) { group in
                for chapter in batch {
                    group.addTask {
                        guard let content = try? await ContentService.fetchContent(
                            source: source, chapter: chapter, httpClient: env.httpClient
                        ) else { return }
                        try? await env.chapterCacheStore.save(bookUrl: bookUrl, index: chapter.index, content: content)
                    }
                }
            }
            offset += batch.count
            downloadProgress = alreadyDownloaded.count + offset
        }
        await refreshDownloadedCount()
    }

    private func deleteCache() async {
        try? await env.chapterCacheStore.removeBook(bookUrl: bookUrl)
        downloadedCount = 0
    }

    private func setCover(_ newCoverUrl: String) async {
        try? await env.shelfStore.setCoverUrl(bookUrl: bookUrl, coverUrl: newCoverUrl)
        shelfCoverUrl = newCoverUrl
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
