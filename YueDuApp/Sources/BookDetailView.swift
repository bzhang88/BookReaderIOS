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
///
/// Layout matches Legado_Max's real `BookInfoActivity` (confirmed by reading its actual XML/Kotlin,
/// not guessed): a full-bleed blurred cover backdrop with a scrim, a centered floating cover card,
/// a rounded-top content panel "sliding up" over the backdrop, a stack of icon info rows (some with
/// a trailing pill-shaped action button -- 来源+换源, 分组+改分组, 目录+查看), and a bottom-fixed
/// two-button bar (加入书架/移出书架 + 阅读). `source`/`bookUrl` are `@State` (not `let`) so 换源 can
/// swap them in place, the same technique `ReaderView` already uses for its own in-reader 换源.
struct BookDetailView: View {
    @State private var source: BookSource
    @State private var bookUrl: String
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
    @State private var shelfGroup: String?
    @State private var existingGroupNames: [String] = []
    @State private var isShowingCoverPicker = false
    @State private var isShowingChangeSource = false
    @State private var isShowingGroupPicker = false
    @State private var previewChapters: [BookChapter] = []
    @State private var downloadedCount = 0
    @State private var isDownloading = false
    @State private var downloadProgress = 0
    @State private var downloadTask: Task<Void, Never>?
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var isShowingExportSheet = false
    // Real bug found comparing against Legado: `switchSource` used to swallow a failed re-fetch via
    // `try?` and still commit `source`/`bookUrl` to the new source regardless -- with `bookInfo` left
    // `nil`, the computed `name`/`author`/etc. properties silently fell back to this screen's
    // *original* `fallbackName`/`fallbackAuthor` (captured when it first opened), showing the new
    // source's label paired with the old book's stale data, with zero indication anything went wrong.
    // A separate alert (not the full-screen `errorMessage`, which would replace the still-valid,
    // already-loaded book info with an error screen) reports this without discarding what's on screen.
    @State private var switchSourceErrorMessage: String?

