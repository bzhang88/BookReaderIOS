import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import Persistence

struct ShelfView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var books: [ShelfBook] = []
    @State private var changeSourceTarget: ShelfBook?
    @State private var detailTarget: ShelfBook?
    @State private var groupPickerTarget: ShelfBook?
    @State private var isAutoGrouping = false
    @State private var isSelecting = false
    @State private var selectedBookUrls: Set<String> = []
    @State private var isShowingBatchGroupPicker = false
    @State private var isShowingBatchExportSheet = false
    @State private var batchExportItems: [Any] = []
    @State private var isBatchExporting = false

    /// Sections books by `group` -- a mix of names assigned by the "自动分组" tag-rule sweep and
    /// ones set manually via the row's "设置分组" menu; both write the same field (see `ShelfBook
    /// .group`'s doc comment), so there's no separate "manual group" data model to keep in sync.
    /// Un-grouped books land in a synthetic "未分组" section, sorted last.
    private var groupedSections: [(key: String, books: [ShelfBook])] {
        let grouped = Dictionary(grouping: books) { book -> String in
            let trimmed = book.group?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "未分组" : trimmed
        }
        return grouped.sorted { lhs, rhs in
            if lhs.key == "未分组" { return false }
            if rhs.key == "未分组" { return true }
            return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
        }.map { (key: $0.key, books: $0.value) }
    }

    private var hasAnyGroup: Bool {
        books.contains { !($0.group?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
    }

    private var existingGroupNames: [String] {
        groupedSections.map(\.key).filter { $0 != "未分组" }
    }

    var body: some View {
        NavigationStack {
            List {
                if books.isEmpty {
                    ContentUnavailableView(
                        "书架是空的", systemImage: "books.vertical",
                        description: Text("点右上角搜索图标找一本书，加入书架")
                    )
                } else if hasAnyGroup {
                    ForEach(groupedSections, id: \.key) { section in
                        Section(header: Text(section.key)) {
                            ForEach(section.books) { book in
                                bookRow(book)
                            }
                            .onDelete(perform: isSelecting ? nil : { offsets in delete(offsets.map { section.books[$0] }) })
                        }
                    }
                } else {
                    ForEach(books) { book in
                        bookRow(book)
                    }
                    .onDelete(perform: isSelecting ? nil : { offsets in delete(offsets.map { books[$0] }) })
                }
            }
            .navigationTitle("书架")
            .toolbar { toolbarContent }
            .task { await reload() }
            .refreshable { await reload() }
            .navigationDestination(isPresented: Binding(
                get: { detailTarget != nil },
                set: { if !$0 { detailTarget = nil } }
            )) {
                if let detailTarget {
                    ShelfBookDetailView(book: detailTarget)
                }
            }
            .sheet(item: $changeSourceTarget) { book in
                NavigationStack {
                    ChangeSourceView(
                        currentBookSourceUrl: book.bookSourceUrl, bookName: book.name, bookAuthor: book.author
                    ) { newSource, match in
                        await switchSource(of: book, to: newSource, match: match)
                    }
                }
            }
            .sheet(item: $groupPickerTarget) { book in
                ShelfGroupPickerView(existingGroups: existingGroupNames) { newGroup in
                    await setGroup(of: book, to: newGroup)
                }
            }
            .sheet(isPresented: $isShowingBatchGroupPicker) {
                ShelfGroupPickerView(existingGroups: existingGroupNames) { newGroup in
                    await batchSetGroup(to: newGroup)
                }
            }
            .sheet(isPresented: $isShowingBatchExportSheet) {
                ShareSheet(items: batchExportItems)
            }
        }
    }

    // Broken out of `body` into its own `@ToolbarContentBuilder` property (rather than inlined in
    // `.toolbar { }`) for the same reason `SourceCheckView` needed splitting into sub-views this
    // session: a real "compiler unable to type-check this expression in reasonable time" build
    // break that Windows-local `swift test` can never catch, only actually compiling the App
    // target (i.e. the macOS CI runners) can. Keeping each toolbar section as its own small
    // expression avoids relearning that lesson here too.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(isSelecting ? "完成" : "选择") {
                isSelecting.toggle()
                if !isSelecting { selectedBookUrls.removeAll() }
            }
            .disabled(books.isEmpty)
        }
        ToolbarItem(placement: .primaryAction) {
            NavigationLink {
                GlobalSearchView()
            } label: {
                Label("搜索", systemImage: "magnifyingglass")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await autoGroup() }
            } label: {
                if isAutoGrouping {
                    ProgressView()
                } else {
                    Label("自动分组", systemImage: "tag")
                }
            }
            .disabled(isAutoGrouping || books.isEmpty)
        }
        ToolbarItem(placement: .primaryAction) {
            NavigationLink {
                LocalBookListView()
            } label: {
                Label("本地书籍", systemImage: "doc.text")
            }
        }
        if isSelecting {
            batchActionsToolbarContent
        }
    }

    @ToolbarContentBuilder
    private var batchActionsToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Text("已选 \(selectedBookUrls.count) 本")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("移动分组") { isShowingBatchGroupPicker = true }
                .disabled(selectedBookUrls.isEmpty)
            Spacer()
            if isBatchExporting {
                ProgressView()
            } else {
                Button("导出") { batchExport() }
                    .disabled(selectedBookUrls.isEmpty)
            }
            Spacer()
            Button("删除", role: .destructive) { batchDelete() }
                .disabled(selectedBookUrls.isEmpty)
        }
    }

    @ViewBuilder
    private func bookRow(_ book: ShelfBook) -> some View {
        if isSelecting {
            Button {
                toggleSelection(book)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selectedBookUrls.contains(book.bookUrl) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedBookUrls.contains(book.bookUrl) ? Color.accentColor : Color.secondary)
                    bookRowContent(book)
                }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                ShelfBookResumeView(book: book)
            } label: {
                bookRowContent(book)
            }
            .swipeActions(edge: .leading) {
                Button {
                    changeSourceTarget = book
                } label: {
                    Label("换源", systemImage: "arrow.triangle.2.circlepath")
                }
                .tint(.orange)
            }
            .contextMenu {
                Button {
                    detailTarget = book
                } label: {
                    Label("详情", systemImage: "info.circle")
                }
                Button {
                    changeSourceTarget = book
                } label: {
                    Label("换源", systemImage: "arrow.triangle.2.circlepath")
                }
                Button {
                    groupPickerTarget = book
                } label: {
                    Label("设置分组", systemImage: "folder")
                }
            }
        }
    }

    @ViewBuilder
    private func bookRowContent(_ book: ShelfBook) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(book.name).font(.headline)
                if let group = book.group, !group.isEmpty {
                    Text(group)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
            if let author = book.author, !author.isEmpty {
                Text(author).font(.subheadline).foregroundStyle(.secondary)
            }
            if let title = book.lastReadChapterTitle {
                Text("上次读到: \(title)").font(.caption).foregroundStyle(.secondary)
            } else if let last = book.lastChapterTitle, !last.isEmpty {
                Text("最新: \(last)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func toggleSelection(_ book: ShelfBook) {
        if selectedBookUrls.contains(book.bookUrl) {
            selectedBookUrls.remove(book.bookUrl)
        } else {
            selectedBookUrls.insert(book.bookUrl)
        }
    }

    private func reload() async {
        let all = (try? await env.shelfStore.all()) ?? []
        books = all.sorted { ($0.lastReadAt ?? $0.addedAt) > ($1.lastReadAt ?? $1.addedAt) }
    }

    /// Sets (or clears, when `newGroup` is nil) one book's group directly -- shares `setGroups`
    /// with the batch auto-grouping sweep rather than a separate single-book store method, since
    /// the underlying write is identical either way.
    private func setGroup(of book: ShelfBook, to newGroup: String?) async {
        try? await env.shelfStore.setGroups([book.bookUrl: newGroup])
        await reload()
    }

    /// Matches every shelf book against the user's enabled tag-group rules and saves the results in
    /// one batch. Manual/on-demand rather than automatic-on-reload -- running regexes over every
    /// shelf book on every launch would be wasted work for a shelf that rarely changes.
    private func autoGroup() async {
        isAutoGrouping = true
        defer { isAutoGrouping = false }
        let rules = (try? await env.tagGroupRuleStore.enabled()) ?? []
        guard !rules.isEmpty else { return }
        var groups: [String: String?] = [:]
        for book in books {
            groups[book.bookUrl] = TagGroupRuleApplier.matchGroup(
                rules, name: book.name, author: book.author, intro: book.intro
            )
        }
        try? await env.shelfStore.setGroups(groups)
        await reload()
    }

    private func delete(_ toDelete: [ShelfBook]) {
        Task {
            for book in toDelete {
                try? await env.shelfStore.remove(bookUrl: book.bookUrl)
            }
            await reload()
        }
    }

    /// Applies one group to every selected book in a single batch write -- shares `setGroups` with
    /// both the auto-grouping sweep and the single-row picker, since all three are just "write this
    /// group value for these book URLs" with a different source for which URLs to write.
    private func batchSetGroup(to newGroup: String?) async {
        var updates: [String: String?] = [:]
        for bookUrl in selectedBookUrls {
            updates[bookUrl] = newGroup
        }
        try? await env.shelfStore.setGroups(updates)
        exitSelection()
        await reload()
    }

    private func batchDelete() {
        let toDelete = books.filter { selectedBookUrls.contains($0.bookUrl) }
        Task {
            for book in toDelete {
                try? await env.shelfStore.remove(bookUrl: book.bookUrl)
            }
            exitSelection()
            await reload()
        }
    }

    /// Exports every selected book that has at least one cached chapter, skipping the rest (a book
    /// with zero downloaded chapters has nothing to export) -- unlike `BookDetailView`'s single-book
    /// export, this doesn't require the *whole* book to be cached first, since gating an entire
    /// batch action on every selected book being 100% downloaded would make it rarely usable.
    private func batchExport() {
        let toExport = books.filter { selectedBookUrls.contains($0.bookUrl) }
        isBatchExporting = true
        Task {
            var items: [Any] = []
            for book in toExport {
                if let url = await exportedFileURL(for: book) {
                    items.append(url)
                }
            }
            isBatchExporting = false
            guard !items.isEmpty else { return }
            batchExportItems = items
            isShowingBatchExportSheet = true
        }
    }

    private func exportedFileURL(for book: ShelfBook) async -> URL? {
        let sources = (try? await env.bookSourceStore.all()) ?? []
        guard let source = sources.first(where: { $0.bookSourceUrl == book.bookSourceUrl }) else { return nil }
        guard let chapters = try? await TocService.fetchChapterList(source: source, tocURL: book.tocUrl, httpClient: env.httpClient),
              !chapters.isEmpty else { return nil }

        var chapterTexts: [(title: String, text: String)] = []
        for chapter in chapters {
            guard let content = try? await env.chapterCacheStore.chapter(bookUrl: book.bookUrl, index: chapter.index) else { continue }
            chapterTexts.append((title: chapter.title, text: content.text))
        }
        guard !chapterTexts.isEmpty else { return nil }

        let combined = TxtExporter.combine(bookTitle: book.name, chapters: chapterTexts)
        let fileName = TxtExporter.sanitizedFileName(book.name)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).txt")
        guard (try? combined.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        return url
    }

    private func exitSelection() {
        selectedBookUrls.removeAll()
        isSelecting = false
    }

    /// Swaps a shelf entry to a different source for the same book. The chapter *index* carries
    /// over as a best-effort approximation (chapter numbering is usually close enough across
    /// sources for the same book), but the character offset resets to 0 -- the old offset was
    /// measured against the old source's own text extraction, which won't line up with the new
    /// source's formatting/pagination of the same content.
    private func switchSource(of oldBook: ShelfBook, to newSource: BookSource, match: SearchResult) async {
        let bookInfo = try? await BookInfoService.fetchBookInfo(source: newSource, bookURL: match.bookUrl, httpClient: env.httpClient)
        let newBook = ShelfBook(
            bookSourceUrl: newSource.bookSourceUrl,
            bookUrl: match.bookUrl,
            name: bookInfo?.name ?? match.name,
            author: bookInfo?.author ?? match.author,
            coverUrl: bookInfo?.coverUrl ?? match.coverUrl,
            intro: bookInfo?.intro ?? match.intro,
            tocUrl: bookInfo?.tocUrl ?? match.bookUrl,
            lastChapterTitle: bookInfo?.lastChapter ?? match.lastChapter,
            addedAt: oldBook.addedAt,
            lastReadChapterIndex: oldBook.lastReadChapterIndex,
            lastReadChapterTitle: oldBook.lastReadChapterTitle,
            lastReadCharacterOffset: 0,
            lastReadAt: oldBook.lastReadAt
        )
        try? await env.shelfStore.remove(bookUrl: oldBook.bookUrl)
        try? await env.shelfStore.addOrUpdate(newBook)
        await reload()
    }
}

/// Resolves a shelf entry's originating book source and fetches its chapter list directly, then
/// hands off straight to `ReaderView` -- deliberately does *not* route through `TocView`'s own List
/// UI (unlike the "查看目录"/"立即阅读" entry points elsewhere, which legitimately want to show a
/// browsable list). Real-device feedback was that tapping a shelf book felt like it went "through"
/// the table of contents before landing in the reader; fetching chapters here and rendering
/// `ReaderView` the moment they're ready means that list is never constructed at all for this path,
/// not just hidden behind a loading overlay.
struct ShelfBookResumeView: View {
    let book: ShelfBook

    @EnvironmentObject private var env: AppEnvironment
    @State private var source: BookSource?
    @State private var chapters: [BookChapter] = []
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let source, !chapters.isEmpty {
                ReaderView(
                    source: source, bookUrl: book.bookUrl, tocUrl: book.tocUrl, chapters: chapters,
                    currentIndex: resumeIndex, bookTitle: book.name
                )
            } else if let errorMessage {
                ContentUnavailableView("无法打开", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ProgressView("正在打开…")
            }
        }
        .task { await load() }
    }

    /// Falls back to the first chapter both when this book has never been read (`lastReadChapterIndex
    /// == nil`) and when a stored index no longer lines up with a freshly-fetched chapter list (the
    /// source's chapter count can shift between visits) -- either way, landing in the reader at
    /// chapter 1 is more useful than an error.
    private var resumeIndex: Int {
        book.lastReadChapterIndex.flatMap { chapters.indices.contains($0) ? $0 : nil } ?? 0
    }

    private func load() async {
        let sources = (try? await env.bookSourceStore.all()) ?? []
        guard let match = sources.first(where: { $0.bookSourceUrl == book.bookSourceUrl }) else {
            errorMessage = "找不到这本书对应的书源，可能已被删除"
            return
        }
        source = match
        do {
            let fetched = try await TocService.fetchChapterList(source: match, tocURL: book.tocUrl, httpClient: env.httpClient)
            if fetched.isEmpty {
                errorMessage = "没有找到章节"
            } else {
                chapters = fetched
            }
        } catch {
            errorMessage = "\(error)"
        }
    }
}

/// Same source-resolution as `ShelfBookResumeView`, but hands off to `BookDetailView` instead of
/// jumping straight into reading -- reachable via a shelf row's long-press menu ("详情"), matching
/// Legado's own shelf context menu.
struct ShelfBookDetailView: View {
    let book: ShelfBook

    @EnvironmentObject private var env: AppEnvironment
    @State private var source: BookSource?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let source {
                BookDetailView(source: source, shelfBook: book)
            } else if let errorMessage {
                ContentUnavailableView("无法打开", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ProgressView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        let sources = (try? await env.bookSourceStore.all()) ?? []
        if let match = sources.first(where: { $0.bookSourceUrl == book.bookSourceUrl }) {
            source = match
        } else {
            errorMessage = "找不到这本书对应的书源，可能已被删除"
        }
    }
}
