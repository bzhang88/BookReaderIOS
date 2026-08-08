import SwiftUI
import BookSourceModel
import WebBookOrchestrator

struct RssArticleListView: View {
    let source: RssSource

    @EnvironmentObject private var env: AppEnvironment
    @State private var articles: [RssArticle] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List(articles) { article in
            NavigationLink {
                RssArticleReaderView(article: article)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(article.title).font(.headline).lineLimit(2)
                    if let pubDate = article.pubDate, !pubDate.isEmpty {
                        Text(pubDate).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if articles.isEmpty {
                ContentUnavailableView("没有文章", systemImage: "doc.text")
            }
        }
        .navigationTitle(source.sourceName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            articles = try await RssFeedService.fetchArticles(source: source, httpClient: env.httpClient)
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
    }
}

struct RssArticleReaderView: View {
    let article: RssArticle

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
    }
}
