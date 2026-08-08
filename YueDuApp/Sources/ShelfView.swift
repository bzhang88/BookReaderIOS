import SwiftUI
import BookSourceModel
import Persistence

struct ShelfView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var books: [ShelfBook] = []

    var body: some View {
        NavigationStack {
            List {
                if books.isEmpty {
                    ContentUnavailableView(
                        "书架是空的", systemImage: "books.vertical",
                        description: Text("去书源库搜索一本书，加入书架")
                    )
                }
                ForEach(books) { book in
                    NavigationLink {
                        ShelfBookResumeView(book: book)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.name).font(.headline)
                            if let author = book.author, !author.isEmpty {
                                Text(author).font(.subheadline).foregroundStyle(.secondary)
                            }
                            if let title = book.lastReadChapterTitle {
                                Text("上次读到: \(title)").font(.caption).foregroundStyle(.secondary)
                            } else if let last = book.lastChapterTitle, !last.isEmpty {
                                Text("最新: \(last)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("书架")
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    private func reload() async {
        let all = (try? await env.shelfStore.all()) ?? []
        books = all.sorted { ($0.lastReadAt ?? $0.addedAt) > ($1.lastReadAt ?? $1.addedAt) }
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { books[$0] }
        Task {
            for book in toDelete {
                try? await env.shelfStore.remove(bookUrl: book.bookUrl)
            }
            await reload()
        }
    }
}

/// Resolves a shelf entry's originating book source, then hands off to `TocView` with a resume
/// index so tapping a shelf book jumps straight back into reading rather than re-browsing the TOC.
struct ShelfBookResumeView: View {
    let book: ShelfBook

    @EnvironmentObject private var env: AppEnvironment
    @State private var source: BookSource?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let source {
                TocView(
                    source: source, tocURL: book.tocUrl, bookUrl: book.bookUrl, bookTitle: book.name,
                    resumeChapterIndex: book.lastReadChapterIndex
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
        let sources = (try? await env.bookSourceStore.all()) ?? []
        if let match = sources.first(where: { $0.bookSourceUrl == book.bookSourceUrl }) {
            source = match
        } else {
            errorMessage = "找不到这本书对应的书源，可能已被删除"
        }
    }
}
