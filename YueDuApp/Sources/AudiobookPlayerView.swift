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
    /// Per-book, `UserDefaults`-keyed settings (not `ShelfStore`/backup-tracked) -- same convention
    /// `TocView.isReversed` already uses for a setting that's real and persisted but doesn't need
    /// full Codable-migration/backup treatment. Mirrors Legado's own per-book `Book.config.playMode`/
    /// `openCredits`/`closeCredits` (`AudioSkipCredits.kt`, `model/AudioPlay.kt`).
    @State private var playMode: AudioPlayMode = .sequential
    @State private var openCreditsSeconds: Int = 0
    @State private var closeCreditsSeconds: Int = 0
    @State private var isShowingSkipCreditsSheet = false

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
                    advanceToNextByPlayMode()
                } label: {
                    Image(systemName: "forward.end.fill").font(.title2)
                }
                // Only `.sequential` has a real "last chapter" -- `.listLoop` wraps back to the
                // first chapter and `.random`/`.singleLoop` don't advance linearly at all, matching
                // Legado's own `AudioPlay.next()` (the manual skip-next button calls the exact same
                // playMode-aware dispatcher there too, not a separate always-linear "next").
                .disabled(playMode == .sequential && currentIndex >= chapters.count - 1)
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
        .onAppear {
            player.onFinished = { advanceToNextByPlayMode() }
            // Real gap found comparing against Legado: lock-screen/Control Center next/previous had
            // no effect before this -- see `AudiobookPlayerController.onRequestNextChapter`'s doc
            // comment. `onRequestNextChapter` now goes through the same playMode-aware dispatcher
            // the in-app "next" button uses (see that button's own doc comment); `prev` stays plain,
            // matching Legado's `AudioPlay.prev()` never considering playMode either.
            player.onRequestNextChapter = { advanceToNextByPlayMode() }
            player.onRequestPreviousChapter = { goTo(currentIndex - 1) }
            loadPerBookSettings()
        }
        .onDisappear { player.stop() }
        .sheet(isPresented: $isShowingSkipCreditsSheet) { skipCreditsSheet }
    }

    // Broken out into its own `@ToolbarContentBuilder` property rather than an inline `.toolbar {
    // }` closure -- same "compiler unable to type-check this expression in reasonable time" CI
    // failure class `ShelfView`/`SourceCheckView` already document: Windows-local `swift build`
    // can't catch it, only the real macOS `xcodebuild` runner can, so this stays proactively split.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) { playbackRateMenu }
        ToolbarItem(placement: .primaryAction) { sleepTimerMenu }
        ToolbarItem(placement: .primaryAction) { playModeMenu }
        ToolbarItem(placement: .primaryAction) {
            Button {
                isShowingSkipCreditsSheet = true
            } label: {
                Image(systemName: "timer")
            }
        }
    }

    @ViewBuilder
    private var playbackRateMenu: some View {
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

    @ViewBuilder
    private var sleepTimerMenu: some View {
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

    /// Matches Legado's own 4-mode `AudioPlay.PlayMode` (`顺序播放`/`单曲循环`/`随机播放`/`列表循环`)
    /// -- a `Menu` with a checkmark on the current mode rather than Legado's single tap-to-cycle
    /// icon button, for consistency with this same toolbar's two other menus (rate/sleep timer)
    /// rather than introducing a third, different interaction style.
    @ViewBuilder
    private var playModeMenu: some View {
        Menu {
            ForEach(AudioPlayMode.allCases) { mode in
                Button {
                    setPlayMode(mode)
                } label: {
                    if playMode == mode {
                        Label(mode.displayName, systemImage: "checkmark")
                    } else {
                        Text(mode.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: playMode.iconName)
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

    /// Single dispatcher for "this chapter is done, what plays next" -- called by the manual "next"
    /// button, the lock-screen/Control Center next-track command, and `player.onFinished` (both a
    /// natural end-of-stream and a skip-tail-threshold end) alike, matching how Legado's own
    /// `AudioPlay.next()` is the one function all of those call sites share. `.singleLoop` reloads
    /// directly rather than going through `goTo` -- `currentIndex` doesn't change, so the `.task(id:)`
    /// driving `load()` wouldn't refire on its own.
    private func advanceToNextByPlayMode() {
        switch playMode {
        case .sequential:
            guard currentIndex < chapters.count - 1 else { return }
            goTo(currentIndex + 1)
        case .singleLoop:
            Task { await load() }
        case .random:
            goTo(Int.random(in: 0..<chapters.count))
        case .listLoop:
            goTo((currentIndex + 1) % chapters.count)
        }
    }

    private func loadPerBookSettings() {
        if let mode = AudioPlayMode(rawValue: UserDefaults.standard.integer(forKey: playModeKey)) {
            playMode = mode
        }
        openCreditsSeconds = UserDefaults.standard.integer(forKey: openCreditsKey)
        closeCreditsSeconds = UserDefaults.standard.integer(forKey: closeCreditsKey)
    }

    private func setPlayMode(_ mode: AudioPlayMode) {
        playMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: playModeKey)
    }

    private func setOpenCredits(_ seconds: Int) {
        openCreditsSeconds = seconds
        UserDefaults.standard.set(seconds, forKey: openCreditsKey)
    }

    private func setCloseCredits(_ seconds: Int) {
        closeCreditsSeconds = seconds
        UserDefaults.standard.set(seconds, forKey: closeCreditsKey)
    }

    private var playModeKey: String { "audiobook.playMode.\(bookUrl)" }
    private var openCreditsKey: String { "audiobook.openCredits.\(bookUrl)" }
    private var closeCreditsKey: String { "audiobook.closeCredits.\(bookUrl)" }

    /// Only applied the next time a chapter loads (matches Legado's own `AudioSkipCredits` dialog,
    /// which doesn't retroactively re-seek whatever's already playing) -- not a live re-seek of the
    /// currently-playing stream.
    private var skipCreditsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(
                        "片头跳过: \(openCreditsSeconds) 秒",
                        value: Binding(get: { openCreditsSeconds }, set: { setOpenCredits($0) }), in: 0...300, step: 5
                    )
                    Stepper(
                        "片尾跳过: \(closeCreditsSeconds) 秒",
                        value: Binding(get: { closeCreditsSeconds }, set: { setCloseCredits($0) }), in: 0...300, step: 5
                    )
                } footer: {
                    Text("跳过每一章开头/结尾指定秒数，下一章加载时生效。")
                }
            }
            .navigationTitle("跳过片头片尾")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { isShowingSkipCreditsSheet = false }
                }
            }
        }
        .presentationDetents([.height(260)])
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
            player.play(
                url: url, bookTitle: bookTitle, chapterTitle: chapter.title,
                openCreditsSeconds: Double(openCreditsSeconds), closeCreditsSeconds: Double(closeCreditsSeconds)
            )
        } catch {
            errorMessage = "\(error)"
        }
    }
}

/// Mirrors Legado's own `AudioPlay.PlayMode` enum (`model/AudioPlay.kt`) one-for-one, including
/// raw-value order -- `.sequential` (顺序播放，播完最后一章停止) is `0` so a book that never had a
/// play mode explicitly saved (`UserDefaults.standard.integer(forKey:)` reading back the default
/// `0` for an absent key) reads as the same "just play through and stop" behavior this player always
/// had before this feature existed.
enum AudioPlayMode: Int, CaseIterable, Identifiable {
    case sequential = 0
    case singleLoop = 1
    case random = 2
    case listLoop = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .sequential: return "顺序播放"
        case .singleLoop: return "单曲循环"
        case .random: return "随机播放"
        case .listLoop: return "列表循环"
        }
    }

    var iconName: String {
        switch self {
        case .sequential: return "arrow.right.to.line"
        case .singleLoop: return "repeat.1"
        case .random: return "shuffle"
        case .listLoop: return "repeat"
        }
    }
}
