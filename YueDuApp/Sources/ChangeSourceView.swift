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
                List(group.entries) { entry in
                    Button {
                        pickerGroup = nil
                        switchTo(entry)
                    } label: {
                        BookResultCard(
                            name: entry.name, author: entry.author, coverUrl: entry.coverUrl,
                            wordCount: entry.wordCount, lastChapter: entry.lastChapter, intro: entry.intro,
                            trailingLabel: entry.bookSourceName
                        )
                    }
                    .disabled(isSwitching)
                }
                .navigationTitle(group.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { pickerGroup = nil }
                    }
                }
            }
        }
        .task { await search() }
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
        let candidates = all.filter { $0.bookSourceUrl != currentBookSourceUrl }
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

    private func isExactMatch(_ group: GroupedSearchResult) -> Bool {
        let nameMatches = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            == bookName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bookAuthor, !bookAuthor.isEmpty else { return nameMatches }
        return nameMatches && group.author?.trimmingCharacters(in: .whitespacesAndNewlines) == bookAuthor
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
