import SwiftUI
import BookSourceModel
import WebBookOrchestrator

struct RssArticleListView: View {
    let source: RssSource

    @EnvironmentObject private var env: AppEnvironment
    @State private var articles: [RssArticle] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// Parsed from `source.sortUrl` the same way `ExploreView` parses `BookSource.exploreUrl` --
    /// empty when the source only offers one feed, in which case no chip row shows at all and
    /// `load()` just fetches `source.sourceUrl` directly (via `selectedKind == nil`).
    @State private var kinds: [ExploreKind] = []
    @State private var selectedKind: ExploreKind?
    @State private var favoritedLinks: Set<String> = []
    @State private var readLinks: Set<String> = []
    @State private var isShowingLogin = false

    var body: some View {
        VStack(spacing: 0) {
            categoryChipsRow
            List(articles) { article in
                articleRow(article)
            }
        }
        .overlay { articleListOverlay }
        .navigationTitle(source.sourceName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .refreshable { await load() }
        .task { await initialLoad() }
        // Refreshes `readLinks` (a cheap local file read, not a network fetch) every time this list
        // becomes visible again -- including when popping back from `RssArticleReaderView`, which is
        // what actually marks an article read. `.task` alone wouldn't refire for that since this
        // view instance itself never goes away, just gets covered and re-exposed by the push/pop.
        .onAppear { Task { await refreshReadLinks() } }
        .sheet(isPresented: $isShowingLogin) {
            SourceLoginView(source: BookSource(
                bookSourceUrl: source.sourceUrl, bookSourceName: source.sourceName, loginUrl: source.loginUrl
            ))
        }
    }

    @ViewBuilder
    private var categoryChipsRow: some View {
        if !kinds.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(kinds, id: \.url) { kind in
                        Button {
                            Task { await selectKind(kind) }
                        } label: {
                            Text(kind.name)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    kind.url == selectedKind?.url
                                        ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1),
                                    in: Capsule()
                                )
                                .foregroundStyle(kind.url == selectedKind?.url ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            Divider()
        }
    }

    /// `NavigationLink` + a sibling favorite `Button`, not a button nested *inside* the
    /// `NavigationLink`'s own label -- same tap-swallowing gotcha `ExploreView.resultRow`'s doc
    /// comment already documents for this exact shape.
    @ViewBuilder
    private func articleRow(_ article: RssArticle) -> some View {
        let isRead = readLinks.contains(article.link)
        HStack(alignment: .top, spacing: 8) {
            NavigationLink {
                RssArticleReaderView(article: article)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(article.title)
                        .font(.headline)
                        .fontWeight(isRead ? .regular : .bold)
                        .foregroundStyle(isRead ? .secondary : .primary)
                        .lineLimit(2)
                    if let pubDate = article.pubDate, !pubDate.isEmpty {
                        Text(pubDate).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            favoriteButton(article)
        }
    }

    @ViewBuilder
    private func favoriteButton(_ article: RssArticle) -> some View {
        let isFavorited = favoritedLinks.contains(article.link)
        Button {
            Task { await toggleFavorite(article) }
        } label: {
            Image(systemName: isFavorited ? "star.fill" : "star")
                .foregroundStyle(isFavorited ? Color.yellow : Color.secondary)
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var articleListOverlay: some View {
        if isLoading {
            ProgressView()
        } else if let errorMessage {
            ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
        } else if articles.isEmpty {
            ContentUnavailableView("没有文章", systemImage: "doc.text")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if source.loginUrl != nil {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingLogin = true
                } label: {
                    Image(systemName: "person.crop.circle")
                }
            }
        }
    }

    private func initialLoad() async {
        kinds = ExploreKindParser.parse(source.sortUrl ?? "")
        selectedKind = kinds.first
        favoritedLinks = Set((try? await env.rssFavoriteStore.all())?.map(\.link) ?? [])
        await refreshReadLinks()
        await load()
    }

    private func refreshReadLinks() async {
        readLinks = (try? await env.rssReadStore.readLinks()) ?? []
    }

    private func selectKind(_ kind: ExploreKind) async {
        selectedKind = kind
        await load()
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            articles = try await RssFeedService.fetchArticles(source: source, url: selectedKind?.url, httpClient: env.httpClient)
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
    }

    private func toggleFavorite(_ article: RssArticle) async {
        if favoritedLinks.contains(article.link) {
            try? await env.rssFavoriteStore.remove(link: article.link)
            favoritedLinks.remove(article.link)
        } else {
            try? await env.rssFavoriteStore.add(RssFavoriteArticle(
                link: article.link, title: article.title, sourceUrl: source.sourceUrl, sourceName: source.sourceName,
                pubDate: article.pubDate, summary: article.summary
            ))
            favoritedLinks.insert(article.link)
        }
    }
}

struct RssArticleReaderView: View {
    let article: RssArticle

    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        Group {
            if let url = URL(string: article.link) {
                WebArticleView(url: url)
            } else {
                ContentUnavailableView("链接无效", systemImage: "link.badge.plus")
            }
        }
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { try? await env.rssReadStore.markRead(article.link) }
    }
}
