import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import Persistence

/// Lets the user replace a shelf book's cover image without switching its source -- searches every
/// enabled source by title for candidate covers (reusing the same grouping/ranking machinery
/// `ChangeSourceView` uses for its "find this book elsewhere" flow, just harvesting cover URLs
/// instead of offering to switch), plus a manual "paste an image URL" fallback for when none of
/// the found covers look right.
struct CoverPickerView: View {
    let bookName: String
    let onSelect: (String) async -> Void

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var coverUrls: [String] = []
    @State private var galleryCovers: [SavedCover] = []
    @State private var isSearching = false
    @State private var manualUrlText = ""

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        TextField("或直接输入图片网址", text: $manualUrlText)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("使用") {
                            select(manualUrlText)
                        }
                        .disabled(manualUrlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)

                    if !galleryCovers.isEmpty {
                        Text("我的相册").font(.headline).padding(.horizontal)
                        coverGrid(galleryCovers.map(\.url))
                    }

                    Text("从其他书源查找").font(.headline).padding(.horizontal)
                    if isSearching && coverUrls.isEmpty {
                        ProgressView("正在其他书源里查找封面…").frame(maxWidth: .infinity)
                    } else if coverUrls.isEmpty {
                        ContentUnavailableView(
                            "没有找到其他封面", systemImage: "photo",
                            description: Text("可以在上面直接输入图片网址")
                        )
                    } else {
                        coverGrid(coverUrls)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("更换封面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .task {
                async let searchTask: Void = search()
                async let galleryTask: Void = loadGallery()
                _ = await (searchTask, galleryTask)
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func coverGrid(_ urls: [String]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(urls, id: \.self) { url in
                Button {
                    select(url)
                } label: {
                    AsyncImage(url: URL(string: url)) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle().fill(.quaternary)
                        }
                    }
                    .frame(width: 90, height: 126)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    /// Saves every applied cover into the gallery -- there's no separate explicit "save to gallery"
    /// step; using a cover here is itself what makes it show up there next time (see
    /// `CoverGalleryStore`'s doc comment).
    private func select(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            try? await env.coverGalleryStore.add(SavedCover(url: trimmed, bookName: bookName))
            await onSelect(trimmed)
            dismiss()
        }
    }

    private func loadGallery() async {
        galleryCovers = (try? await env.coverGalleryStore.all()) ?? []
    }

    private func search() async {
        let sources = (try? await env.bookSourceStore.enabled()) ?? []
        guard !sources.isEmpty else { return }
        isSearching = true
        var groups: [GroupedSearchResult] = []
        let stream = MultiSourceSearchService.search(sources: sources, keyword: bookName, httpClient: env.httpClient)
        for await outcome in stream {
            groups = SearchResultGrouper.merge(outcome.results, into: groups)
        }
        groups = groups.rankedByRelevance(query: bookName)

        var seen = Set<String>()
        var urls: [String] = []
        for group in groups {
            for entry in group.entries {
                guard let coverUrl = entry.coverUrl, !coverUrl.isEmpty, !seen.contains(coverUrl) else { continue }
                seen.insert(coverUrl)
                urls.append(coverUrl)
            }
        }
        coverUrls = urls
        isSearching = false
    }
}
