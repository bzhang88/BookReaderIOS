import SwiftUI
import BookSourceModel
import WebBookOrchestrator

/// "发现" tab -- browse book-source-provided category listings without typing a search keyword.
/// Confirmed via the user's own real reference screenshots: this is a single flat screen (a source
/// picker in the nav bar + a horizontally scrollable category-chip row + a results list with a
/// quick "+" add-to-shelf button per row), not the 3-level push (source list -> category list ->
/// results list) this view used before -- switching source or category updates this same screen in
/// place instead of navigating away from it.
struct ExploreView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var sources: [BookSource] = []
    @State private var selectedSource: BookSource?
    @State private var kinds: [ExploreKind] = []
    @State private var selectedKind: ExploreKind?
    @State private var results: [SearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var currentPage = 1
    @State private var isLoadingMore = false
    @State private var shelfKeys: Set<String> = []
    /// `SearchResult.id` (bookSourceUrl+bookUrl) of whichever row's quick-add fetch is in flight --
    /// a `Set` rather than a single value since nothing stops the user tapping "+" on more than one
    /// row before the first fetch finishes.
    @State private var addingResultIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if sources.isEmpty {
                    ContentUnavailableView(
                        "没有支持发现的书源", systemImage: "safari",
                        description: Text("导入的书源里没有一个支持发现功能，或者都被停用了")
                    )
                } else {
                    VStack(spacing: 0) {
                        categoryChipsRow
                        resultsList
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        GlobalSearchView()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
                ToolbarItem(placement: .principal) {
                    sourcePickerMenu
                }
            }
            .task { await reloadSources() }
            .refreshable { await reloadSources() }
        }
    }

    private var sourcePickerMenu: some View {
        Menu {
            ForEach(sources) { source in
                Button {
                    Task { await selectSource(source) }
                } label: {
                    if source.bookSourceUrl == selectedSource?.bookSourceUrl {
                        Label(source.bookSourceName, systemImage: "checkmark")
                    } else {
                        Text(source.bookSourceName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedSource?.bookSourceName ?? "发现").font(.headline)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var categoryChipsRow: some View {
        if !kinds.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(kinds, id: \.url) { kind in
                        Button {
                            Task { await selectKind(kind) }
                        } label: {
                            Text(kind.name)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    kind.url == selectedKind?.url
                                        ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1),
                                    in: Capsule()
                                )
                                .foregroundStyle(kind.url == selectedKind?.url ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            Divider()
        }
    }

    private var resultsList: some View {
        List {
            ForEach(results) { result in
                resultRow(result)
            }
            if !results.isEmpty {
                loadMoreRow
            }
        }
        .listStyle(.plain)
        .overlay { resultsOverlay }
    }

    /// NavigationLink + a sibling quick-add Button, not a Button nested *inside* the NavigationLink's
    /// own label -- a nested button's taps get swallowed by the row's own NavigationLink without
    /// `.buttonStyle(.plain)` and being a sibling rather than nested (the exact same gotcha
    /// `ShelfView`'s row already had to work around for its own trailing "..." button).
    private func resultRow(_ result: SearchResult) -> some View {
        HStack(alignment: .top, spacing: 8) {
            NavigationLink {
                BookDetailView(
                    source: selectedSource ?? BookSource(bookSourceUrl: result.bookSourceUrl, bookSourceName: result.bookSourceName),
                    searchResult: result
                )
            } label: {
                BookResultCard(
                    name: result.name, author: result.author, coverUrl: result.coverUrl,
                    wordCount: result.wordCount, lastChapter: result.lastChapter, intro: result.intro,
                    trailingLabel: result.kind ?? "",
                    isInShelf: shelfKeys.contains(GroupedSearchResult.groupKey(name: result.name, author: result.author))
                )
            }
            quickAddButton(for: result)
        }
    }

    @ViewBuilder
    private func quickAddButton(for result: SearchResult) -> some View {
        let key = GroupedSearchResult.groupKey(name: result.name, author: result.author)
        if shelfKeys.contains(key) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 32, height: 44)
        } else if addingResultIDs.contains(result.id) {
            ProgressView()
                .frame(width: 32, height: 44)
        } else {
            Button {
                Task { await quickAdd(result) }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var loadMoreRow: some View {
        Button {
            Task { await loadMore() }
        } label: {
            if isLoadingMore {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text("加载更多").frame(maxWidth: .infinity)
            }
        }
        .disabled(isLoadingMore)
    }

    @ViewBuilder
    private var resultsOverlay: some View {
        if isLoading {
            ProgressView()
        } else if let errorMessage {
            ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
        } else if results.isEmpty {
            ContentUnavailableView("没有结果", systemImage: "tray")
        }
    }

    private func reloadSources() async {
        let all = (try? await env.bookSourceStore.enabled()) ?? []
        sources = all.filter {
            $0.enabledExplore && !($0.exploreUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        await reloadShelfKeys()
        if let selectedSource, sources.contains(where: { $0.bookSourceUrl == selectedSource.bookSourceUrl }) {
            return
        }
        if let first = sources.first {
            await selectSource(first)
        } else {
            selectedSource = nil
            kinds = []
            selectedKind = nil
            results = []
        }
    }

    private func reloadShelfKeys() async {
        let shelfBooks = (try? await env.shelfStore.all()) ?? []
        shelfKeys = Set(shelfBooks.map { GroupedSearchResult.groupKey(name: $0.name, author: $0.author) })
    }

    private func selectSource(_ source: BookSource) async {
        selectedSource = source
        kinds = ExploreKindParser.parse(source.exploreUrl ?? "")
        results = []
        selectedKind = nil
        if let first = kinds.first {
            await selectKind(first)
        }
    }

    private func selectKind(_ kind: ExploreKind) async {
        selectedKind = kind
        await load()
    }

    private func load() async {
        guard let selectedSource, let selectedKind else { return }
        isLoading = true
        errorMessage = nil
        do {
            results = try await ExploreService.fetchExploreList(
                source: selectedSource, exploreURL: selectedKind.url, page: 1, httpClient: env.httpClient
            )
            currentPage = 1
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
    }

    /// Failures here are silent (no error alert) -- "加载更多" is a secondary action on an already
    /// non-empty, already-useful list, so surfacing a hard error for a failed next-page fetch would
    /// be disruptive relative to just leaving the button tappable to retry.
    private func loadMore() async {
        guard let selectedSource, let selectedKind else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1
        if let more = try? await ExploreService.fetchExploreList(
            source: selectedSource, exploreURL: selectedKind.url, page: nextPage, httpClient: env.httpClient
        ) {
            results.append(contentsOf: more)
            currentPage = nextPage
        }
        isLoadingMore = false
    }

    /// Fetches full book info (needed for `tocUrl`, which a bare search/explore result never has)
    /// before adding to the shelf, mirroring `BookDetailView`'s own 加入书架 logic -- this is what
    /// lets the "+" button add a book without navigating into the detail page first. Fails silently
    /// (button just stays as "+" so the user can retry) rather than surfacing an alert, matching
    /// `loadMore`'s same reasoning.
    private func quickAdd(_ result: SearchResult) async {
        guard let selectedSource else { return }
        addingResultIDs.insert(result.id)
        defer { addingResultIDs.remove(result.id) }
        guard let info = try? await BookInfoService.fetchBookInfo(
            source: selectedSource, bookURL: result.bookUrl, httpClient: env.httpClient
        ) else { return }
        let book = ShelfBook(
            bookSourceUrl: selectedSource.bookSourceUrl, bookUrl: result.bookUrl,
            name: info.name ?? result.name, author: info.author ?? result.author,
            coverUrl: info.coverUrl ?? result.coverUrl, intro: info.intro ?? result.intro,
            tocUrl: info.tocUrl, lastChapterTitle: info.lastChapter ?? result.lastChapter
        )
        try? await env.shelfStore.addOrUpdate(book)
        shelfKeys.insert(GroupedSearchResult.groupKey(name: book.name, author: book.author))
    }
}
