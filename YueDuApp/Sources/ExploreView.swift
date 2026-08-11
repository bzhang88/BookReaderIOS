import SwiftUI
import BookSourceModel
import WebBookOrchestrator

/// "发现" tab -- browse book-source-provided category listings without typing a search keyword,
/// matching Legado's own Discover tab. Three-level navigation: pick a source, pick one of its
/// `exploreKinds` categories (parsed from `exploreUrl` via `ExploreKindParser`), then see that
/// category's results (reusing `BookResultCard`, the same row style `GlobalSearchView` uses).
struct ExploreView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var sources: [BookSource] = []

    var body: some View {
        NavigationStack {
            List {
                if sources.isEmpty {
                    ContentUnavailableView(
                        "没有支持发现的书源", systemImage: "safari",
                        description: Text("导入的书源里没有一个支持发现功能，或者都被停用了")
                    )
                }
                ForEach(sources) { source in
                    NavigationLink {
                        ExploreKindListView(source: source)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.bookSourceName).font(.headline)
                            if let group = source.bookSourceGroup, !group.isEmpty {
                                Text(group).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("发现")
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    private func reload() async {
        let all = (try? await env.bookSourceStore.enabled()) ?? []
        sources = all.filter {
            $0.enabledExplore && !($0.exploreUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }
}

private struct ExploreKindListView: View {
    let source: BookSource
    @State private var kinds: [ExploreKind] = []

    var body: some View {
        List {
            if kinds.isEmpty {
                ContentUnavailableView("没有分类", systemImage: "square.grid.2x2")
            }
            ForEach(kinds, id: \.url) { kind in
                NavigationLink(kind.name) {
                    ExploreResultsView(source: source, kind: kind)
                }
            }
        }
        .navigationTitle(source.bookSourceName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            kinds = ExploreKindParser.parse(source.exploreUrl ?? "")
        }
    }
}

private struct ExploreResultsView: View {
    let source: BookSource
    let kind: ExploreKind

    @EnvironmentObject private var env: AppEnvironment
    @State private var results: [SearchResult] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var currentPage = 1
    @State private var isLoadingMore = false

    var body: some View {
        List {
            ForEach(results) { result in
                NavigationLink {
                    BookDetailView(source: source, searchResult: result)
                } label: {
                    BookResultCard(
                        name: result.name, author: result.author, coverUrl: result.coverUrl,
                        wordCount: result.wordCount, lastChapter: result.lastChapter, intro: result.intro,
                        trailingLabel: result.kind ?? ""
                    )
                }
            }
            if !results.isEmpty {
                loadMoreRow
            }
        }
        .overlay { resultsOverlay }
        .navigationTitle(kind.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
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

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            results = try await ExploreService.fetchExploreList(
                source: source, exploreURL: kind.url, page: 1, httpClient: env.httpClient
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
        isLoadingMore = true
        let nextPage = currentPage + 1
        if let more = try? await ExploreService.fetchExploreList(
            source: source, exploreURL: kind.url, page: nextPage, httpClient: env.httpClient
        ) {
            results.append(contentsOf: more)
            currentPage = nextPage
        }
        isLoadingMore = false
    }
}
