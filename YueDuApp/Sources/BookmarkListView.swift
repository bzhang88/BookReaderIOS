import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import Persistence

/// Cross-book bookmark list -- reachable from Settings, since a bookmark isn't tied to being on
/// the shelf (the book it points at might not be shelved, e.g. reached via a search result's
/// "立即阅读" without ever tapping "加入书架").
struct BookmarkListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var bookmarks: [Bookmark] = []
    @State private var target: Bookmark?

    var body: some View {
        List {
            if bookmarks.isEmpty {
                ContentUnavailableView(
                    "还没有书签", systemImage: "bookmark",
                    description: Text("在阅读器里点书签图标，把当前章节存下来")
                )
            }
            ForEach(bookmarks) { bookmark in
                Button {
                    target = bookmark
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bookmark.bookTitle).font(.headline)
                        Text(bookmark.chapterTitle).font(.subheadline).foregroundStyle(.secondary)
                        if let note = bookmark.note, !note.isEmpty {
                            Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("书签")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $target) { bookmark in
            BookmarkResumeView(bookmark: bookmark)
        }
        .task { await reload() }
    }

    private func reload() async {
        let all = (try? await env.bookmarkStore.all()) ?? []
        bookmarks = all.sorted { $0.createdAt > $1.createdAt }
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { bookmarks[$0] }
        Task {
            for bookmark in toDelete {
                try? await env.bookmarkStore.remove(id: bookmark.id)
            }
            await reload()
        }
    }
}

/// Resolves a bookmark back into a live reading session -- for a network book, re-resolves the
/// `BookSource` and re-fetches its TOC (the bookmark only stored the URLs, not the whole chapter
/// list, to keep bookmarks.json small); for a local book, just looks it up by id.
private struct BookmarkResumeView: View {
    let bookmark: Bookmark

    @EnvironmentObject private var env: AppEnvironment
    @State private var source: BookSource?
    @State private var chapters: [BookChapter] = []
    @State private var localBook: LocalBook?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if bookmark.isLocal {
                if let localBook {
                    LocalReaderView(book: localBook, startChapterIndex: bookmark.chapterIndex)
                } else if let errorMessage {
                    ContentUnavailableView("无法打开", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else {
                    ProgressView()
                }
            } else if let source, !chapters.isEmpty {
                BookOpenerView(
                    source: source, bookUrl: bookmark.bookIdentifier, tocUrl: bookmark.tocUrl ?? "",
                    chapters: chapters, currentIndex: min(bookmark.chapterIndex, chapters.count - 1),
                    bookTitle: bookmark.bookTitle
                )
            } else if let errorMessage {
                ContentUnavailableView("无法打开", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ProgressView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        if bookmark.isLocal {
            let all = (try? await env.localBookStore.all()) ?? []
            if let match = all.first(where: { $0.id == bookmark.bookIdentifier }) {
                localBook = match
            } else {
                errorMessage = "这本本地书籍已经被删除了"
            }
            return
        }

        guard let bookSourceUrl = bookmark.bookSourceUrl, let tocUrl = bookmark.tocUrl else {
            errorMessage = "书签信息不完整"
            return
        }
        let sources = (try? await env.bookSourceStore.all()) ?? []
        guard let match = sources.first(where: { $0.bookSourceUrl == bookSourceUrl }) else {
            errorMessage = "找不到这本书对应的书源，可能已被删除"
            return
        }
        source = match
        do {
            let fetched = try await TocService.fetchChapterList(source: match, tocURL: tocUrl, httpClient: env.httpClient)
            if fetched.isEmpty {
                errorMessage = "没有找到章节"
            } else {
                chapters = fetched
            }
        } catch {
            errorMessage = "\(error)"
        }
    }
}
