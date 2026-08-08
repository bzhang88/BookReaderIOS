import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import Persistence

/// Finds the same book (exact name + author match, same convention as `SearchResultGrouper`) on
/// other enabled sources -- lets the user switch a shelf book to a different source when its
/// current one has stopped working, which real-world testing this session showed is a common,
/// expected situation (public book-source collections decay; sites add anti-bot protection).
struct ChangeSourceView: View {
    let currentBookSourceUrl: String
    let bookName: String
    let bookAuthor: String?
    let onSourceSelected: (BookSource, SearchResult) async -> Void

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var sources: [BookSource] = []
    @State private var matches: [SearchResult] = []
    @State private var isSearching = false
    @State private var hasSearchedOnce = false
    @State private var isSwitching = false

    var body: some View {
        List {
            ForEach(matches) { match in
                Button {
                    switchTo(match)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(match.bookSourceName).font(.headline)
                        if let lastChapter = match.lastChapter, !lastChapter.isEmpty {
                            Text(lastChapter).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(isSwitching)
            }
        }
        .overlay {
            if isSearching {
                ProgressView("正在其他书源里查找…")
            } else if isSwitching {
                ProgressView("正在切换…")
            } else if hasSearchedOnce && matches.isEmpty {
                ContentUnavailableView(
                    "没有找到其他源", systemImage: "arrow.triangle.2.circlepath",
                    description: Text("已启用的其他书源里没搜到同名同作者的书")
                )
            }
        }
        .navigationTitle("换源")
        .navigationBarTitleDisplayMode(.inline)
        .task { await search() }
    }

    private func search() async {
        let all = (try? await env.bookSourceStore.enabled()) ?? []
        sources = all
        let candidates = all.filter { $0.bookSourceUrl != currentBookSourceUrl }
        guard !candidates.isEmpty else {
            hasSearchedOnce = true
            return
        }

        isSearching = true
        let stream = MultiSourceSearchService.search(sources: candidates, keyword: bookName, httpClient: env.httpClient)
        for await outcome in stream {
            let sameBook = outcome.results.filter(matchesTargetBook)
            matches.append(contentsOf: sameBook)
        }
        isSearching = false
        hasSearchedOnce = true
    }

    private func matchesTargetBook(_ result: SearchResult) -> Bool {
        let nameMatches = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
            == bookName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bookAuthor, !bookAuthor.isEmpty else { return nameMatches }
        return nameMatches && result.author?.trimmingCharacters(in: .whitespacesAndNewlines) == bookAuthor
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
