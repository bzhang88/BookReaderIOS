import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import NetworkClient
import Persistence
import RuleEngine

/// Searches every *enabled* book source concurrently (not one picked ahead of time), streaming
/// results in per-source as they arrive, with a visible way to stop early -- matches how these
/// apps are actually used: you search your whole library at once, not one source you have to
/// remember has the book, and some sources are slow/dead so waiting for all of them isn't
/// reasonable.
struct GlobalSearchView: View {
    /// Real gap found comparing against Legado: `tvName`/`tvAuthor`/the kind chip on the real detail
    /// page all jump straight into a search for that value (`BookInfoActivity.kt`'s click handlers) --
    /// `BookDetailView`'s equivalents were inert. Same prefill-param pattern as `DictLookupView
    /// .initialWord`/`ChapterContentSearchView.initialKeyword`: seeds `keyword` and fires a search
    /// once sources are loaded, rather than landing on an empty search field the user has to retype.
    var initialKeyword: String = ""

    @EnvironmentObject private var env: AppEnvironment
    @State private var keyword: String = ""
    @State private var sources: [BookSource] = []
    @State private var groups: [GroupedSearchResult] = []
    @State private var completedCount = 0
    @State private var failedCount = 0
    // Real usage feedback: "3 个书源搜索失败" told you *a* number failed but nothing about which
    // ones or why, so a source that's actually broken (unsupported rule syntax, dead domain, ...)
    // was indistinguishable from one that just hit a transient network hiccup. Kept alongside
    // `failedCount` rather than derived from it since this needs the actual outcomes, not just a
    // tally.
    @State private var failedOutcomes: [MultiSourceSearchService.SourceOutcome] = []
    @State private var isShowingFailedSources = false
    @State private var isSearching = false
    @State private var hasSearchedOnce = false
    @State private var searchTask: Task<Void, Never>?
    // Real bug found comparing against Legado: `.sourceCount` used to be the default, ranking purely
    // by how many sources found a title and ignoring relevance entirely -- Legado's real search
    // (`SearchModel.mergeItems`) always ranks by title-match closeness first, source count only as a
    // same-tier tiebreaker, unconditionally (not a toggle). `.relevance` mode already implements that
    // correct ranking; it just wasn't the default.
    @State private var sortMode: SearchSortMode = .relevance
    @State private var searchHistory: [String] = []
    @State private var shelfKeys: Set<String> = []
    @State private var allShelfBooks: [ShelfBook] = []
    @State private var relevanceFilter: SearchRelevanceFilter = .all
    // Precomputed once per settled search (see `recomputeRelevanceBuckets`), not a computed
    // property re-run on every body evaluation -- similarity scoring is O(title length × keyword
    // length) per result, and the reference reading app's own search results can run into the
    // thousands, so recomputing all of them on every SwiftUI redraw would be real, avoidable work.
    @State private var relevanceBuckets: [SearchRelevanceFilter: [GroupedSearchResult]] = [:]

    init(initialKeyword: String = "") {
        self.initialKeyword = initialKeyword
        _keyword = State(initialValue: initialKeyword)
    }

    private var displayedGroups: [GroupedSearchResult] {
        relevanceBuckets[relevanceFilter] ?? groups
    }

    var body: some View {
        List {
            if !keyword.isEmpty && !hasSearchedOnce {
                shelfMatchSection
            }
            if keyword.isEmpty {
                historySection
            }
            if isSearching || hasSearchedOnce {
                statusRow
            }
            if hasSearchedOnce && !isSearching && !groups.isEmpty {
                relevanceFilterRow
            }
            ForEach(displayedGroups) { group in
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
        // `.navigationBarDrawer(displayMode: .always)` keeps the field permanently expanded in the
        // nav bar instead of collapsing to a search icon you have to tap first -- matches Legado's
        // own search screen, where the box is embedded in the title bar and always visible.
        .searchable(
            text: $keyword, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索所有已启用的书源"
        )
        .onSubmit(of: .search) { startSearching() }
        // Real bug found comparing against Legado: `hasSearchedOnce` used to only ever flip to
        // `true` (set once in `startSearching()`, never reset), so the "书架同名书籍" convenience
        // section permanently disappeared after the first search in a screen visit -- even after
        // clearing the field and typing a brand-new query. Legado's own equivalent re-shows this any
        // time the field is being retyped, regardless of past searches; clearing back to empty is the
        // natural point to reset here too.
        .onChange(of: keyword) { _, newValue in
            if newValue.isEmpty { hasSearchedOnce = false }
        }
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
            await reloadShelfBooks()
            if !initialKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                startSearching()
            }
        }
    }

