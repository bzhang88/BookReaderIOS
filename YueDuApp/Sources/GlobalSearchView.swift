import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import NetworkClient
import Persistence

/// Searches every *enabled* book source concurrently (not one picked ahead of time), streaming
/// results in per-source as they arrive, with a visible way to stop early -- matches how these
/// apps are actually used: you search your whole library at once, not one source you have to
/// remember has the book, and some sources are slow/dead so waiting for all of them isn't
/// reasonable.
struct GlobalSearchView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var keyword: String = ""
    @State private var sources: [BookSource] = []
    @State private var groups: [GroupedSearchResult] = []
    @State private var completedCount = 0
    @State private var failedCount = 0
    @State private var isSearching = false
    @State private var hasSearchedOnce = false
    @State private var searchTask: Task<Void, Never>?
    @State private var sortMode: SearchSortMode = .sourceCount
    @State private var searchHistory: [String] = []
    @State private var shelfKeys: Set<String> = []

    var body: some View {
        List {
            if keyword.isEmpty {
                historySection
            }
            if isSearching || hasSearchedOnce {
                statusRow
            }
            ForEach(groups) { group in
                NavigationLink {
                    destination(for: group)
                } label: {
                    SearchResultRow(group: group, isInShelf: shelfKeys.contains(
                        GroupedSearchResult.groupKey(name: group.name, author: group.author)
                    ))
                }
            }
        }
        .overlay {
            if sources.isEmpty {
                ContentUnavailableView(
                    "没有已启用的书源", systemImage: "tray",
                    description: Text("去书源库导入并启用至少一个书源")
                )
            } else if hasSearchedOnce && !isSearching && groups.isEmpty {
                ContentUnavailableView.search(text: keyword)
            }
        }
        .navigationTitle("搜索")
        .searchable(text: $keyword, prompt: "搜索所有已启用的书源")
        .onSubmit(of: .search) { startSearching() }
        .toolbar {
            if hasSearchedOnce && !groups.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(SearchSortMode.allCases) { mode in
                            Button {
                                sortMode = mode
                            } label: {
                                if sortMode == mode {
                                    Label(mode.displayName, systemImage: "checkmark")
                                } else {
                                    Text(mode.displayName)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
        }
        .onChange(of: sortMode) { _, _ in applyRanking() }
        .task {
            sources = (try? await env.bookSourceStore.enabled()) ?? []
            await reloadHistory()
            await reloadShelfKeys()
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !searchHistory.isEmpty {
            Section {
                FlowChips(items: searchHistory) { term in
                    keyword = term
                    startSearching()
                }
            } header: {
                HStack {
                    Text("最近搜索")
                    Spacer()
                    Button("清空记录") {
                        Task {
                            try? await env.searchHistoryStore.clear()
                            await reloadHistory()
                        }
                    }
                    .font(.caption)
                }
            }
        }
    }

    /// A book found by only one source goes straight to its detail page; a book multiple sources
    /// agree on (same name + author) goes to a picker first, mirroring Legado's "共 N 个源" search
    /// entries -- since which of those sources is actually still working/fastest isn't known until
    /// you try one.
    @ViewBuilder
    private func destination(for group: GroupedSearchResult) -> some View {
        if group.sourceCount > 1 {
            BookSourcePickerView(group: group, resolveSource: resolveSource)
        } else {
            BookDetailView(source: resolveSource(group.entries[0]), searchResult: group.entries[0])
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack {
            if isSearching {
                ProgressView()
                Text("搜索中… \(completedCount)/\(sources.count) 个书源已完成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("停止搜索", role: .destructive) { stopSearching() }
                    .font(.caption)
            } else {
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summaryText: String {
        failedCount > 0
            ? "共找到 \(groups.count) 本书（\(failedCount) 个书源搜索失败）"
            : "共找到 \(groups.count) 本书"
    }

    private func resolveSource(_ result: SearchResult) -> BookSource {
        sources.first { $0.bookSourceUrl == result.bookSourceUrl }
            ?? BookSource(bookSourceUrl: result.bookSourceUrl, bookSourceName: result.bookSourceName)
    }

    private func reloadHistory() async {
        searchHistory = (try? await env.searchHistoryStore.recent()) ?? []
    }

    private func reloadShelfKeys() async {
        let shelfBooks = (try? await env.shelfStore.all()) ?? []
        shelfKeys = Set(shelfBooks.map { GroupedSearchResult.groupKey(name: $0.name, author: $0.author) })
    }

    /// Re-applies the current sort mode to whatever's already been collected -- called both once
    /// results settle and whenever the user changes `sortMode`, so switching sort order doesn't
    /// require re-running the search.
    private func applyRanking() {
        switch sortMode {
        case .sourceCount:
            groups = groups.rankedBySourceCount()
        case .relevance:
            groups = groups.rankedByRelevance(query: keyword)
        }
    }

    private func startSearching() {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sources.isEmpty else { return }

        searchTask?.cancel()
        groups = []
        completedCount = 0
        failedCount = 0
        isSearching = true
        hasSearchedOnce = true

        Task {
            try? await env.searchHistoryStore.record(trimmed)
            await reloadHistory()
        }

        searchTask = Task {
            let stream = MultiSourceSearchService.search(sources: sources, keyword: trimmed, httpClient: env.httpClient)
            for await outcome in stream {
                if Task.isCancelled { break }
                groups = SearchResultGrouper.merge(outcome.results, into: groups)
                completedCount += 1
                if outcome.errorDescription != nil { failedCount += 1 }
            }
            // Ranking only happens once results settle -- re-sorting on every incremental arrival
            // would make rows jump around mid-search, which reads as broken rather than "ranked."
            applyRanking()
            isSearching = false
        }
    }

    private func stopSearching() {
        searchTask?.cancel()
        applyRanking()
        isSearching = false
    }
}

/// Which order search results are displayed in -- by-source-count surfaces titles multiple sites
/// agree on (more likely a correctly-matched real book), but that alone buries a book that only
/// exists on one source, however well it matches the query; relevance mode fixes that by ranking
/// on title-match closeness first, source count only as a tiebreaker.
enum SearchSortMode: String, CaseIterable, Identifiable {
    case sourceCount, relevance

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sourceCount: return "源数量"
        case .relevance: return "相关度"
        }
    }
}

/// Wrapping row of tappable keyword chips (Legado's "最近搜索" style). SwiftUI has no built-in
/// flow-wrap container, and a custom `Layout` conformance is more machinery than a capped-length
/// history list warrants -- an adaptive `LazyVGrid` approximates the same "wrap to the next row"
/// look with none of that, close enough for a handful of short keyword chips.
private struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 60), spacing: 8, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    onTap(item)
                } label: {
                    Text(item)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One search result card: cover, name, author, word count, latest chapter, a short intro, and
/// which/how-many sources found it -- the fields real book-source readers typically show on a
/// search results screen (word count instead of a chapter count, which would need fetching each
/// result's full table of contents -- far too expensive to do for every search hit).
private struct SearchResultRow: View {
    let group: GroupedSearchResult
    var isInShelf: Bool = false

    var body: some View {
        BookResultCard(
            name: group.name, author: group.author, coverUrl: group.coverUrl, wordCount: group.wordCount,
            lastChapter: group.lastChapter, intro: group.intro,
            trailingLabel: group.sourceCount > 1 ? "共 \(group.sourceCount) 个源" : group.entries[0].bookSourceName,
            isInShelf: isInShelf
        )
    }
}

/// Shared card layout for a book result -- used both by the main search list (one card per grouped
/// title) and the per-source picker (one card per source's own copy of a title), so the two don't
/// duplicate the same cover/author/wordcount/intro layout.
struct BookResultCard: View {
    let name: String
    let author: String?
    let coverUrl: String?
    let wordCount: String?
    let lastChapter: String?
    let intro: String?
    let trailingLabel: String
    var isInShelf: Bool = false

    var body: some View {
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
            .frame(width: 60, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name).font(.headline).lineLimit(1)
                    if isInShelf {
                        Text("已在书架")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }

                HStack(spacing: 6) {
                    if let author, !author.isEmpty {
                        Text(author)
                    }
                    if let wordCount, !wordCount.isEmpty {
                        Text(wordCount)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let lastChapter, !lastChapter.isEmpty {
                    Text("最新: \(lastChapter)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let intro, !intro.isEmpty {
                    Text(intro)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(trailingLabel)
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Lets the user pick which of several sources to open a book from, when search found the same
/// book (by name + author) on more than one -- each row shows that source's own cover/author/intro
/// rather than just its name, since different sources sometimes have better covers or more
/// complete descriptions for the same book.
struct BookSourcePickerView: View {
    let group: GroupedSearchResult
    let resolveSource: (SearchResult) -> BookSource

    var body: some View {
        List(group.entries) { entry in
            NavigationLink {
                BookDetailView(source: resolveSource(entry), searchResult: entry)
            } label: {
                BookResultCard(
                    name: entry.name, author: entry.author, coverUrl: entry.coverUrl, wordCount: entry.wordCount,
                    lastChapter: entry.lastChapter, intro: entry.intro, trailingLabel: entry.bookSourceName
                )
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
