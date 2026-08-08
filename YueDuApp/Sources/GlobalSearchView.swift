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
    @State private var results: [SearchResult] = []
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
            ForEach(results) { result in
                NavigationLink {
                    BookDetailView(source: resolveSource(for: result), searchResult: result)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.name).font(.headline)
                        HStack(spacing: 6) {
                            if let author = result.author, !author.isEmpty {
                                Text(author)
                            }
                            Text(result.bookSourceName).foregroundStyle(.blue)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if sources.isEmpty {
                ContentUnavailableView(
                    "没有已启用的书源", systemImage: "tray",
                    description: Text("去书源库导入并启用至少一个书源")
                )
            } else if hasSearchedOnce && !isSearching && results.isEmpty {
                ContentUnavailableView.search(text: keyword)
            }
        }
        .navigationTitle("搜索")
        .searchable(text: $keyword, prompt: "搜索所有已启用的书源")
        .onSubmit(of: .search) { startSearching() }
        .task { sources = (try? await env.bookSourceStore.enabled()) ?? [] }
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
            ? "共找到 \(results.count) 个结果（\(failedCount) 个书源搜索失败）"
            : "共找到 \(results.count) 个结果"
    }

    private func resolveSource(for result: SearchResult) -> BookSource {
        sources.first { $0.bookSourceUrl == result.bookSourceUrl }
            ?? BookSource(bookSourceUrl: result.bookSourceUrl, bookSourceName: result.bookSourceName)
    }

    private func startSearching() {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sources.isEmpty else { return }

        searchTask?.cancel()
        results = []
        completedCount = 0
        failedCount = 0
        isSearching = true
        hasSearchedOnce = true

        searchTask = Task {
            let stream = MultiSourceSearchService.search(sources: sources, keyword: trimmed, httpClient: env.httpClient)
            for await outcome in stream {
                if Task.isCancelled { break }
                results.append(contentsOf: outcome.results)
                completedCount += 1
                if outcome.errorDescription != nil { failedCount += 1 }
            }
            isSearching = false
        }
    }

    private func stopSearching() {
        searchTask?.cancel()
        isSearching = false
    }
}
