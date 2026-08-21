import SwiftUI
import WebBookOrchestrator

/// Full-book content search -- searches this book's chapter text for a keyword and jumps straight
/// to the first match. For a network book this only searches chapters already cached locally
/// (fetching every remaining chapter over the network just to search it isn't worth the cost);
/// for a local .txt book every chapter is already in memory, so `scopeNotice` is left nil there.
struct ChapterContentSearchView: View {
    let loadChapters: () async -> [(index: Int, title: String, text: String)]
    let onSelect: (Int) -> Void
    var scopeNotice: String?
    /// Pre-fills the search field -- used by the reader's long-press paragraph menu's 搜索本书 action
    /// (see `DictLookupView.initialWord`/`WebSearchPanelView.initialQuery` for the same pattern) so
    /// tapping it searches for the pressed paragraph's own text immediately instead of landing on an
    /// empty search field the user has to retype into.
    var initialKeyword: String = ""

    @State private var keyword: String
    @State private var allChapters: [(index: Int, title: String, text: String)] = []
    @State private var results: [ChapterSearchMatch] = []
    @State private var isLoadingChapters = true
    @Environment(\.dismiss) private var dismiss

    init(
        loadChapters: @escaping () async -> [(index: Int, title: String, text: String)],
        onSelect: @escaping (Int) -> Void, scopeNotice: String? = nil, initialKeyword: String = ""
    ) {
        self.loadChapters = loadChapters
        self.onSelect = onSelect
        self.scopeNotice = scopeNotice
        self.initialKeyword = initialKeyword
        _keyword = State(initialValue: initialKeyword)
    }

    var body: some View {
        NavigationStack {
            List {
                if let scopeNotice {
                    Text(scopeNotice).font(.caption).foregroundStyle(.secondary)
                }
                if isLoadingChapters {
                    ProgressView("正在准备搜索…")
                } else if results.isEmpty && !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("没有找到", systemImage: "magnifyingglass")
                }
                ForEach(results) { match in
                    Button {
                        onSelect(match.chapterIndex)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(match.chapterTitle).font(.headline)
                            Text(match.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $keyword, prompt: "搜索本书内容")
            .onChange(of: keyword) { _, newValue in
                results = ChapterContentSearch.search(chapters: allChapters, keyword: newValue)
            }
            .navigationTitle("书内搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                allChapters = await loadChapters()
                isLoadingChapters = false
                if !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    results = ChapterContentSearch.search(chapters: allChapters, keyword: keyword)
                }
            }
        }
    }
}
