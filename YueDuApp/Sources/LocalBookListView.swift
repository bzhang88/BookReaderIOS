import SwiftUI
import UniformTypeIdentifiers
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
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.plainText]) { result in
            Task { await handleImport(result) }
        }
        .alert("导入失败", isPresented: .constant(errorMessage != nil)) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await reload() }
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
            let split = TxtChapterSplitter.split(text, fallbackTitle: title)
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
