import SwiftUI
import Persistence
import BookSourceModel
import WebBookOrchestrator

/// Left-sliding drawer for in-reader navigation -- matches the reference reading app's real 目录
/// entry point (confirmed via screenshot: tapping "目录" slides a panel in from the left edge over
/// a dimmed scrim, not a full bottom sheet), with 4 internal tabs bundling everything that's really
/// "find something in this book": chapter list, bookmarks, full-text search, and which purification
/// rules are currently active. Generic over the caller's chapter/bookmark/search plumbing so both
/// `ReaderView` (network books) and `LocalReaderView` (local .txt books) share one drawer instead of
/// each maintaining its own near-identical chapter-list-only sheet.
///
/// The search tab is a lightweight reimplementation of `ChapterContentSearchView`'s logic rather
/// than embedding that view directly -- that view wraps its content in its own `NavigationStack`
/// with a "关闭" button that calls `@Environment(\.dismiss)`. Nested here (inside an `.overlay`, not
/// a real modal presentation), that `dismiss()` would resolve to the *reader's own* dismiss action
/// (since the reader itself was pushed via `NavigationLink`), popping the whole reader off screen
/// instead of just closing the drawer -- a real correctness trap, not a hypothetical one.
struct ReaderTocDrawerView: View {
    struct ChapterItem: Identifiable {
        let id: Int  // chapter index
        let title: String
    }

    @Binding var isPresented: Bool
    let chapters: [ChapterItem]
    let currentIndex: Int
    let bookIdentifier: String
    let bookmarkStore: BookmarkStore
    let matchedReplaceRules: [ReplaceRule]
    /// Shown above the search tab's results -- for a network book this explains why only *cached*
    /// chapters are searchable; a local book (already fully in memory) passes nil.
    var searchScopeNotice: String? = nil
    let loadChaptersForSearch: () async -> [(index: Int, title: String, text: String)]
    let onSelectChapter: (Int) -> Void

    @State private var selectedTab: Tab = .toc
    @State private var bookmarks: [Bookmark] = []
    @State private var searchKeyword = ""
    @State private var searchableChapters: [(index: Int, title: String, text: String)] = []
    @State private var searchResults: [ChapterSearchMatch] = []
    @State private var isLoadingSearchChapters = true

    private enum Tab: String, CaseIterable, Identifiable {
        case toc, bookmark, search, purify

        var id: String { rawValue }

        var title: String {
            switch self {
            case .toc: return "目录"
            case .bookmark: return "书签"
            case .search: return "全文搜索"
            case .purify: return "净化规则"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if isPresented {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { isPresented = false }
                    .transition(.opacity)

                VStack(spacing: 0) {
                    tabBar
                    Divider()
                    content
                }
                .frame(width: min(320, UIScreen.main.bounds.width * 0.82))
                .frame(maxHeight: .infinity)
                .background(.regularMaterial)
                .ignoresSafeArea(edges: .vertical)
                .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
        .task(id: isPresented) {
            guard isPresented else { return }
            async let loadedBookmarks = bookmarkStore.bookmarks(bookIdentifier: bookIdentifier)
            async let loadedChapters = loadChaptersForSearch()
            bookmarks = (try? await loadedBookmarks) ?? []
            searchableChapters = await loadedChapters
            isLoadingSearchChapters = false
            searchResults = ChapterContentSearch.search(chapters: searchableChapters, keyword: searchKeyword)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .font(.caption)
                        .fontWeight(selectedTab == tab ? .semibold : .regular)
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 44)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .toc: tocList
        case .bookmark: bookmarkList
        case .search: searchTab
        case .purify: purifyTab
        }
    }

    private var tocList: some View {
        ScrollViewReader { proxy in
            List(chapters) { item in
                Button {
                    onSelectChapter(item.id)
                    isPresented = false
                } label: {
                    HStack {
                        Text(item.title).lineLimit(1)
                        Spacer()
                        if item.id == currentIndex {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
                .id(item.id)
            }
            .listStyle(.plain)
            .onAppear { proxy.scrollTo(currentIndex, anchor: .center) }
        }
    }

    private var bookmarkList: some View {
        Group {
            if bookmarks.isEmpty {
                ContentUnavailableView("还没有书签", systemImage: "bookmark")
            } else {
                List(bookmarks) { bookmark in
                    Button {
                        onSelectChapter(bookmark.chapterIndex)
                        isPresented = false
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bookmark.chapterTitle).lineLimit(1)
                            Text(bookmark.createdAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
    }

    private var searchTab: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索本书内容", text: $searchKeyword)
                    .textFieldStyle(.plain)
                    .onChange(of: searchKeyword) { _, newValue in
                        searchResults = ChapterContentSearch.search(chapters: searchableChapters, keyword: newValue)
                    }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .padding([.horizontal, .top], 8)

            if let searchScopeNotice {
                Text(searchScopeNotice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            List {
                if isLoadingSearchChapters {
                    ProgressView("正在准备搜索…")
                } else if searchResults.isEmpty && !searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("没有找到", systemImage: "magnifyingglass")
                }
                ForEach(searchResults) { match in
                    Button {
                        onSelectChapter(match.chapterIndex)
                        isPresented = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(match.chapterTitle).font(.subheadline)
                            Text(match.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
        }
    }

    private var purifyTab: some View {
        List {
            Section("本章命中的净化规则") {
                if matchedReplaceRules.isEmpty {
                    Text("本章没有命中任何净化规则").foregroundStyle(.secondary)
                } else {
                    ForEach(matchedReplaceRules) { rule in
                        Text(rule.name)
                    }
                }
            }
            Section {
                NavigationLink("管理全部净化规则") {
                    ReplaceRuleListView()
                }
            }
        }
        .listStyle(.plain)
    }
}
