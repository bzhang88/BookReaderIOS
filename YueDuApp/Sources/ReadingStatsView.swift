import SwiftUI
import Persistence

/// Reading stats dashboard (Phase 24 polish) -- purely a read-only aggregation over data the app
/// already persists (ShelfStore/LocalBookStore), no new storage of its own.
struct ReadingStatsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var shelfBooks: [ShelfBook] = []
    @State private var localBooks: [LocalBook] = []
    @State private var isLoading = true

    private var totalBooks: Int { shelfBooks.count + localBooks.count }

    private var startedBooks: Int {
        shelfBooks.filter { $0.lastReadAt != nil }.count + localBooks.filter { $0.lastReadAt != nil }.count
    }

    /// Rough "how long have you been using this" number -- days since the earliest `addedAt`
    /// across every book, shelf or local.
    private var daysSinceFirstBook: Int? {
        let dates = shelfBooks.map(\.addedAt) + localBooks.map(\.addedAt)
        guard let earliest = dates.min() else { return nil }
        let days = Calendar.current.dateComponents([.day], from: earliest, to: Date()).day ?? 0
        return max(0, days)
    }

    private var recentlyRead: [RecentEntry] {
        let shelfEntries = shelfBooks.compactMap { book -> RecentEntry? in
            guard let lastReadAt = book.lastReadAt else { return nil }
            return RecentEntry(id: "shelf-\(book.bookUrl)", name: book.name, chapterTitle: book.lastReadChapterTitle, lastReadAt: lastReadAt)
        }
        let localEntries = localBooks.compactMap { book -> RecentEntry? in
            guard let lastReadAt = book.lastReadAt else { return nil }
            let chapterTitle = book.lastReadChapterIndex.flatMap { book.chapters.indices.contains($0) ? book.chapters[$0].title : nil }
            return RecentEntry(id: "local-\(book.id)", name: book.title, chapterTitle: chapterTitle, lastReadAt: lastReadAt)
        }
        return Array((shelfEntries + localEntries).sorted { $0.lastReadAt > $1.lastReadAt }.prefix(5))
    }

    var body: some View {
        List {
            Section {
                HStack {
                    statTile(value: "\(totalBooks)", label: "书籍总数")
                    statTile(value: "\(startedBooks)", label: "已开始阅读")
                    if let days = daysSinceFirstBook {
                        statTile(value: "\(days)", label: "使用天数")
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            if !recentlyRead.isEmpty {
                Section("最近阅读") {
                    ForEach(recentlyRead) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).font(.subheadline)
                            if let chapterTitle = entry.chapterTitle, !chapterTitle.isEmpty {
                                Text(chapterTitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if totalBooks == 0 {
                ContentUnavailableView(
                    "还没有数据", systemImage: "chart.bar",
                    description: Text("加几本书开始阅读后，这里会显示统计信息")
                )
            }
        }
        .navigationTitle("阅读统计")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        shelfBooks = (try? await env.shelfStore.all()) ?? []
        localBooks = (try? await env.localBookStore.all()) ?? []
        isLoading = false
    }
}

private struct RecentEntry: Identifiable {
    let id: String
    let name: String
    let chapterTitle: String?
    let lastReadAt: Date
}
