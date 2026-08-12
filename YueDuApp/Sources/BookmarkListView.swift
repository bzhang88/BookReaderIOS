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
    // Editing a note used to be dead-end UI -- `Bookmark.note` was displayed if present, but nothing
    // anywhere ever set it (every bookmark-creation call site is a bare one-tap toggle with no note
    // prompt, matching how quickly you actually want to bookmark a spot while reading). This adds the
    // missing write path via a leading swipe action instead of turning bookmarking itself into a
    // two-step flow.
    @State private var editingNoteBookmark: Bookmark?
    @State private var noteDraft = ""
    @State private var exportURL: URL?
    @State private var isShowingExportSheet = false

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
                .swipeActions(edge: .leading) {
                    Button {
                        editingNoteBookmark = bookmark
                        noteDraft = bookmark.note ?? ""
                    } label: {
                        Label("备注", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("书签")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("导出为 Markdown") { exportMarkdown() }
                    Button("导出为 JSON") { exportJSON() }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(bookmarks.isEmpty)
            }
        }
        .navigationDestination(item: $target) { bookmark in
            BookmarkResumeView(bookmark: bookmark)
        }
        .alert("编辑备注", isPresented: Binding(
            get: { editingNoteBookmark != nil }, set: { if !$0 { editingNoteBookmark = nil } }
        )) {
            TextField("备注", text: $noteDraft)
            Button("保存") { Task { await saveNote() } }
            Button("取消", role: .cancel) { editingNoteBookmark = nil }
        }
        .sheet(isPresented: $isShowingExportSheet) {
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
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

    private func saveNote() async {
        guard var bookmark = editingNoteBookmark else { return }
        editingNoteBookmark = nil
        bookmark.note = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : noteDraft
        try? await env.bookmarkStore.update(bookmark)
        await reload()
    }

    private func exportMarkdown() {
        var lines = ["# 书签\n"]
        for (bookTitle, group) in Dictionary(grouping: bookmarks, by: \.bookTitle).sorted(by: { $0.key < $1.key }) {
            lines.append("## \(bookTitle)\n")
            for bookmark in group.sorted(by: { $0.chapterIndex < $1.chapterIndex }) {
                lines.append("- \(bookmark.chapterTitle)" + (bookmark.note.map { " —— \($0)" } ?? ""))
            }
            lines.append("")
        }
        writeAndShare(content: lines.joined(separator: "\n"), fileName: "书签.md")
    }

    private func exportJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(bookmarks), let json = String(data: data, encoding: .utf8) else { return }
        writeAndShare(content: json, fileName: "书签.json")
    }

    private func writeAndShare(content: String, fileName: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        guard (try? content.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        exportURL = url
        isShowingExportSheet = true
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
