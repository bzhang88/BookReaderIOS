import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import RuleEngine
import Persistence

/// Reader for image-type book sources (`bookSourceType == 2`) -- the rule engine and
/// `ContentService` needed no changes at all for this: a manga source's `ruleContent` just extracts
/// image URLs (one per line, via e.g. `@css:.img-list img@src`) instead of prose paragraphs, and
/// `ContentService.fetchContent` already returns that as plain newline-joined text the exact same
/// way it returns prose. The only new work is on the display side -- rendering each line as an
/// image instead of a paragraph of text, vertical-continuous-scroll style (the common "webtoon"
/// manga reading mode, and the simplest one to implement -- Legado itself also supports a paged
/// mode, left out here the same way this app's own text reader has no true pagination yet).
struct MangaReaderView: View {
    @State private var source: BookSource
    @State private var bookUrl: String
    let tocUrl: String
    @State private var chapters: [BookChapter]
    let bookTitle: String
    @State private var currentIndex: Int

    @EnvironmentObject private var env: AppEnvironment
    @State private var imageURLs: [URL] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isChromeVisible = true

    init(source: BookSource, bookUrl: String, tocUrl: String, chapters: [BookChapter], currentIndex: Int, bookTitle: String) {
        self._source = State(initialValue: source)
        self._bookUrl = State(initialValue: bookUrl)
        self.tocUrl = tocUrl
        self._chapters = State(initialValue: chapters)
        self._currentIndex = State(initialValue: currentIndex)
        self.bookTitle = bookTitle
    }

    private var chapter: BookChapter { chapters[currentIndex] }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(imageURLs.enumerated()), id: \.offset) { _, url in
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit().frame(maxWidth: .infinity)
                        case .failure:
                            Color.secondary.opacity(0.15)
                                .frame(height: 200)
                                .overlay(Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary))
                        default:
                            Color.secondary.opacity(0.08)
                                .frame(height: 200)
                                .overlay(ProgressView())
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { isChromeVisible.toggle() }
        }
        .background(Color.black)
        .overlay {
            if isLoading {
                ProgressView().tint(.white)
            } else if let errorMessage {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if imageURLs.isEmpty {
                ContentUnavailableView(
                    "没有解析到图片", systemImage: "photo",
                    description: Text("这个书源的正文规则没有提取出图片地址，可能不是真正的图片类书源规则")
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isChromeVisible {
                HStack {
                    Button {
                        goTo(currentIndex - 1)
                    } label: {
                        Label("上一章", systemImage: "chevron.left")
                    }
                    .disabled(currentIndex <= 0)

                    Spacer()

                    Text("第 \(currentIndex + 1) / \(chapters.count) 章")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        goTo(currentIndex + 1)
                    } label: {
                        Label("下一章", systemImage: "chevron.right")
                    }
                    .disabled(currentIndex >= chapters.count - 1)
                }
                .padding()
                .background(.bar)
            }
        }
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isChromeVisible ? .visible : .hidden, for: .navigationBar)
        .animation(.easeInOut(duration: 0.2), value: isChromeVisible)
        .task(id: "\(source.bookSourceUrl)#\(currentIndex)") { await load() }
    }

    private func goTo(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        currentIndex = index
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let cached = try? await env.chapterCacheStore.chapter(bookUrl: bookUrl, index: chapter.index)
            let content: ChapterContent
            if let cached {
                content = cached
            } else {
                content = try await ContentService.fetchContent(source: source, chapter: chapter, httpClient: env.httpClient)
            }
            imageURLs = content.text
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .compactMap { URL(string: URLResolver.resolve($0, against: chapter.url)) }
            try? await env.shelfStore.updateProgress(
                bookUrl: bookUrl, chapterIndex: chapter.index, chapterTitle: chapter.title, characterOffset: 0
            )
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
    }
}
