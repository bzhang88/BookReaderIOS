import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import Persistence

/// Searches other enabled sources by book title and groups the results (reusing the same
/// `SearchResultGrouper`/`GroupedSearchResult` machinery `GlobalSearchView` uses), splitting them
/// into "同一本书" (exact name+author match -- genuine alternate sources for switching) and "其他相关结果"
/// (everything else the title search turned up). Earlier version only ever showed exact matches,
/// which meant a book that only existed on one source was simply unfindable here; real-device
/// feedback specifically asked for the broader "what else is out there" discovery this section
/// provides, matching Legado's own change-source screen (which shows near-matches too, not just
/// exact ones).
struct ChangeSourceView: View {
    let currentBookSourceUrl: String
    let bookName: String
    let bookAuthor: String?
    let onSourceSelected: (BookSource, SearchResult) async -> Void

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var sources: [BookSource] = []
    @State private var groups: [GroupedSearchResult] = []
    @State private var isSearching = false
    @State private var hasSearchedOnce = false
    @State private var isSwitching = false
    @State private var pickerGroup: GroupedSearchResult?
    // Real usage feedback (a Legado-comparison pass): with several exact-match sources to pick
    // from, there was no way to tell which one actually has the most chapters -- Legado's own
    // change-source screen fetches each candidate's TOC to compare completeness (word/chapter
    // count), the standard way to pick "which mirror has the fullest translation" instead of
    // guessing from the source name alone. `SearchResult.wordCount` (already shown on each card)
    // is the *source's own self-reported* figure -- inconsistent formatting across sources, and
    // sometimes just stale -- so this fetches the real, current chapter count instead. Keyed by
    // `bookUrl` (unique per candidate within one picker sheet), not `bookSourceUrl` (`bookUrl`
    // is what `SearchResult` actually varies by; a source could theoretically be re-used, though
    // that doesn't happen in practice here).
    @State private var chapterCounts: [String: Int] = [:]
    @State private var isLoadingChapterCounts = false

    private var exactGroups: [GroupedSearchResult] {
        groups.filter(isExactMatch)
    }
    private var otherGroups: [GroupedSearchResult] {
        groups.filter { !isExactMatch($0) }
    }

