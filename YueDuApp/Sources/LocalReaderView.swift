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

    @AppStorage(ReaderSettingsKey.fontSize) private var fontSize: Double = 18
    @AppStorage(ReaderSettingsKey.lineSpacing) private var lineSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.paragraphSpacing) private var paragraphSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.theme) private var theme: ReaderTheme = .day
    @AppStorage(ReaderSettingsKey.keepScreenOn) private var keepScreenOn: Bool = true

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
        ScrollView {
            VStack(alignment: .leading, spacing: paragraphSpacing) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.system(size: fontSize))
                        .lineSpacing(lineSpacing)
                        .foregroundStyle(theme.textColor)
                        .padding(.horizontal, 4)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.backgroundColor)
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
        .task(id: currentIndex) { await load() }
        .sheet(isPresented: $isShowingSettings) {
            LocalReaderSettingsSheet(matchedRules: matchedReplaceRules)
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepScreenOn }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: keepScreenOn) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
    }

    private func goTo(_ index: Int) {
        guard book.chapters.indices.contains(index) else { return }
        currentIndex = index
    }

    private func load() async {
        let replaceRules = (try? await env.replaceRuleStore.enabled()) ?? []
        let purified = ReplaceRuleApplier.applyReportingMatches(replaceRules, to: chapter.text, sourceUrl: "")
        purifiedText = purified.result
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

                Section("其他") {
                    Toggle("阅读时屏幕常亮", isOn: $keepScreenOn)
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
