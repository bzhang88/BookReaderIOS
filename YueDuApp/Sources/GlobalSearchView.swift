import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import NetworkClient

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

    var body: some View {
        List {
            if isSearching || hasSearchedOnce {
                statusRow
            }
            ForEach(groups) { group in
                NavigationLink {
                    destination(for: group)
                } label: {
                    SearchResultRow(group: group)
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
        .task { sources = (try? await env.bookSourceStore.enabled()) ?? [] }
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

    private func startSearching() {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sources.isEmpty else { return }

        searchTask?.cancel()
        groups = []
        completedCount = 0
        failedCount = 0
        isSearching = true
        hasSearchedOnce = true

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
            groups = groups.rankedBySourceCount()
            isSearching = false
        }
    }

    private func stopSearching() {
        searchTask?.cancel()
        groups = groups.rankedBySourceCount()
        isSearching = false
    }
}

/// One search result card: cover, name, author, word count, latest chapter, a short intro, and
/// which/how-many sources found it -- the fields real book-source readers typically show on a
/// search results screen (word count instead of a chapter count, which would need fetching each
/// result's full table of contents -- far too expensive to do for every search hit).
private struct SearchResultRow: View {
    let group: GroupedSearchResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: group.coverUrl.flatMap(URL.init(string:))) { phase in
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
                Text(group.name).font(.headline).lineLimit(1)

                HStack(spacing: 6) {
                    if let author = group.author, !author.isEmpty {
                        Text(author)
                    }
                    if let wordCount = group.wordCount, !wordCount.isEmpty {
                        Text(wordCount)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let lastChapter = group.lastChapter, !lastChapter.isEmpty {
                    Text("最新: \(lastChapter)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let intro = group.intro, !intro.isEmpty {
                    Text(intro)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if group.sourceCount > 1 {
                    Text("共 \(group.sourceCount) 个源")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                } else {
                    Text(group.entries[0].bookSourceName)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Lets the user pick which of several sources to open a book from, when search found the same
/// book (by name + author) on more than one.
struct BookSourcePickerView: View {
    let group: GroupedSearchResult
    let resolveSource: (SearchResult) -> BookSource

    var body: some View {
        List(group.entries) { entry in
            NavigationLink {
                BookDetailView(source: resolveSource(entry), searchResult: entry)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.bookSourceName).font(.headline)
                    if let lastChapter = entry.lastChapter, !lastChapter.isEmpty {
                        Text(lastChapter).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