    var body: some View {
        List {
            if !exactGroups.isEmpty {
                Section("同一本书") {
                    ForEach(exactGroups) { group in
                        resultRow(group)
                    }
                }
            }
            if !otherGroups.isEmpty {
                Section("其他相关结果") {
                    ForEach(otherGroups) { group in
                        resultRow(group)
                    }
                }
            }
        }
        .overlay {
            if isSearching && groups.isEmpty {
                ProgressView("正在其他书源里查找…")
            } else if isSwitching {
                ProgressView("正在切换…")
            } else if hasSearchedOnce && !isSearching && groups.isEmpty {
                ContentUnavailableView(
                    "没有找到其他源", systemImage: "arrow.triangle.2.circlepath",
                    description: Text("已启用的其他书源里没搜到相关结果")
                )
            }
        }
        .navigationTitle("换源")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pickerGroup) { group in
            NavigationStack {
                List(rankedEntries(for: group)) { entry in
                    Button {
                        pickerGroup = nil
                        switchTo(entry)
                    } label: {
                        BookResultCard(
                            name: entry.name, author: entry.author, coverUrl: entry.coverUrl,
                            wordCount: entry.wordCount, lastChapter: entry.lastChapter, intro: entry.intro,
                            trailingLabel: entry.bookSourceName, chapterCount: chapterCounts[entry.bookUrl]
                        )
                    }
                    .disabled(isSwitching)
                }
                .overlay {
                    if isLoadingChapterCounts {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                ProgressView("正在比较章节数…").font(.caption)
                                Spacer()
                            }
                            .padding(.bottom, 8)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .navigationTitle(group.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { pickerGroup = nil }
                    }
                }
            }
            .task(id: group.id) { await loadChapterCounts(for: group) }
        }
        .task { await search() }
    }

    /// Highest chapter count first once fetched; entries not fetched yet (still loading, or the
    /// fetch failed) keep their original relevance-ranked order and sort after anything with a
    /// known count -- never show as if they had zero chapters.
    private func rankedEntries(for group: GroupedSearchResult) -> [SearchResult] {
        group.entries.enumerated().sorted { lhs, rhs in
            let lhsCount = chapterCounts[lhs.element.bookUrl]
            let rhsCount = chapterCounts[rhs.element.bookUrl]
            switch (lhsCount, rhsCount) {
            case let (l?, r?): return l != r ? l > r : lhs.offset < rhs.offset
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    /// Fetches every candidate's TOC concurrently (bounded to this one group's entries, typically a
    /// handful -- not a whole-library sweep) purely to compare `chapters.count`; the chapters
    /// themselves are discarded once counted; `switchTo`'s own real TOC fetch (via
    /// `onSourceSelected`) still happens fresh afterward. Two real requests per candidate, not one:
    /// `SearchResult.bookUrl` is the book's *detail* page, not its TOC -- same two-step
    /// info-then-toc fetch (and the same `bookInfo?.tocUrl ?? match.bookUrl` fallback for a source
    /// whose detail-fetch fails) `ShelfView.switchSource` already uses when actually committing a
    /// source switch, just discarding the info instead of building a `ShelfBook` from it.
    private func loadChapterCounts(for group: GroupedSearchResult) async {
        isLoadingChapterCounts = true
        // Extracted once, on the MainActor, before entering the task group -- `env` itself is
        // `@MainActor`-isolated (see `AppEnvironment`), so it can't be touched from inside a child
        // task the way `httpClient` (a plain `Sendable` value once extracted) can. Matches
        // `MultiSourceSearchService.search`'s own established idiom of reading `env.httpClient` once
        // at the call site rather than inside `withTaskGroup`.
        let httpClient = env.httpClient
        await withTaskGroup(of: (String, Int?).self) { taskGroup in
            for entry in group.entries {
                guard chapterCounts[entry.bookUrl] == nil,
                      let source = sources.first(where: { $0.bookSourceUrl == entry.bookSourceUrl }) else { continue }
                taskGroup.addTask {
                    let bookInfo = try? await BookInfoService.fetchBookInfo(source: source, bookURL: entry.bookUrl, httpClient: httpClient)
                    let tocUrl = bookInfo?.tocUrl ?? entry.bookUrl
                    let chapters = try? await TocService.fetchChapterList(source: source, tocURL: tocUrl, httpClient: httpClient)
                    return (entry.bookUrl, chapters?.count)
                }
            }
            for await (bookUrl, count) in taskGroup {
                if let count { chapterCounts[bookUrl] = count }
            }
        }
        isLoadingChapterCounts = false
    }

    @ViewBuilder
    private func resultRow(_ group: GroupedSearchResult) -> some View {
        Button {
            if group.sourceCount > 1 {
                pickerGroup = group
            } else {
                switchTo(group.entries[0])
            }
        } label: {
            BookResultCard(
                name: group.name, author: group.author, coverUrl: group.coverUrl, wordCount: group.wordCount,
                lastChapter: group.lastChapter, intro: group.intro,
                trailingLabel: group.sourceCount > 1 ? "共 \(group.sourceCount) 个源" : group.entries[0].bookSourceName
            )
        }
        .disabled(isSwitching)
    }

    private func search() async {
        let all = (try? await env.bookSourceStore.enabled()) ?? []
        sources = all
        // Real bug found comparing against Legado: candidates used to be filtered only by URL, so a
        // same-titled result on an audio (`bookSourceType == 1`) or manga (`== 2`) source could be
        // offered as a "换源" target for a book still open in the text reader -- switching would feed
        // that source's rule output straight into `ReaderView` as prose. `?? 0` (text) is the safe
        // fallback if `currentBookSourceUrl` somehow isn't found among enabled sources: every current
        // caller of this view (reader/detail/shelf) only ever opens it for a text book.
        let currentType = all.first(where: { $0.bookSourceUrl == currentBookSourceUrl })?.bookSourceType ?? 0
        let candidates = all.filter { $0.bookSourceUrl != currentBookSourceUrl && $0.bookSourceType == currentType }
        guard !candidates.isEmpty else {
            hasSearchedOnce = true
            return
        }

        isSearching = true
        let stream = MultiSourceSearchService.search(sources: candidates, keyword: bookName, httpClient: env.httpClient)
        for await outcome in stream {
            groups = SearchResultGrouper.merge(outcome.results, into: groups)
        }
        groups = groups.rankedByRelevance(query: bookName)
        isSearching = false
        hasSearchedOnce = true
    }

    /// Real bug found comparing against Legado: this used to require raw string equality (`==`) on
    /// author after only whitespace trimming, so a source reporting "金庸 著" or "作者：金庸" failed
    /// the check and a genuinely valid alternate source got bucketed into "其他相关结果". Legado
    /// normalizes author via `AppPattern.authorRegex` (`^\s*作\s*者[:：\s]+|\s+著`) then matches with
    /// substring containment, not equality -- mirrored here on both sides (not just one), since
    /// either the known book's author or the search result's could carry the decoration depending on
    /// which source it originally came from.
    private static func normalizedAuthor(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = result.range(of: #"^\s*作\s*者[:：\s]+"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        if let range = result.range(of: #"\s+著$"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isExactMatch(_ group: GroupedSearchResult) -> Bool {
        let nameMatches = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            == bookName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bookAuthor, !bookAuthor.isEmpty else { return nameMatches }
        guard let groupAuthor = group.author, !groupAuthor.isEmpty else { return false }
        let cleanedGroup = Self.normalizedAuthor(groupAuthor)
        let cleanedTarget = Self.normalizedAuthor(bookAuthor)
        return nameMatches && (cleanedGroup.contains(cleanedTarget) || cleanedTarget.contains(cleanedGroup))
    }

    private func switchTo(_ match: SearchResult) {
        guard let newSource = sources.first(where: { $0.bookSourceUrl == match.bookSourceUrl }) else { return }
        isSwitching = true
        Task {
            await onSourceSelected(newSource, match)
            isSwitching = false
            dismiss()
        }
    }
}
