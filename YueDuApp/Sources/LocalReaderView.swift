import SwiftUI
import UIKit
import BookSourceModel
import WebBookOrchestrator
import Persistence

/// Reader for a locally-imported .txt book. Deliberately simpler than `ReaderView`: no network
/// fetch (all chapter text is already in `book.chapters`), no read-aloud/TTS in this first
/// increment. Shares its typography/theme `@AppStorage` keys with `ReaderView` so font size and
/// theme choice carry over between network and local books rather than needing to be set twice.
struct LocalReaderView: View {
    let book: LocalBook

    @EnvironmentObject private var env: AppEnvironment
    @State private var currentIndex: Int
    @State private var isShowingSettings = false
    @State private var isCurrentChapterBookmarked = false
    @State private var matchedReplaceRules: [ReplaceRule] = []
    @State private var isShowingContentSearch = false
    @State private var isShowingAISummary = false
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(ReaderSettingsKey.fontSize) private var fontSize: Double = 18
    @AppStorage(ReaderSettingsKey.lineSpacing) private var lineSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.paragraphSpacing) private var paragraphSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.theme) private var theme: ReaderTheme = .day
    @AppStorage(ReaderSettingsKey.keepScreenOn) private var keepScreenOn: Bool = true
    @AppStorage(ReaderSettingsKey.chineseConversion) private var chineseConversion: ChineseConversionMode = .off
    @AppStorage(ReaderSettingsKey.volumeKeyPage) private var volumeKeyPageEnabled: Bool = false
    @State private var volumeButtonController = VolumeButtonPageTurnController()
    @State private var volumeScrollIndex = 0

    /// `startChapterIndex` overrides the book's own last-read position -- used when jumping in from
    /// a bookmark, which names an exact chapter rather than "wherever I left off."
    init(book: LocalBook, startChapterIndex: Int? = nil) {
        self.book = book
        let fallback = book.lastReadChapterIndex.flatMap { book.chapters.indices.contains($0) ? $0 : nil } ?? 0
        let start = startChapterIndex.flatMap { book.chapters.indices.contains($0) ? $0 : nil } ?? fallback
        self._currentIndex = State(initialValue: start)
    }

    private var chapter: LocalChapter { book.chapters[currentIndex] }
    private var paragraphs: [String] { purifiedText.components(separatedBy: "\n") }
    @State private var purifiedText: String = ""

    var body: some View {
        ScrollViewReader { scrollProxy in
        ScrollView {
            VStack(alignment: .leading, spacing: paragraphSpacing) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    Text(paragraph)
                        .font(.system(size: fontSize))
                        .lineSpacing(lineSpacing)
                        .foregroundStyle(theme.textColor(for: colorScheme))
                        .padding(.horizontal, 4)
                        .id(index)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.backgroundColor(for: colorScheme))
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Text("第 \(currentIndex + 1) / \(book.chapters.count) 章")
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
                        Task { await toggleBookmark() }
                    } label: {
                        Image(systemName: isCurrentChapterBookmarked ? "bookmark.fill" : "bookmark")
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
                    .disabled(currentIndex >= book.chapters.count - 1)
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingContentSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAISummary = true
                } label: {
                    Image(systemName: "sparkles")
                }
            }
        }
        .task(id: currentIndex) { await load() }
        .sheet(isPresented: $isShowingSettings) {
            LocalReaderSettingsSheet(matchedRules: matchedReplaceRules)
        }
        .sheet(isPresented: $isShowingContentSearch) {
            ChapterContentSearchView(
                loadChapters: {
                    book.chapters.enumerated().map { index, chapter in (index: index, title: chapter.title, text: chapter.text) }
                },
                onSelect: { index in goTo(index) }
            )
        }
        .sheet(isPresented: $isShowingAISummary) {
            AIChapterSummaryView(chapterTitle: chapter.title, chapterText: purifiedText)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepScreenOn
            startVolumeButtonPagingIfEnabled(proxy: scrollProxy)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            volumeButtonController.stop()
        }
        .onChange(of: keepScreenOn) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
        .onChange(of: volumeKeyPageEnabled) { _, isEnabled in
            if isEnabled {
                startVolumeButtonPagingIfEnabled(proxy: scrollProxy)
            } else {
                volumeButtonController.stop()
            }
        }
        .onChange(of: currentIndex) { _, _ in
            volumeScrollIndex = 0
        }
        }
    }

    private func startVolumeButtonPagingIfEnabled(proxy: ScrollViewProxy) {
        guard volumeKeyPageEnabled else { return }
        guard let window = Self.keyWindow() else { return }
        volumeButtonController.onVolumeUp = { handleVolumeKeyTurn(direction: -1, proxy: proxy) }
        volumeButtonController.onVolumeDown = { handleVolumeKeyTurn(direction: 1, proxy: proxy) }
        volumeButtonController.start(in: window)
    }

    private func handleVolumeKeyTurn(direction: Int, proxy: ScrollViewProxy) {
        guard !paragraphs.isEmpty else { return }
        let step = 4
        volumeScrollIndex = min(max(volumeScrollIndex + direction * step, 0), paragraphs.count - 1)
        withAnimation {
            proxy.scrollTo(volumeScrollIndex, anchor: .top)
        }
    }

    private static func keyWindow() -> UIView? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    private func goTo(_ index: Int) {
        guard book.chapters.indices.contains(index) else { return }
        currentIndex = index
    }

    private func applyChineseConversion(_ text: String) -> String {
        switch chineseConversion {
        case .off: return text
        case .toTraditional: return ChineseTextConverter.convert(text, direction: .simplifiedToTraditional)
        case .toSimplified: return ChineseTextConverter.convert(text, direction: .traditionalToSimplified)
        }
    }

    private func load() async {
        let replaceRules = (try? await env.replaceRuleStore.enabled()) ?? []
        let purified = ReplaceRuleApplier.applyReportingMatches(replaceRules, to: chapter.text, sourceUrl: "")
        purifiedText = applyChineseConversion(purified.result)
        matchedReplaceRules = purified.matchedRules
        try? await env.localBookStore.updateProgress(id: book.id, chapterIndex: currentIndex)
        isCurrentChapterBookmarked = (try? await env.bookmarkStore.isBookmarked(
            bookIdentifier: book.id, chapterIndex: currentIndex
        )) ?? false
    }

    private func toggleBookmark() async {
        if isCurrentChapterBookmarked {
            try? await env.bookmarkStore.remove(bookIdentifier: book.id, chapterIndex: currentIndex)
            isCurrentChapterBookmarked = false
        } else {
            let bookmark = Bookmark(
                isLocal: true, bookIdentifier: book.id, bookTitle: book.title,
                chapterIndex: currentIndex, chapterTitle: chapter.title
            )
            try? await env.bookmarkStore.add(bookmark)
            isCurrentChapterBookmarked = true
        }
    }
}

