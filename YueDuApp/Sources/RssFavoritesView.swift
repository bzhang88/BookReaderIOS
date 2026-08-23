import SwiftUI
import WebBookOrchestrator

/// Flat list of favorited articles across every subscription -- reachable from `RssListView`'s
/// toolbar rather than nested under any one source, since a favorite is meant to survive being
/// found again regardless of which feed it came from.
struct RssFavoritesView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var favorites: [RssFavoriteArticle] = []

    var body: some View {
        List {
            if favorites.isEmpty {
                ContentUnavailableView(
                    "还没有收藏", systemImage: "star",
                    description: Text("在文章列表里点星标即可收藏")
                )
            }
            ForEach(favorites) { favorite in
                NavigationLink {
                    RssArticleReaderView(article: RssArticle(
                        title: favorite.title, link: favorite.link, pubDate: favorite.pubDate, summary: favorite.summary
                    ))
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(favorite.title).font(.headline).lineLimit(2)
                        Text(favorite.sourceName).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("收藏")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    private func reload() async {
        favorites = (try? await env.rssFavoriteStore.all()) ?? []
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { favorites[$0] }
        Task {
            for favorite in toDelete {
                try? await env.rssFavoriteStore.remove(link: favorite.link)
            }
            await reload()
        }
    }
}
