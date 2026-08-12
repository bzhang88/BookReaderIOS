import SwiftUI
import UniformTypeIdentifiers
import BookSourceModel
import NetworkClient
import WebBookOrchestrator
import Persistence

/// Local .txt import (Phase 16) -- kept as its own screen reachable from the shelf's toolbar
/// rather than merged into `ShelfView`'s list, since `ShelfBook` assumes a network book source
/// (non-optional bookSourceUrl/bookUrl/tocUrl) that a local file simply doesn't have.
struct LocalBookListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var books: [LocalBook] = []
    @State private var isImporterPresented = false
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var exportURL: URL?
    @State private var isShowingExportSheet = false
    @State private var exportTarget: LocalBook?

    var body: some View {
        List {
            if books.isEmpty {
                ContentUnavailableView(
                    "还没有本地书籍", systemImage: "doc.text", description: Text("点右上角 + 导入一个 .txt 文件")
                )
            }
            ForEach(books) { book in
                NavigationLink {
                    LocalReaderView(book: book)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title).font(.headline)
                        Text("共 \(book.chapters.count) 章")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let index = book.lastReadChapterIndex, book.chapters.indices.contains(index) {
                            Text("上次读到: \(book.chapters[index].title)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        exportTarget = book
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                    .tint(.blue)
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("本地书籍")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isImporterPresented = true
                } label: {
                    if isImporting {
                        ProgressView()
                    } else {
                        Label("导入", systemImage: "plus")
                    }
                }
                .disabled(isImporting)
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    WebDAVBookImportView()
                } label: {
                    Label("WebDAV 导入", systemImage: "externaldrive")
                }
            }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.plainText]) { result in
            Task { await handleImport(result) }
        }
        .alert("导入失败", isPresented: .constant(errorMessage != nil)) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $isShowingExportSheet) {
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
        }
        .confirmationDialog(
            "导出格式", isPresented: Binding(get: { exportTarget != nil }, set: { if !$0 { exportTarget = nil } }),
            presenting: exportTarget
        ) { book in
            Button("导出为 TXT") { exportTxt(book) }
            Button("导出为 EPUB") { exportEpub(book) }
            Button("取消", role: .cancel) {}
        }
        .task { await reload() }
    }

    /// All of a local book's chapters are already in memory (no network/cache round-trip needed,
    /// unlike a network book's export), so this can write the temp file synchronously right away.
    private func exportTxt(_ book: LocalBook) {
        let combined = TxtExporter.combine(
            bookTitle: book.title, chapters: book.chapters.map { (title: $0.title, text: $0.text) }
        )
        let fileName = TxtExporter.sanitizedFileName(book.title)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).txt")
        guard (try? combined.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        exportURL = url
        isShowingExportSheet = true
    }

    /// A local book has no author metadata (`LocalBook` doesn't track one -- plain .txt imports never
    /// had a reliable way to extract it), so the EPUB's `dc:creator` falls back to "佚名" (see
    /// `EpubExporter`'s own default for a nil author).
    private func exportEpub(_ book: LocalBook) {
        let data = EpubExporter.build(
            bookTitle: book.title, author: nil, chapters: book.chapters.map { (title: $0.title, text: $0.text) }
        )
        let fileName = TxtExporter.sanitizedFileName(book.title)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).epub")
        guard (try? data.write(to: url)) != nil else { return }
        exportURL = url
        isShowingExportSheet = true
    }

    private func reload() async {
        let all = (try? await env.localBookStore.all()) ?? []
        books = all.sorted { ($0.lastReadAt ?? $0.addedAt) > ($1.lastReadAt ?? $1.addedAt) }
    }

    private func handleImport(_ result: Result<URL, Error>) async {
        isImporting = true
        defer { isImporting = false }
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let text = CharsetDetector.decodeAutodetectingBytes(data)
            let title = url.deletingPathExtension().lastPathComponent
            let patterns = ((try? await env.txtSplitRuleStore.enabled()) ?? []).map(\.pattern)
            let split = TxtChapterSplitter.splitTryingRules(text, rules: patterns, fallbackTitle: title)
            guard !split.isEmpty else {
                errorMessage = "这个文件看起来是空的"
                return
            }
            let chapters = split.map { LocalChapter(title: $0.title, text: $0.text) }
            try await env.localBookStore.add(LocalBook(title: title, chapters: chapters))
            await reload()
        } catch {
            errorMessage = "\(error)"
        }
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { books[$0] }
        Task {
            for book in toDelete {
                try? await env.localBookStore.remove(id: book.id)
            }
            await reload()
        }
    }
}
