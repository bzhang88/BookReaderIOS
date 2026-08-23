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
        /// Defaults to `false` -- a local `.txt` book's chapters never carry this (`TxtChapterSplitter`
        /// treats every heading as a flat, equal-weight chapter with no volume concept), so
        /// `LocalReaderView` never needs to pass it explicitly.
        var isVolume: Bool = false
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
    /// Which chapter indices already have their content saved to disk (so opening them needs no
    /// network) -- real usage feedback, with a reference screenshot, wanted the chapter list to show
    /// this directly (a small cloud glyph on chapters that would need a network fetch) rather than
    /// making you tap in and find out. `nil` (the default) means "not applicable" -- a local `.txt`
    /// book is already entirely on disk, so `LocalReaderView` doesn't pass this at all and no chapter
    /// ever shows the glyph. `ReaderView` passes `env.chapterCacheStore.downloadedIndices(bookUrl:)`.
    var loadDownloadedIndices: (() async -> Set<Int>)? = nil
    /// `(chapterIndex, characterOffset)` -- the offset is `nil` for a plain 目录/全文搜索 jump (go to
    /// the chapter's own start), but carries `bookmark.characterOffset` through for a 书签 tap, so
    /// jumping to a bookmark saved mid-chapter (see `Bookmark.characterOffset`'s doc comment) lands
    /// on the actual spot instead of the chapter's first page.
    let onSelectChapter: (Int, Int?) -> Void

    @State private var selectedTab: Tab = .toc
    @State private var bookmarks: [Bookmark] = []
    @State private var searchKeyword = ""
    @State private var searchableChapters: [(index: Int, title: String, text: String)] = []
    @State private var searchResults: [ChapterSearchMatch] = []
    @State private var isLoadingSearchChapters = true
    @State private var downloadedIndices: Set<Int>?

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
                // Real usage feedback: the scrim behind the drawer wasn't noticeable enough to tell
                // the drawer is actually "on top" (reference screenshot shows a clearly darkened
                // reading area behind it). 0.35 read as too subtle on a light-themed background;
                // bumped to 0.55 to match.
                Color.black.opacity(0.55)
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
            if let loadDownloadedIndices {
                downloadedIndices = await loadDownloadedIndices()
            }
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
                // Real bug found comparing against Legado: a volume/section header row used to be a
                // plain `Button` identical to a real chapter -- tapping it navigated into the reader
                // on a synthetic "chapter" whose body is just the volume's own title. Legado never
                // lets a volume be "opened" this way; rendering it as plain non-navigable text is the
                // minimal fix -- full collapse/expand grouping is a separate, larger feature.
                if item.isVolume {
                    Text(item.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                        .id(item.id)
                } else {
                    Button {
                        onSelectChapter(item.id, nil)
                        isPresented = false
                    } label: {
                        // No `.lineLimit` -- real usage feedback, with a reference screenshot, pointed
                        // out a long chapter title just vanished (clipped to one line with no ellipsis
                        // given the plain `HStack` layout) instead of wrapping to a second line the
                        // way the reference app shows it.
                        HStack(alignment: .top) {
                            Text(item.title)
                                .foregroundStyle(chapterTextColor(for: item.id))
                                .fontWeight(item.id == currentIndex ? .semibold : .regular)
                            Spacer(minLength: 8)
                            // Real usage feedback, same screenshot: chapters already saved to disk
                            // (read, or simply prefetched ahead of where you are) show nothing extra;
                            // chapters that would still need a network fetch get a small cloud glyph,
                            // so you can tell at a glance how far ahead you can keep reading offline.
                            if let downloadedIndices, !downloadedIndices.contains(item.id) {
                                Image(systemName: "icloud")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .id(item.id)
                }
            }
            .listStyle(.plain)
            .onAppear { proxy.scrollTo(currentIndex, anchor: .center) }
        }
    }

    /// Matches the reference screenshot's three-way distinction: chapters before wherever you
    /// currently are read as already-read (dimmed), the current chapter itself stands out (accent
    /// color, bold), and everything after it reads as plain not-yet-read text. Purely index-relative
    /// to `currentIndex` -- no separate "read" bit is persisted anywhere, matching how a linear novel
    /// reader is actually used (you don't jump around and mark chapters read out of order).
    private func chapterTextColor(for index: Int) -> Color {
        if index == currentIndex { return .accentColor }
        if index < currentIndex { return .secondary }
        return .primary
    }

    private var bookmarkList: some View {
        Group {
            if bookmarks.isEmpty {
                ContentUnavailableView("还没有书签", systemImage: "bookmark")
            } else {
                List(bookmarks) { bookmark in
                    Button {
                        onSelectChapter(bookmark.chapterIndex, bookmark.characterOffset)
                        isPresented = false
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bookmark.chapterTitle).lineLimit(1)
                            if let excerpt = bookmark.excerpt, !excerpt.isEmpty {
                                Text(excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
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
                        onSelectChapter(match.chapterIndex, nil)
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
