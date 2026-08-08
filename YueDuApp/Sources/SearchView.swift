import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import NetworkClient

struct SearchView: View {
    let source: BookSource

    @EnvironmentObject private var env: AppEnvironment
    @State private var keyword: String = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var hasSearchedOnce = false

    var body: some View {
        List {
            ForEach(results) { result in
                NavigationLink {
                    BookDetailView(source: source, searchResult: result)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.name).font(.headline)
                        if let author = result.author, !author.isEmpty {
                            Text(author).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let lastChapter = result.lastChapter, !lastChapter.isEmpty {
                            Text(lastChapter).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .overlay {
            if isSearching {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView("搜索失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if hasSearchedOnce && results.isEmpty {
                ContentUnavailableView.search(text: keyword)
            }
        }
        .navigationTitle(source.bookSourceName)
        .searchable(text: $keyword, prompt: "搜索书名/作者")
        .onSubmit(of: .search) { performSearch() }
    }

    private func performSearch() {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        Task {
            defer { isSearching = false; hasSearchedOnce = true }
            do {
                results = try await SearchService.search(source: source, keyword: trimmed, httpClient: env.httpClient)
            } catch {
                results = []
                errorMessage = "\(error)"
            }
        }
    }
}