    init(
        source: BookSource, bookUrl: String, fallbackName: String, fallbackAuthor: String? = nil,
        fallbackCoverUrl: String? = nil, fallbackIntro: String? = nil, fallbackLastChapter: String? = nil
    ) {
        self._source = State(initialValue: source)
        self._bookUrl = State(initialValue: bookUrl)
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

    var body: some View {
        ZStack(alignment: .top) {
            backdrop
            ScrollView {
                VStack(spacing: 0) {
                    // Reserves room for the backdrop + floating cover card to show through above
                    // the panel, matching Legado's "cover peeking out above the sheet" look.
                    Color.clear.frame(height: 190)
                    contentPanel
                }
            }
            coverCard
        }
        .ignoresSafeArea(edges: .top)
        .overlay {
            if isLoading { ProgressView() }
        }
        .safeAreaInset(edge: .bottom) {
            if !isLoading, errorMessage == nil {
                bottomActionBar
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $isShowingCoverPicker) {
            CoverPickerView(bookName: name) { newCoverUrl in
                await setCover(newCoverUrl)
            }
        }
        .sheet(isPresented: $isShowingChangeSource) {
            NavigationStack {
                ChangeSourceView(
                    currentBookSourceUrl: source.bookSourceUrl, bookName: name, bookAuthor: author
                ) { newSource, match in
                    await switchSource(to: newSource, match: match)
                }
            }
        }
        .sheet(isPresented: $isShowingGroupPicker) {
            ShelfGroupPickerView(existingGroups: existingGroupNames) { newGroup in
                await setGroup(newGroup)
            }
        }
        .sheet(isPresented: $isShowingExportSheet) {
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
        }
        .alert("换源失败", isPresented: Binding(
            get: { switchSourceErrorMessage != nil }, set: { if !$0 { switchSourceErrorMessage = nil } }
        )) {
            Button("好") { switchSourceErrorMessage = nil }
        } message: {
            Text(switchSourceErrorMessage ?? "")
        }
        .task { await load() }
    }

    // Split out of `body` into its own `@ToolbarContentBuilder` (rather than inlined in
    // `.toolbar { }`) for the same reason a couple of other views this session needed splitting: a
    // real SwiftUI "compiler unable to type-check this expression in reasonable time" build break
    // has already happened once from a body this size with this much nested-conditional content --
    // keeping each piece its own small expression avoids relearning that lesson here too.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                overflowMenuItems
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private var overflowMenuItems: some View {
        Button {
            isShowingCoverPicker = true
        } label: {
            Label("更换封面", systemImage: "photo")
        }
        if downloadedCount > 0 {
            if downloadedCount == previewChapters.count {
                Button {
                    Task { await exportTxt() }
                } label: {
                    Label("导出 txt", systemImage: "square.and.arrow.up")
                }
                Button {
                    Task { await exportEpub() }
                } label: {
                    Label("导出 epub", systemImage: "book.closed")
                }
            }
            Button(role: .destructive) {
                Task { await deleteCache() }
            } label: {
                Label("删除缓存", systemImage: "trash")
            }
        } else {
            Button {
                startDownload()
            } label: {
                Label("缓存全本", systemImage: "arrow.down.circle")
            }
        }
    }

    // MARK: - Backdrop + floating cover

    private var backdrop: some View {
        GeometryReader { proxy in
            AsyncImage(url: coverUrl.flatMap(URL.init(string:))) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: proxy.size.width, height: 340)
            .blur(radius: 20)
            .clipped()
            .overlay(Color.black.opacity(0.45))
        }
        .frame(height: 340)
    }

    private var coverCard: some View {
        AsyncImage(url: coverUrl.flatMap(URL.init(string:))) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay { Image(systemName: "book.closed").foregroundStyle(.secondary) }
            }
        }
        .frame(width: 110, height: 154)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 8, y: 4)
        .padding(.top, 96)
        .onLongPressGesture {
            isShowingCoverPicker = true
        }
    }

    // MARK: - Content panel

    private var contentPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let errorMessage {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                Text(name)
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)

                if let kind = bookInfo?.kind, !kind.isEmpty {
                    Text(kind)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                VStack(alignment: .leading, spacing: 10) {
                    if let author, !author.isEmpty {
                        infoRow(icon: "person.fill", text: author)
                    }
                    infoRow(icon: "globe", text: "来源: \(source.bookSourceName)") {
                        Button("换源") { isShowingChangeSource = true }
                            .buttonStyle(.pillAction)
                    }
                    if let wordCount = bookInfo?.wordCount, !wordCount.isEmpty {
                        infoRow(icon: "textformat.123", text: "字数: \(wordCount)")
                    }
                    if isInShelf {
                        infoRow(icon: "folder", text: "分组: \(shelfGroup?.isEmpty == false ? shelfGroup! : "未分组")") {
                            Button("改分组") { isShowingGroupPicker = true }
                                .buttonStyle(.pillAction)
                        }
                    }
                    // Real bug found comparing against Legado: the `bookInfo == nil` branch here used
                    // to fall back to `fallbackLastChapter` -- the source's *latest chapter* title,
                    // not reading progress -- and label it "上次读到" (last read to). That branch was
                    // only ever reachable through `switchSource`'s old silent-failure bug (see its own
                    // doc comment); now that `switchSource` can't leave `bookInfo` nil while this
                    // content panel is showing, `shelfLastReadTitle` is the only value this could ever
                    // correctly show.
                    if isInShelf, let lastRead = shelfLastReadTitle {
                        infoRow(icon: "clock", text: "上次读到: \(lastRead)")
                    }
                    if !previewChapters.isEmpty {
                        infoRow(icon: "list.bullet", text: "共 \(previewChapters.count) 章") {
                            NavigationLink {
                                TocView(
                                    source: source, tocURL: bookInfo?.tocUrl ?? "", bookUrl: bookUrl, bookTitle: name,
                                    bookAuthor: author, currentChapterIndex: shelfLastReadChapterIndex
                                )
                            } label: {
                                Text("查看")
                            }
                            .buttonStyle(.pillAction)
                        }
                    }
                }

                if downloadedCount > 0 {
                    downloadStatusRow
                }

                if let intro, !intro.isEmpty {
                    Divider()
                    Text(intro).font(.body)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 24)
                .fill(.background)
        )
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary).frame(width: 16)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func infoRow<Trailing: View>(icon: String, text: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary).frame(width: 16)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
    }

    @ViewBuilder
    private var downloadStatusRow: some View {
        if isDownloading {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(downloadProgress), total: Double(max(previewChapters.count, 1)))
                HStack {
                    Text("缓存中 \(downloadProgress)/\(previewChapters.count)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("取消") { downloadTask?.cancel() }.font(.caption)
                }
            }
        } else {
            HStack {
                Label("已缓存 \(downloadedCount)/\(previewChapters.count) 章", systemImage: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Spacer()
                if downloadedCount < previewChapters.count {
                    Button("继续缓存") { startDownload() }.font(.caption)
                } else if isExporting {
                    ProgressView().font(.caption)
                }
            }
        }
    }

    // MARK: - Bottom action bar

    private var bottomActionBar: some View {
        HStack(spacing: 0) {
            Button {
                Task { await toggleShelf() }
            } label: {
                Text(isInShelf ? "移出书架" : "加入书架")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(bookInfo == nil)

            if let bookInfo {
                NavigationLink {
                    // Real usage bug, now fixed: this used to hardcode `resumeChapterIndex: 0`
                    // unconditionally, so re-opening a book you'd already made progress in always
                    // restarted at chapter 1 instead of resuming -- and combined with `TocView`'s own
                    // auto-navigate re-firing on `.task` re-runs (see its doc comment), tapping back
                    // out of the reader would bounce straight back into that same wrong chapter,
                    // making it feel like "back" didn't work at all. `shelfLastReadChapterIndex ?? 0`
                    // resumes real progress when there is any, and still starts a genuinely new book
                    // at chapter 1 (not `nil`, which would leave `TocView` on a bare list with no
                    // auto-navigate at all -- "阅读" should always actually start reading).
                    TocView(
                        source: source, tocURL: bookInfo.tocUrl, bookUrl: bookUrl, bookTitle: name,
                        bookAuthor: author, resumeChapterIndex: shelfLastReadChapterIndex ?? 0,
                        currentChapterIndex: shelfLastReadChapterIndex
                    )
                } label: {
                    Text("阅读").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Data

    /// Populated by `load()` (and refreshed by `switchSource`) from the live shelf entry.
    @State private var shelfLastReadTitle: String?
    /// Drives the "阅读" button's `resumeChapterIndex` -- see that button's own doc comment for the
    /// real bug this fixes (it used to always hardcode `0`, ignoring any actual saved progress).
    @State private var shelfLastReadChapterIndex: Int?

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let info = try await BookInfoService.fetchBookInfo(source: source, bookURL: bookUrl, httpClient: env.httpClient)
            bookInfo = info
            let allShelfBooks = (try? await env.shelfStore.all()) ?? []
            let existingShelfBook = allShelfBooks.first { $0.bookUrl == bookUrl }
            isInShelf = existingShelfBook != nil
            shelfCoverUrl = existingShelfBook?.coverUrl
            shelfGroup = existingShelfBook?.group
            shelfLastReadTitle = existingShelfBook?.lastReadChapterTitle
            shelfLastReadChapterIndex = existingShelfBook?.lastReadChapterIndex
            existingGroupNames = Array(Set(allShelfBooks.compactMap {
                let trimmed = $0.group?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (trimmed?.isEmpty ?? true) ? nil : trimmed
            })).sorted()
            previewChapters = (try? await TocService.fetchChapterList(
                source: source, tocURL: info.tocUrl, httpClient: env.httpClient
            )) ?? []
            if isInShelf {
                try? await env.shelfStore.updateTotalChapterCount(bookUrl: bookUrl, count: previewChapters.count)
            }
            await refreshDownloadedCount()
        } catch {
            errorMessage = FriendlyError.message(for: error)
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
                            source: source, chapter: chapter, httpClient: env.httpClient,
                            nextChapterUrl: previewChapters.indices.contains(chapter.index + 1)
                                ? previewChapters[chapter.index + 1].url : nil
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

    /// Only offered once every previewed chapter is cached (see the "..." menu's condition) --
    /// there's no server-side export endpoint, so re-assembling the book requires every chapter to
    /// already be sitting in `ChapterCacheStore`.
    private func exportTxt() async {
        isExporting = true
        defer { isExporting = false }
        var chapterTexts: [(title: String, text: String)] = []
        for chapter in previewChapters {
            guard let content = try? await env.chapterCacheStore.chapter(bookUrl: bookUrl, index: chapter.index) else { continue }
            chapterTexts.append((title: chapter.title, text: content.text))
        }
        guard !chapterTexts.isEmpty else { return }
        let combined = TxtExporter.combine(bookTitle: name, chapters: chapterTexts)
        let fileName = TxtExporter.sanitizedFileName(name)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).txt")
        guard (try? combined.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        exportURL = url
        isShowingExportSheet = true
    }

    /// Same cached-chapters-only precondition as `exportTxt` -- EPUB is the other local export
    /// format real e-readers expect (this app previously only offered TXT).
    private func exportEpub() async {
        isExporting = true
        defer { isExporting = false }
        var chapterTexts: [(title: String, text: String)] = []
        for chapter in previewChapters {
            guard let content = try? await env.chapterCacheStore.chapter(bookUrl: bookUrl, index: chapter.index) else { continue }
            chapterTexts.append((title: chapter.title, text: content.text))
        }
        guard !chapterTexts.isEmpty else { return }
        let data = EpubExporter.build(bookTitle: name, author: author, chapters: chapterTexts)
        let fileName = TxtExporter.sanitizedFileName(name)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).epub")
        guard (try? data.write(to: url)) != nil else { return }
        exportURL = url
        isShowingExportSheet = true
    }

    private func setCover(_ newCoverUrl: String) async {
        try? await env.shelfStore.setCoverUrl(bookUrl: bookUrl, coverUrl: newCoverUrl)
        shelfCoverUrl = newCoverUrl
    }

    private func setGroup(_ newGroup: String?) async {
        try? await env.shelfStore.setGroups([bookUrl: newGroup])
        shelfGroup = newGroup
    }

    /// Toggles shelf membership both ways -- Legado's own detail page button is a real toggle
    /// (加入书架/移出书架), not the add-only button this screen had before.
    private func toggleShelf() async {
        if isInShelf {
            try? await env.shelfStore.remove(bookUrl: bookUrl)
            isInShelf = false
            return
        }
        guard let bookInfo else { return }
        let book = ShelfBook(
            bookSourceUrl: source.bookSourceUrl, bookUrl: bookUrl,
            name: bookInfo.name ?? fallbackName, author: bookInfo.author ?? fallbackAuthor,
            coverUrl: bookInfo.coverUrl ?? fallbackCoverUrl, intro: bookInfo.intro ?? fallbackIntro,
            tocUrl: bookInfo.tocUrl, lastChapterTitle: bookInfo.lastChapter ?? fallbackLastChapter,
            totalChapterCount: previewChapters.isEmpty ? nil : previewChapters.count
        )
        try? await env.shelfStore.addOrUpdate(book)
        isInShelf = true
    }

    /// In-place source switch (mirrors `ReaderView.switchSource`): re-fetches book info from the
    /// new source, updates local `@State` so the whole screen re-renders against it, and -- if this
    /// book is on the shelf -- replaces the shelf entry (chapter index/progress don't carry over
    /// meaningfully across sources with different chapter counts, so they reset).
    private func switchSource(to newSource: BookSource, match: SearchResult) async {
        let oldBookUrl = bookUrl
        // Gating on a successful info fetch (rather than falling back to `try?` + `nil`) is the fix:
        // `source`/`bookUrl` are never committed to the new source unless the new book's own data is
        // actually in hand, so this screen can never show "new source name + old book data" again.
        // This also removes the old `newInfo?.tocUrl ?? match.bookUrl` fallback for the TOC fetch --
        // that only existed to paper over a failed info fetch, which now bails out before reaching it.
        guard let newInfo = try? await BookInfoService.fetchBookInfo(
            source: newSource, bookURL: match.bookUrl, httpClient: env.httpClient
        ) else {
            switchSourceErrorMessage = "无法获取新书源的书籍信息，换源已取消"
            return
        }
        source = newSource
        bookUrl = match.bookUrl
        bookInfo = newInfo
        previewChapters = (try? await TocService.fetchChapterList(
            source: newSource, tocURL: newInfo.tocUrl, httpClient: env.httpClient
        )) ?? []
        await refreshDownloadedCount()

        if let existing = try? await env.shelfStore.book(bookUrl: oldBookUrl) {
            let updated = ShelfBook(
                bookSourceUrl: newSource.bookSourceUrl,
                bookUrl: match.bookUrl,
                name: newInfo?.name ?? match.name,
                author: newInfo?.author ?? match.author,
                coverUrl: newInfo?.coverUrl ?? match.coverUrl,
                intro: newInfo?.intro ?? match.intro,
                tocUrl: newInfo?.tocUrl ?? match.bookUrl,
                lastChapterTitle: newInfo?.lastChapter ?? match.lastChapter,
                addedAt: existing.addedAt,
                group: existing.group,
                lastReadChapterIndex: nil,
                lastReadChapterTitle: nil,
                lastReadCharacterOffset: 0,
                lastReadAt: existing.lastReadAt,
                totalChapterCount: previewChapters.isEmpty ? nil : previewChapters.count
            )
            try? await env.shelfStore.remove(bookUrl: oldBookUrl)
            try? await env.shelfStore.addOrUpdate(updated)
            shelfCoverUrl = updated.coverUrl
            shelfGroup = updated.group
            shelfLastReadTitle = nil
            shelfLastReadChapterIndex = nil
        }
    }
}

/// Small rounded-pill button style for the info-row trailing actions (换源/改分组/查看) -- matches
/// Legado's small accent-colored pill buttons inline with each info row.
private struct PillActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.3 : 0.15), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }
}

extension ButtonStyle where Self == PillActionButtonStyle {
    fileprivate static var pillAction: PillActionButtonStyle { PillActionButtonStyle() }
}
