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
    @State private var isChromeVisible = true
    @State private var screenBrightness: Double = Double(UIScreen.main.brightness)
    @State private var highlightRules: [HighlightRule] = []
    @StateObject private var readAloud = ReadAloudController()

    @AppStorage(ReaderSettingsKey.fontSize) private var fontSize: Double = 18
    @AppStorage(ReaderSettingsKey.lineSpacing) private var lineSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.paragraphSpacing) private var paragraphSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.theme) private var theme: ReaderTheme = .day
    @AppStorage(ReaderSettingsKey.keepScreenOn) private var keepScreenOn: Bool = true
    @AppStorage(ReaderSettingsKey.readAloudRate) private var readAloudRate: Double = 0.5

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
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    highlightedText(paragraph)
                        .font(.system(size: fontSize))
                        .lineSpacing(lineSpacing)
                        .padding(.horizontal, 4)
                        .background(
                            readAloud.isSpeaking && index == readAloud.currentParagraphIndex
                                ? Color.accentColor.opacity(0.15) : Color.clear
                        )
                }
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture {
                isChromeVisible.toggle()
            }
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
            if isChromeVisible {
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

                    if readAloud.isSpeaking {
                        HStack(spacing: 20) {
                            Button {
                                readAloud.previousParagraph()
                            } label: {
                                Image(systemName: "backward.end")
                            }
                            Button {
                                readAloud.togglePause()
                            } label: {
                                Image(systemName: readAloud.isPaused ? "play.fill" : "pause.fill")
                            }
                            Button {
                                readAloud.nextParagraph()
                            } label: {
                                Image(systemName: "forward.end")
                            }
                            Button(role: .destructive) {
                                readAloud.stop()
                            } label: {
                                Image(systemName: "stop.fill")
                            }
                        }
                        .font(.title3)
                    }

                    HStack {
                        Button {
                            goTo(currentIndex - 1)
                        } label: {
                            Label("上一章", systemImage: "chevron.left")
                        }
                        .disabled(currentIndex <= 0)

                        Spacer()

                        Button {
                            if readAloud.isSpeaking {
                                readAloud.stop()
                            } else {
                                readAloud.setRate(Float(readAloudRate))
                                readAloud.start(paragraphs: paragraphs, bookTitle: bookTitle, chapterTitle: chapter.title)
                            }
                        } label: {
                            Image(systemName: readAloud.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                        }

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
        }
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isChromeVisible ? .visible : .hidden, for: .navigationBar)
        .animation(.easeInOut(duration: 0.2), value: isChromeVisible)
        .task(id: currentIndex) { await load() }
        .sheet(isPresented: $isShowingSettings) {
            ReaderSettingsSheet()
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepScreenOn }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            readAloud.stop()
        }
        .onChange(of: keepScreenOn) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
        .onChange(of: readAloudRate) { _, newValue in
            // AVSpeechSynthesizer can't change an utterance's rate mid-speech -- this takes effect
            // starting with the next paragraph, not a jarring restart of the current one.
            readAloud.setRate(Float(newValue))
        }
        .onChange(of: currentIndex) { _, _ in
            // Chapter navigation (prev/next buttons, or a lock-screen "next track" tap while at the
            // chapter's last paragraph in a future increment) invalidates whatever was being read
            // from the old chapter's text -- stopping is simpler and safer than trying to carry
            // read-aloud state across a chapter reload for this first version.
            readAloud.stop()
        }
    }

    private func goTo(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        currentIndex = index
    }

    /// Builds one paragraph's flowing text as a concatenation of styled `Text` runs -- SwiftUI's
    /// `Text + Text` only carries text-level attributes (color/weight/etc.) across the join, not
    /// view-level ones like `.background()`, so highlighted spans are set apart with color+bold
    /// rather than a literal background tint.
    private func highlightedText(_ paragraph: String) -> Text {
        let segments = HighlightRuleApplier.segments(highlightRules, in: paragraph)
        return segments.reduce(Text("")) { partial, segment in
            if segment.isHighlighted {
                return partial + Text(segment.text).foregroundStyle(.orange).bold()
            } else {
                return partial + Text(segment.text).foregroundStyle(theme.textColor)
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let content = try await ContentService.fetchContent(source: source, chapter: chapter, httpClient: env.httpClient)
            let replaceRules = (try? await env.replaceRuleStore.enabled()) ?? []
            text = ReplaceRuleApplier.apply(replaceRules, to: content.text, sourceUrl: source.bookSourceUrl)
            highlightRules = (try? await env.highlightRuleStore.enabled()) ?? []
            try? await env.shelfStore.updateProgress(
                bookUrl: bookUrl, chapterIndex: chapter.index, chapterTitle: chapter.title, characterOffset: 0
            )
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
    }
}
