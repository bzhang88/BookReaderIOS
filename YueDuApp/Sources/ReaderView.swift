import SwiftUI
import UIKit
import BookSourceModel
import WebBookOrchestrator
import Persistence

struct ReaderView: View {
    let source: BookSource
    let bookUrl: String
    let chapters: [BookChapter]
    let bookTitle: String
    @State private var currentIndex: Int

    @EnvironmentObject private var env: AppEnvironment
    @State private var text: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingSettings = false
    @State private var screenBrightness: Double = Double(UIScreen.main.brightness)

    @AppStorage(ReaderSettingsKey.fontSize) private var fontSize: Double = 18
    @AppStorage(ReaderSettingsKey.lineSpacing) private var lineSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.paragraphSpacing) private var paragraphSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.theme) private var theme: ReaderTheme = .day
    @AppStorage(ReaderSettingsKey.keepScreenOn) private var keepScreenOn: Bool = true

    init(source: BookSource, bookUrl: String, chapters: [BookChapter], currentIndex: Int, bookTitle: String) {
        self.source = source
        self.bookUrl = bookUrl
        self.chapters = chapters
        self.bookTitle = bookTitle
        self._currentIndex = State(initialValue: currentIndex)
    }

    private var chapter: BookChapter { chapters[currentIndex] }
    private var paragraphs: [String] { text.components(separatedBy: "\n") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: paragraphSpacing) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.system(size: fontSize))
                        .lineSpacing(lineSpacing)
                        .foregroundStyle(theme.textColor)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.backgroundColor)
        .overlay {
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "sun.min")
                    Slider(value: $screenBrightness, in: 0...1)
                        .onChange(of: screenBrightness) { _, newValue in
                            UIScreen.main.brightness = CGFloat(newValue)
                        }
                    Image(systemName: "sun.max")
                }
                Text("第 \(currentIndex + 1) / \(chapters.count) 章")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button {
                        goTo(currentIndex - 1)
                    } label: {
                        Label("上一章", systemImage: "chevron.left")
                    }
                    .disabled(currentIndex <= 0)

                    Spacer()

                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "textformat.size")
                    }

                    Spacer()

                    Button {
                        goTo(currentIndex + 1)
                    } label: {
                        Label("下一章", systemImage: "chevron.right")
                    }
                    .disabled(currentIndex >= chapters.count - 1)
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: currentIndex) { await load() }
        .sheet(isPresented: $isShowingSettings) {
            ReaderSettingsSheet()
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepScreenOn }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: keepScreenOn) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
    }

    private func goTo(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        currentIndex = index
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let content = try await ContentService.fetchContent(source: source, chapter: chapter, httpClient: env.httpClient)
            text = content.text
            try? await env.shelfStore.updateProgress(
                bookUrl: bookUrl, chapterIndex: chapter.index, chapterTitle: chapter.title, characterOffset: 0
            )
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
    }
}
