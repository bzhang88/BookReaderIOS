import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import Persistence

struct ShelfView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var books: [ShelfBook] = []
    @State private var changeSourceTarget: ShelfBook?
    @State private var isAutoGrouping = false

    var body: some View {
        NavigationStack {
            List {
                if books.isEmpty {
                    ContentUnavailableView(
                        "书架是空的", systemImage: "books.vertical",
                        description: Text("点右上角搜索图标找一本书，加入书架")
                    )
                }
                ForEach(books) { book in
                    NavigationLink {
                        ShelfBookResumeView(book: book)
                    } label: {
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
                    .swipeActions(edge: .leading) {
                        Button {
                            changeSourceTarget = book
                        } label: {
                            Label("换源", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .tint(.orange)
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("书架")
            .toolbar {
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
            }
            .task { await reload() }
            .refreshable { await reload() }
            .sheet(item: $changeSourceTarget) { book in
                NavigationStack {
                    ChangeSourceView(
                        currentBookSourceUrl: book.bookSourceUrl, bookName: book.name, bookAuthor: book.author
                    ) { newSource, match in
                        await switchSource(of: book, to: newSource, match: match)
                    }
                }
            }
        }
    }

    private func reload() async {
        let all = (try? await env.shelfStore.all()) ?? []
        books = all.sorted { ($0.lastReadAt ?? $0.addedAt) > ($1.lastReadAt ?? $1.addedAt) }
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

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { books[$0] }
        Task {
            for book in toDelete {
                try? await env.shelfStore.remove(bookUrl: book.bookUrl)
            }
            await reload()
        }
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

/// Resolves a shelf entry's originating book source, then hands off to `TocView` with a resume
/// index so tapping a shelf book jumps straight back into reading rather than re-browsing the TOC.
struct ShelfBookResumeView: View {
    let book: ShelfBook

    @EnvironmentObject private var env: AppEnvironment
    @State private var source: BookSource?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let source {
                TocView(
                    source: source, tocURL: book.tocUrl, bookUrl: book.bookUrl, bookTitle: book.name,
                    resumeChapterIndex: book.lastReadChapterIndex
                )
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
