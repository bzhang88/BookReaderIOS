import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import RuleEngine
import Persistence

/// Player for audio-type book sources (`bookSourceType == 1`). Confirmed against Legado_Max's own
/// `AudioPlay.kt` (`durPlayUrl = content` right after the exact same `WebBook.getContent` call text
/// books use) that audio sources reuse the identical search/detail/toc/content pipeline as text
/// ones -- the only difference is that `ruleContent`'s extracted "content" is a single playable
/// stream URL instead of prose, so this needed no changes to `ContentService` or the rule engine
/// either, the same shared-pipeline situation as `MangaReaderView`.
struct AudiobookPlayerView: View {
    @State private var source: BookSource
    @State private var bookUrl: String
    let tocUrl: String
    @State private var chapters: [BookChapter]
    let bookTitle: String
    @State private var currentIndex: Int

    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var player = AudiobookPlayerController()
    @State private var isLoading = true
    @State private var errorMessage: String?

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
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "headphones")
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 4) {
                Text(chapter.title).font(.title3).bold().multilineTextAlignment(.center)
                Text(bookTitle).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            if isLoading {
                ProgressView()
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                        in: 0...max(player.duration, 1)
                    )
                    HStack {
                        Text(formatted(player.currentTime))
                        Spacer()
                        Text(formatted(player.duration))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }

            HStack(spacing: 40) {
                Button {
                    goTo(currentIndex - 1)
                } label: {
                    Image(systemName: "backward.end.fill").font(.title2)
                }
                .disabled(currentIndex <= 0)

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                }
                .disabled(isLoading || errorMessage != nil)

                Button {
                    goTo(currentIndex + 1)
                } label: {
                    Image(systemName: "forward.end.fill").font(.title2)
                }
                .disabled(currentIndex >= chapters.count - 1)
            }

            Text("第 \(currentIndex + 1) / \(chapters.count) 章")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .navigationTitle("听书")
        .navigationBarTitleDisplayMode(.inline)
        // Matches `ReaderView`'s same fix -- without this, the main app's 书架/发现/订阅/我的 tab
        // bar stayed visible underneath this player's own controls.
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbarContent }
        .task(id: "\(source.bookSourceUrl)#\(currentIndex)") { await load() }
        .onAppear { player.onFinished = { advanceOnFinish() } }
        .onDisappear { player.stop() }
    }

    // Broken out into its own `@ToolbarContentBuilder` property rather than an inline `.toolbar {
    // }` closure -- same "compiler unable to type-check this expression in reasonable time" CI
    // failure class `ShelfView`/`SourceCheckView` already document: Windows-local `swift build`
    // can't catch it, only the real macOS `xcodebuild` runner can, so this stays proactively split.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(Self.playbackRates, id: \.self) { rate in
                    Button {
                        player.setPlaybackRate(rate)
                    } label: {
                        if player.playbackRate == rate {
                            Label(Self.rateLabel(rate), systemImage: "checkmark")
                        } else {
                            Text(Self.rateLabel(rate))
                        }
                    }
                }
            } label: {
                Text(Self.rateLabel(player.playbackRate))
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if player.sleepTimerRemainingSeconds != nil {
                    Button("关闭定时", role: .destructive) { player.cancelSleepTimer() }
                }
                ForEach(Self.sleepTimerMinutesOptions, id: \.self) { minutes in
                    Button("\(minutes) 分钟后暂停") { player.startSleepTimer(minutes: minutes) }
                }
            } label: {
                if let remaining = player.sleepTimerRemainingSeconds {
                    Label(formatted(Double(remaining)), systemImage: "moon.zzz.fill")
                } else {
                    Image(systemName: "moon.zzz")
                }
            }
        }
    }

    private static let playbackRates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    private static let sleepTimerMinutesOptions = [15, 30, 45, 60]

    private static func rateLabel(_ rate: Float) -> String {
        if rate == rate.rounded() { return "\(Int(rate))x" }
        var text = String(format: "%.2f", rate)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + "x"
    }

    private func goTo(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        currentIndex = index
    }

    private func advanceOnFinish() {
        guard currentIndex < chapters.count - 1 else { return }
        goTo(currentIndex + 1)
    }

    private func formatted(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        player.stop()
        defer { isLoading = false }
        do {
            let cached = try? await env.chapterCacheStore.chapter(bookUrl: bookUrl, index: chapter.index)
            let content: ChapterContent
            if let cached {
                content = cached
            } else {
                content = try await ContentService.fetchContent(source: source, chapter: chapter, httpClient: env.httpClient)
            }
            let trimmed = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let url = URL(string: URLResolver.resolve(trimmed, against: chapter.url)) else {
                errorMessage = "没有解析到播放地址，这个书源的正文规则可能不是真正的音频类书源规则"
                return
            }
            try? await env.shelfStore.updateProgress(
                bookUrl: bookUrl, chapterIndex: chapter.index, chapterTitle: chapter.title, characterOffset: 0
            )
            player.play(url: url, bookTitle: bookTitle, chapterTitle: chapter.title)
        } catch {
            errorMessage = "\(error)"
        }
    }
}