    /// Live-filters the shelf as the user types, *before* they've actually submitted a search --
    /// matches Legado's own pre-search empty state, which shows "书架中同名书籍" above the search
    /// history so a book you already own surfaces immediately without waiting on a network search.
    @ViewBuilder
    private var shelfMatchSection: some View {
        let matches = allShelfBooks.filter { $0.name.localizedCaseInsensitiveContains(keyword) }
        if !matches.isEmpty {
            Section("书架中同名书籍") {
                ForEach(matches) { book in
                    NavigationLink {
                        ShelfBookResumeView(book: book)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.name).font(.headline)
                            if let author = book.author, !author.isEmpty {
                                Text(author).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
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
            } else if failedCount > 0 {
                Button {
                    isShowingFailedSources = true
                } label: {
                    Text("\(summaryText) · 查看详情")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $isShowingFailedSources) {
            FailedSourcesListView(outcomes: failedOutcomes)
        }
    }

    private var summaryText: String {
        failedCount > 0
            ? "共找到 \(groups.count) 本书（\(failedCount) 个书源搜索失败）"
            : "共找到 \(groups.count) 本书"
    }

    /// 精确/≥70%/<70%/全部 filter tabs, each showing a live count -- matches the reference reading
    /// app's own real search-results screen. A horizontally scrollable row rather than a fixed
    /// segmented control since the labels are asymmetric widths ("精确(0)" vs "<70%(3248)").
    @ViewBuilder
    private var relevanceFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchRelevanceFilter.allCases) { filter in
                    let count = relevanceBuckets[filter]?.count ?? 0
                    Button {
                        relevanceFilter = filter
                    } label: {
                        Text("\(filter.displayName)(\(count))")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                relevanceFilter == filter
                                    ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1),
                                in: Capsule()
                            )
                            .foregroundStyle(relevanceFilter == filter ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }

    private func resolveSource(_ result: SearchResult) -> BookSource {
        sources.first { $0.bookSourceUrl == result.bookSourceUrl }
            ?? BookSource(bookSourceUrl: result.bookSourceUrl, bookSourceName: result.bookSourceName)
    }

    private func reloadHistory() async {
        searchHistory = (try? await env.searchHistoryStore.recent()) ?? []
    }

    private func reloadShelfBooks() async {
        let shelfBooks = (try? await env.shelfStore.all()) ?? []
        allShelfBooks = shelfBooks
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
        recomputeRelevanceBuckets()
    }

    /// Buckets `groups` by title similarity to the search keyword -- matches the reference reading
    /// app's real 精确/≥70%/<70%/全部 tabs. Computed once here (see `relevanceBuckets`'s own doc
    /// comment for why this isn't a plain computed property) rather than per-row, so switching tabs
    /// is just a dictionary lookup.
    private func recomputeRelevanceBuckets() {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        var exact: [GroupedSearchResult] = []
        var high: [GroupedSearchResult] = []
        var low: [GroupedSearchResult] = []
        for group in groups {
            let ratio = TextSimilarity.ratio(group.name, trimmed)
            if ratio >= 0.999 {
                exact.append(group)
            } else if ratio >= 0.7 {
                high.append(group)
            } else {
                low.append(group)
            }
        }
        relevanceBuckets = [.exact: exact, .highSimilarity: high, .lowSimilarity: low, .all: groups]
    }

    private func startSearching() {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sources.isEmpty else { return }

        searchTask?.cancel()
        groups = []
        relevanceFilter = .all
        relevanceBuckets = [:]
        completedCount = 0
        failedCount = 0
        failedOutcomes = []
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
                if outcome.errorDescription != nil {
                    failedCount += 1
                    failedOutcomes.append(outcome)
                }
            }
            // Real bug found comparing against Legado: this tail used to run unconditionally even
            // when the `for await` loop above exited via the `Task.isCancelled` `break` (not natural
            // completion) -- `startSearching()` cancelling a still-running `searchTask` to start a
            // *new* search let the just-cancelled task's own tail fire moments later and stomp
            // `isSearching` back to `false` while the new search was still actively running,
            // prematurely ending the "searching…" UI state for a search that hadn't finished.
            guard !Task.isCancelled else { return }
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

/// Which title-similarity bucket a search result falls into, relative to the search keyword --
/// matches the reference reading app's own real 精确/≥70%/<70%/全部 tabs (see `TextSimilarity`).
/// `.exact` and `.highSimilarity`/`.lowSimilarity` are mutually exclusive partitions of `.all`, not
/// overlapping ranges -- a title counted in "精确" never also shows up in "≥70%".
enum SearchRelevanceFilter: String, CaseIterable, Identifiable {
    case exact, highSimilarity, lowSimilarity, all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .exact: return "精确"
        case .highSimilarity: return "≥70%"
        case .lowSimilarity: return "<70%"
        case .all: return "全部"
        }
    }
}

/// Wrapping row of tappable keyword chips (matches the reference reading app's own "最近搜索"
/// layout, confirmed via real screenshots: chips hug their own text width and wrap left-to-right,
/// top-to-bottom -- not a fixed-width grid). Real `Layout` conformance, not a `LazyVGrid`
/// approximation: an adaptive grid gives every chip the same cell width, which doesn't match how a
/// short 2-character term and a long 8-character one actually sit next to each other in the
/// reference.
private struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
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

/// Left-to-right, top-to-bottom wrapping container for variable-width chips -- SwiftUI has no
/// built-in flow/wrap layout, so this is the standard `Layout`-protocol implementation (each
/// subview keeps its own natural size; a subview that would overflow the available width starts a
/// new row instead).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        var isFirstInRow = true

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if !isFirstInRow, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
                isFirstInRow = true
            }
            rowWidth += (isFirstInRow ? 0 : spacing) + size.width
            rowHeight = max(rowHeight, size.height)
            isFirstInRow = false
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        var isFirstInRow = true

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if !isFirstInRow, x + size.width > bounds.minX + bounds.width {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
                isFirstInRow = true
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            isFirstInRow = false
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
    /// Non-zero when `CapabilityScanner` found this row's source using rule syntax this app can't
    /// run (most commonly JS) -- shown as the same orange "N 项不支持" badge `SourceLibraryView`
    /// already uses, so a source likely to fail is visible *before* tapping in, not just after.
    var compatibilityIssueCount: Int = 0
    /// The real, freshly-fetched chapter count -- only ever set by `ChangeSourceView`'s picker
    /// sheet (see its own doc comment for why: a real network fetch per candidate isn't something
    /// every card everywhere should pay for). `nil` elsewhere, matching this parameter's default.
    var chapterCount: Int? = nil

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
                    if compatibilityIssueCount > 0 {
                        Text("\(compatibilityIssueCount) 项不支持")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 6) {
                    if let author, !author.isEmpty {
                        Text(author)
                    }
                    if let wordCount, !wordCount.isEmpty {
                        Text(wordCount)
                    }
                    if let chapterCount {
                        Text("共 \(chapterCount) 章")
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
                // Real usage feedback: picking a source here only to hit a raw error after tapping
                // in (see `BookDetailView.load`'s `FriendlyError` fix) left no way to tell *before*
                // tapping which source was likely to fail. `CapabilityScanner.scan` is a pure,
                // network-free static parse of the source's own rule strings (already used the same
                // way for `SourceLibraryView`'s own badge) -- cheap enough to run inline per row here
                // rather than needing `SourceLibraryView`'s precomputed dictionary, since this list is
                // just "however many sources found this one book," never hundreds.
                BookResultCard(
                    name: entry.name, author: entry.author, coverUrl: entry.coverUrl, wordCount: entry.wordCount,
                    lastChapter: entry.lastChapter, intro: entry.intro, trailingLabel: entry.bookSourceName,
                    compatibilityIssueCount: CapabilityScanner.scan(resolveSource(entry)).issues.count
                )
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Which sources a search failed against, and why -- reachable by tapping "查看详情" on the results
/// screen's failure summary. `MultiSourceSearchService`'s `SourceOutcome.errorDescription` is
/// already run through `FriendlyError.message(for:)` at the point the failure is caught, so this
/// just displays it -- no error-formatting logic duplicated here.
private struct FailedSourcesListView: View {
    let outcomes: [MultiSourceSearchService.SourceOutcome]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(outcomes, id: \.source.bookSourceUrl) { outcome in
                VStack(alignment: .leading, spacing: 2) {
                    Text(outcome.source.bookSourceName).font(.headline)
                    Text(outcome.errorDescription ?? "未知错误")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .navigationTitle("搜索失败的书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
