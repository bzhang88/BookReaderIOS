import SwiftUI
import BookSourceModel
import Persistence

/// Sources removed from the library land here instead of being gone for good -- swiping to delete
/// a row in a long list of similar-looking book sources is easy to fat-finger, so an unrecoverable
/// delete would be a real annoyance. Restoring re-imports through the same upsert-by-url path a
/// normal import uses, so a restored source behaves exactly like a freshly-imported one.
struct SourceTrashView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var sources: [BookSource] = []

    var body: some View {
        List {
            if sources.isEmpty {
                ContentUnavailableView(
                    "回收站是空的", systemImage: "trash",
                    description: Text("删除的书源会先进这里，不会直接消失")
                )
            }
            ForEach(sources) { source in
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.bookSourceName).font(.headline)
                    Text(source.bookSourceUrl).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .swipeActions(edge: .leading) {
                    Button {
                        Task { await restore(source) }
                    } label: {
                        Label("恢复", systemImage: "arrow.uturn.backward")
                    }
                    .tint(.green)
                }
            }
            .onDelete(perform: permanentlyDelete)
        }
        .navigationTitle("书源回收站")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !sources.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("清空", role: .destructive) {
                        Task { await clearAll() }
                    }
                }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        sources = (try? await env.bookSourceTrashStore.all()) ?? []
    }

    private func restore(_ source: BookSource) async {
        try? await env.bookSourceStore.importSources([source])
        try? await env.bookSourceTrashStore.remove(bookSourceUrl: source.bookSourceUrl)
        await reload()
    }

    private func permanentlyDelete(at offsets: IndexSet) {
        let toDelete = offsets.map { sources[$0] }
        Task {
            for source in toDelete {
                try? await env.bookSourceTrashStore.remove(bookSourceUrl: source.bookSourceUrl)
            }
            await reload()
        }
    }

    private func clearAll() async {
        try? await env.bookSourceTrashStore.removeAll()
        await reload()
    }
}
