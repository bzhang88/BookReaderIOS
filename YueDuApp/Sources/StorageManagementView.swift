import SwiftUI
import Persistence

/// Shows how much disk space the offline chapter-download cache (`ChapterCacheStore`) is using,
/// broken down per shelf book, with a way to reclaim it -- either one book at a time or all at
/// once. Deliberately scoped to just this cache: the other on-disk JSON files (shelf, book
/// sources, imported local .txt books, etc.) are the user's actual data, not a regenerable cache,
/// so they don't belong on a "clear space" screen.
struct StorageManagementView: View {
    private struct BookCacheUsage: Identifiable {
        let book: ShelfBook
        let sizeBytes: Int64
        let chapterCount: Int
        var id: String { book.bookUrl }
    }

    @EnvironmentObject private var env: AppEnvironment
    @State private var totalSizeBytes: Int64 = 0
    @State private var perBookUsage: [BookCacheUsage] = []
    @State private var isLoading = true
    @State private var isClearingAll = false

    var body: some View {
        List {
            Section {
                HStack {
                    Text("已下载章节缓存总占用")
                    Spacer()
                    Text(Self.formattedSize(totalSizeBytes)).foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    Task { await clearAll() }
                } label: {
                    if isClearingAll {
                        ProgressView()
                    } else {
                        Text("清空全部下载缓存")
                    }
                }
                .disabled(isClearingAll || totalSizeBytes == 0)
            }

            if !perBookUsage.isEmpty {
                Section("按书籍") {
                    ForEach(perBookUsage) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.book.name).font(.headline)
                            Text("\(entry.chapterCount) 章 · \(Self.formattedSize(entry.sizeBytes))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await clearBook(entry.book) }
                            } label: {
                                Label("删除缓存", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if totalSizeBytes == 0 {
                ContentUnavailableView(
                    "还没有下载缓存", systemImage: "externaldrive",
                    description: Text("在书籍详情页点\u{201C}缓存全本\u{201D}即可离线阅读")
                )
            }
        }
        .navigationTitle("存储管理")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        totalSizeBytes = await env.chapterCacheStore.totalSizeBytes()

        let shelfBooks = (try? await env.shelfStore.all()) ?? []
        var usage: [BookCacheUsage] = []
        for book in shelfBooks {
            let indices = (try? await env.chapterCacheStore.downloadedIndices(bookUrl: book.bookUrl)) ?? []
            guard !indices.isEmpty else { continue }
            let size = await env.chapterCacheStore.sizeBytes(bookUrl: book.bookUrl)
            usage.append(BookCacheUsage(book: book, sizeBytes: size, chapterCount: indices.count))
        }
        perBookUsage = usage.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private func clearAll() async {
        isClearingAll = true
        defer { isClearingAll = false }
        try? await env.chapterCacheStore.removeAll()
        await reload()
    }

    private func clearBook(_ book: ShelfBook) async {
        try? await env.chapterCacheStore.removeBook(bookUrl: book.bookUrl)
        await reload()
    }

    private static func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