/// Trimmed-down variant of `ReaderSettingsSheet` without the TTS "朗读" section -- `LocalReaderView`
/// has no read-aloud button in this increment, and showing a rate slider with nothing to control
/// would look like a broken feature rather than an absent one.
struct LocalReaderSettingsSheet: View {
    var matchedRules: [ReplaceRule] = []

    @AppStorage(ReaderSettingsKey.fontSize) private var fontSize: Double = 18
    @AppStorage(ReaderSettingsKey.lineSpacing) private var lineSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.paragraphSpacing) private var paragraphSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.theme) private var theme: ReaderTheme = .day
    @AppStorage(ReaderSettingsKey.keepScreenOn) private var keepScreenOn: Bool = true
    @AppStorage(ReaderSettingsKey.chineseConversion) private var chineseConversion: ChineseConversionMode = .off
    @AppStorage(ReaderSettingsKey.volumeKeyPage) private var volumeKeyPageEnabled: Bool = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("主题") {
                    ThemeSwatchPicker(theme: $theme)
                }

                Section("字体") {
                    VStack(alignment: .leading) {
                        Text("字号: \(Int(fontSize))")
                        Slider(value: $fontSize, in: 12...32, step: 1)
                    }
                    VStack(alignment: .leading) {
                        Text("行间距: \(Int(lineSpacing))")
                        Slider(value: $lineSpacing, in: 0...24, step: 1)
                    }
                    VStack(alignment: .leading) {
                        Text("段间距: \(Int(paragraphSpacing))")
                        Slider(value: $paragraphSpacing, in: 0...32, step: 1)
                    }
                }

                Section("简繁转换") {
                    Picker("简繁转换", selection: $chineseConversion) {
                        ForEach(ChineseConversionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("其他") {
                    Toggle("阅读时屏幕常亮", isOn: $keepScreenOn)
                    Toggle("音量键翻页", isOn: $volumeKeyPageEnabled)
                }

                Section("本章生效的净化规则") {
                    if matchedRules.isEmpty {
                        Text("本章没有命中任何净化规则").foregroundStyle(.secondary)
                    } else {
                        ForEach(matchedRules) { rule in
                            Text(rule.name)
                        }
                    }
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
