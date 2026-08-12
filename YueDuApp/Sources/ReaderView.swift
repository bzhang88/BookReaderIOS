import SwiftUI
import UIKit
import BookSourceModel
import WebBookOrchestrator
import Persistence
import RuleEngine

/// Reports each *page* block's top edge position (in the `"readerScroll"` named coordinate space)
/// as it renders/moves -- used to figure out which page is currently at the top of the visible
/// screen, the basis for real reading-position tracking (see `ReaderView.currentPageIndexInChapter`).
/// Page-granular, not paragraph-granular -- confirmed against Legado_Max's real source
/// (`TextChapterLayout`/`ChapterProvider`) that `.scroll` mode there is built on the exact same
/// screen-measured page splitting as its non-scroll paginated modes, just drawn stacked instead of
/// one-at-a-time; this reader's own `.scroll` mode used to be a raw continuous-paragraph flow with
/// no page concept at all, which is what real usage feedback (with a reference screenshot showing a
/// real "10/10" page-in-chapter indicator) asked to be corrected.
private struct PageTopOffsetKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Fully fetched-and-purified next-chapter content, ready to display immediately (see
/// `ReaderView.nextChapterPreview`'s doc comment) or promote straight to "current" with no further
/// network/purification work needed. `pageLayout` is filled in once pagination (which needs the
/// measured screen size) has actually run against `text` -- may briefly be `nil` right after the
/// text itself arrives.
private struct NextChapterPreview {
    let index: Int
    let title: String
    let text: String
    let matchedRules: [ReplaceRule]
    var pageLayout: ChapterPageLayout?
}

struct ReaderView: View {
    // These start as constructor params but can change in place when the user switches source
    // mid-read (see `switchSource`) -- kept as @State rather than the `let`s this started as so the
    // reader itself can adopt a new source/book/chapter-list without popping back and re-pushing a
    // whole new ReaderView (which would need a shared NavigationPath this view doesn't have access
    // to, given how deeply it's already nested under Shelf/Toc navigation).
    @State private var source: BookSource
    @State private var bookUrl: String
    @State private var tocUrl: String
    @State private var chapters: [BookChapter]
    @State private var bookTitle: String
    @State private var currentIndex: Int

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingStyleSheet = false
    @State private var isShowingMoreSettings = false
    @State private var isSettingsPanelVisible = false
    @State private var isShowingTapZoneConfig = false
    @State private var isShowingChangeSource = false
    @State private var isShowingChapterSourceSwitch = false
    @State private var isShowingToc = false
    @State private var isShowingContentSearch = false
    @State private var isShowingAISummary = false
    @State private var isShowingDictLookup = false
    @State private var isShowingContentEdit = false
    @State private var isShowingWebSearch = false
    @State private var isShowingReplaceRules = false
    @State private var isChromeVisible = true
    // Brightness is a toggleable quick-access row (tap the "亮度" icon to reveal/hide it), not a
    // permanently-visible slider -- matches the reference reading app the user pointed at directly
    // (a slider taking up a full row at all times, whether or not anyone's about to touch it, was
    // part of what made the previous chrome feel cluttered).
    @State private var isBrightnessVisible = false
    // Guards auto-advance so a chapter that's short enough to fit on screen without scrolling
    // doesn't fire the moment it loads (the bottom sentinel would already be within the visible
    // scroll bounds from the very first layout pass, before the user has read anything) -- reset
    // to false on every chapter change, flips true after a short grace period.
    @State private var canAutoAdvance = false
    @State private var isCurrentChapterBookmarked = false
    @State private var matchedReplaceRules: [ReplaceRule] = []
    @State private var screenBrightness: Double = Double(UIScreen.main.brightness)
    @State private var highlightRules: [HighlightRule] = []
    @State private var isAutoScrolling = false
    @State private var autoScrollTask: Task<Void, Never>?
    @StateObject private var readAloud = ReadAloudController()
    @StateObject private var httpReadAloud = HttpReadAloudController()
    @State private var httpTTSEngines: [HttpTTSEngine] = []
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(ReaderSettingsKey.fontSize) private var fontSize: Double = 18
    @AppStorage(ReaderSettingsKey.lineSpacing) private var lineSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.paragraphSpacing) private var paragraphSpacing: Double = 8
    @AppStorage(ReaderSettingsKey.theme) private var theme: ReaderTheme = .day
    @AppStorage(ReaderSettingsKey.keepScreenOn) private var keepScreenOn: Bool = true
    @AppStorage(ReaderSettingsKey.readAloudRate) private var readAloudRate: Double = 0.5
    @AppStorage(ReaderSettingsKey.chineseConversion) private var chineseConversion: ChineseConversionMode = .off
    @AppStorage(ReaderSettingsKey.autoScrollInterval) private var autoScrollInterval: Double = 3.0
    @AppStorage(ReaderSettingsKey.tapZoneGrid) private var tapZoneGridRaw: String = ReaderTapZoneGrid.standardEncoded
    @AppStorage(ReaderSettingsKey.volumeKeyPage) private var volumeKeyPageEnabled: Bool = false
    @State private var volumeButtonController = VolumeButtonPageTurnController()
    // Not real character/pixel scroll position -- a simple step counter over paragraph indices,
    // same "honest approximation" the auto-scroll feature already uses (see its own doc comment).
    // Resets to 0 on every chapter change.
    @State private var volumeScrollIndex = 0
    @AppStorage(ReaderSettingsKey.eyeCareEnabled) private var eyeCareEnabled: Bool = false
    @AppStorage(ReaderSettingsKey.eyeCareIntensity) private var eyeCareIntensity: Double = 0.35
    @AppStorage(ReaderSettingsKey.eyeCareScheduleEnabled) private var eyeCareScheduleEnabled: Bool = false
    @AppStorage(ReaderSettingsKey.eyeCareScheduleStartHour) private var eyeCareScheduleStartHour: Int = 20
    @AppStorage(ReaderSettingsKey.eyeCareScheduleEndHour) private var eyeCareScheduleEndHour: Int = 6
    @AppStorage(ReaderSettingsKey.touchSlop) private var touchSlop: Double = 50
    @AppStorage(ReaderSettingsKey.selectedHttpTTSEngineID) private var selectedHttpTTSEngineID: String = ""
    @AppStorage(ReaderSettingsKey.customThemeBackgroundHex) private var customThemeBackgroundHex: String = "#FFFFFF"
    @AppStorage(ReaderSettingsKey.customThemeTextHex) private var customThemeTextHex: String = "#0D0D0D"
    @AppStorage(ReaderSettingsKey.pageTurnStyle) private var pageTurnStyle: PageTurnStyle = .scroll
    @AppStorage(ReaderSettingsKey.prefetchChapterCount) private var prefetchChapterCount: Int = 1
    // Only ever set to `.last` right before `goTo` steps backward across a paginated chapter's
    // boundary (see `goTo`'s doc comment) -- every other navigation path defaults back to `.first`.
    @State private var pageAnchor: PageAnchor = .first
    @State private var pageTurnRequest: PageTurnRequest?
    @State private var pageJumpRequest: Int?
    @State private var pagedPageProgress: (current: Int, total: Int)?
    // Local override while the user is actively dragging the progress seekbar -- lets the slider
    // show the finger's live position instead of snapping back to the real page on every tiny
    // movement; cleared (reverting to tracking `pagedPageProgress` again) once the drag ends and
    // `pageJumpRequest` has been sent.
    @State private var pageSeekDragValue: Double?
    @State private var isAutoPaging = false
    @State private var autoPageTask: Task<Void, Never>?
    // Re-evaluated every minute so a schedule-only filter actually turns on/off while the reader
    // stays open across the boundary, not just whenever the view happens to redraw for other reasons.
    @State private var scheduleTick = Date()
    private let scheduleTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    /// Set from `init`'s `resumeCharacterOffset` when opening a book that was left mid-chapter;
    /// consumed (scrolled-to, then cleared) the first time `repaginateForScroll` runs against this
    /// chapter's real (non-empty) text -- converting a saved character offset into a scroll target
    /// needs the actual page layout, which only exists once pagination has run. Only meaningful in
    /// `.scroll` mode -- see `currentPageIndexInChapter`'s doc comment for why paginated mode doesn't
    /// track this.
    @State private var pendingResumeCharacterOffset: Int?
    /// Which page is currently at (or nearest) the top of the visible screen in `.scroll` mode --
    /// tracked continuously via `PageTopOffsetKey` below purely in memory (cheap), but only
    /// *persisted* to `ShelfStore` periodically (`scheduleTimer`) and on `.onDisappear` (see those
    /// handlers), not on every scroll frame, since writing to disk that often would be wasteful.
    /// Scoped to `.scroll` mode only -- `PagedChapterReaderView` already tracks its own page position
    /// independently for the 4 paginated styles.
    @State private var currentPageIndexInChapter = 0
    /// Real, screen-measured pagination of the *current* chapter's `text` -- confirmed against
    /// Legado_Max's real source that `.scroll` mode there is built on the same page-splitting engine
    /// as its non-scroll paginated modes (not a raw continuous-text flow), which is what real usage
    /// feedback asked this reader to match (down to the bottom-left "page N/M in this chapter"
    /// indicator a real screenshot showed). Reuses `ChapterPaginator`/`ChapterPageLayout`, the exact
    /// same already-shipped, already-tested machinery `PagedChapterReaderView` uses for its own 4
    /// paginated styles -- not a second, separately-risked pagination implementation.
    @State private var pageLayout: ChapterPageLayout?
    /// Just the *text* pagination last ran against (not the fuller key `.task(id:)` uses, which also
    /// includes font/spacing/size) -- lets `repaginateForScroll` tell "the chapter changed" (reset
    /// `currentPageIndexInChapter` to 0) apart from "only a reading-settings slider changed, same
    /// chapter" (try to stay on roughly the same page instead of jumping back to page 1 every time).
    /// Mirrors `PagedChapterReaderView.lastPaginatedText` exactly, including comparing on text alone.
    @State private var lastPaginatedScrollText: String?
    /// The measured on-screen content area (screen size minus this reader's page margins) --
    /// `ChapterPaginator` needs this to know how much text fits one "page." Stored as `@State`
    /// (rather than only known inside the `GeometryReader` closure) because `loadNextChapterPreview`
    /// needs it too, from outside `body`.
    @State private var scrollPageSize: CGSize = .zero
    /// The next chapter's content, already fetched *and* purified (replace rules + Chinese
    /// conversion already applied, exactly like `text` itself), appended visually below the current
    /// chapter's own paragraphs -- see the rendering code in `body` and `commitToNextChapterPreview`
    /// for the full picture. Real usage feedback pointed at a reference app (screenshot: chapter 3's
    /// ending, a gap, then chapter 4's title as a heading, then chapter 4's own text -- all in one
    /// continuous scroll) where chapters visually flow into each other instead of this reader's
    /// previous behavior (hit the bottom -> the whole screen reloads to a blank top).
    @State private var nextChapterPreview: NextChapterPreview?
    /// Set right before a seamless preview-commit changes `currentIndex` -- consumed by `load()` (see
    /// its own doc comment) so `.task(id:)` firing from that same `currentIndex` change doesn't
    /// redundantly re-fetch content that's already sitting on screen, which would also flash the
    /// loading spinner over it.
    @State private var justCommittedFromPreview = false
    /// Same idea as `justCommittedFromPreview` but for `.onChange(of: currentIndex)`'s scroll-to-top
    /// reset (see item 6's fix there) -- a seamless commit must *not* jump the scroll position, since
    /// nothing about what's on screen actually changed, only which paragraphs count as "current."
    /// Kept as its own separate flag rather than reusing `justCommittedFromPreview` because there's no
    /// guaranteed ordering between `.task(id:)` and `.onChange(of:)` both firing off the same
    /// `currentIndex` mutation -- two independent one-shot flags avoid depending on that ordering.
    @State private var suppressScrollResetOnNextChapterChange = false

    @AppStorage(ReaderSettingsKey.pageMarginTop) private var pageMarginTop: Double = 16
    @AppStorage(ReaderSettingsKey.pageMarginBottom) private var pageMarginBottom: Double = 16
    @AppStorage(ReaderSettingsKey.pageMarginLeading) private var pageMarginLeading: Double = 16
    @AppStorage(ReaderSettingsKey.pageMarginTrailing) private var pageMarginTrailing: Double = 16
    @AppStorage(ReaderSettingsKey.paragraphIndent) private var paragraphIndent: Int = 2

    private var isEyeCareActive: Bool {
        eyeCareEnabled || (eyeCareScheduleEnabled && EyeCareSchedule.isActive(
            startHour: eyeCareScheduleStartHour, endHour: eyeCareScheduleEndHour, now: scheduleTick
        ))
    }

    /// `resumeCharacterOffset` -- real usage feedback: reopening a book from the shelf always
    /// landed at the *start* of the last-read chapter, never the exact spot the user actually
    /// stopped at, even though `ShelfBook.lastReadCharacterOffset` already existed as a field --
    /// nothing ever wrote a real value into it (every call site hardcoded `characterOffset: 0`) or
    /// read it back on resume. This is that missing other half, threaded in from whichever call
    /// site knows the book's saved position (see `BookOpenerView`).
    init(
        source: BookSource, bookUrl: String, tocUrl: String, chapters: [BookChapter], currentIndex: Int,
        bookTitle: String, resumeCharacterOffset: Int = 0
    ) {
        self._source = State(initialValue: source)
        self._bookUrl = State(initialValue: bookUrl)
        self._tocUrl = State(initialValue: tocUrl)
        self._chapters = State(initialValue: chapters)
        self._bookTitle = State(initialValue: bookTitle)
        self._currentIndex = State(initialValue: currentIndex)
        self._pendingResumeCharacterOffset = State(initialValue: resumeCharacterOffset > 0 ? resumeCharacterOffset : nil)
    }

    private var chapter: BookChapter { chapters[currentIndex] }
    private var paragraphs: [String] { text.components(separatedBy: "\n") }

    private var chapterProgressText: String {
        let chapterPart = "第 \(currentIndex + 1) / \(chapters.count) 章"
        guard pageTurnStyle.isPaginated, let pagedPageProgress else { return chapterPart }
        return "\(chapterPart) · 第 \(pagedPageProgress.current) / \(pagedPageProgress.total) 页"
    }

    /// Drives the paginated-mode progress seekbar -- while a drag is in flight, shows the finger's
    /// live position (`pageSeekDragValue`) instead of the real current page, so the slider doesn't
    /// fight the user's touch; reverts to tracking `pagedPageProgress` once the drag ends and the
    /// actual jump (`pageJumpRequest`) has been sent. Matches Legado's real "page" progress-bar
    /// mode: jump immediately on release, no confirmation (confirmed via `ReadMenu.kt` research).
    private var pageSeekBinding: Binding<Double> {
        Binding(
            get: { pageSeekDragValue ?? Double((pagedPageProgress?.current ?? 1) - 1) },
            set: { pageSeekDragValue = $0 }
        )
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
        Group {
            if pageTurnStyle.isPaginated {
                PagedChapterReaderView(
                    text: text,
                    style: pageTurnStyle,
                    fontSize: fontSize,
                    lineSpacing: lineSpacing,
                    paragraphSpacing: paragraphSpacing,
                    textColor: theme.textColor(for: colorScheme, customText: Color(hex: customThemeTextHex)),
                    backgroundColor: theme.backgroundColor(for: colorScheme, customBackground: Color(hex: customThemeBackgroundHex)),
                    highlightRules: highlightRules,
                    readAloudParagraphIndex: isReadAloudSpeaking ? readAloudCurrentParagraphIndex : nil,
                    initialAnchor: pageAnchor,
                    pageTurnRequest: $pageTurnRequest,
                    pageJumpRequest: $pageJumpRequest,
                    touchSlop: touchSlop,
                    onTapMiddle: { isChromeVisible.toggle() },
                    onRequestPreviousChapter: { goTo(currentIndex - 1, anchor: .last) },
                    onRequestNextChapter: { goTo(currentIndex + 1) },
                    onPageChanged: { current, total in pagedPageProgress = (current, total) }
                )
            } else {
                scrollModeBody(scrollProxy: scrollProxy)
            }
        }
        .background(theme.backgroundColor(for: colorScheme, customBackground: Color(hex: customThemeBackgroundHex)))
        .overlay {
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            }
        }
        // A warm, hit-testing-disabled tint layered on top of whichever theme is active -- eye
        // care is a filter you can combine with any theme, not a theme choice of its own.
        .overlay {
            if isEyeCareActive {
                Color(red: 1, green: 0.65, blue: 0.2)
                    .opacity(eyeCareIntensity * 0.35)
                    .allowsHitTesting(false)
            }
        }
        // Floating quick-access read-aloud button -- matches the reference reading app's own
        // small circular "听" button, sitting just above the bottom bar rather than making 朗读
        // compete for one of the 4 primary bottom-row icon slots. Only shown alongside the rest of
        // the chrome (not in the fully-hidden minimal-footer state) and hidden while already
        // speaking, since the read-aloud controls row already covers play/pause/stop then.
        .overlay(alignment: .bottomTrailing) {
            if isChromeVisible && !isReadAloudSpeaking {
                Button {
                    startOrStopReadAloud()
                } label: {
                    Image(systemName: "headphones")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Color.accentColor, in: Circle())
                        .shadow(radius: 3, y: 1)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 8)
            }
        }
        .onReceive(scheduleTimer) { scheduleTick = $0; saveReadingProgress() }
        // `.overlay`, not `.safeAreaInset` -- real usage feedback: opening/closing the menu was
        // visibly shifting where the text sat on screen, because `.safeAreaInset` *reserves* space
        // for its content, shrinking the reading area (and reflowing every line in it) every time
        // the menu toggled. An overlay draws on top of the reading area without changing its size at
        // all -- the menu can cover the last few lines of text while it's open, which is fine, but
        // the lines that stay visible never move. Paired with the matching `.overlay(alignment:
        // .top)` fix above for the same reason on the top bar.
        .overlay(alignment: .bottom) {
            if isChromeVisible {
                VStack(spacing: 10) {
                    // Toggled by the "亮度" icon below, not shown permanently -- matches the
                    // reference reading app the user pointed at directly (a screenshot of its menu
                    // has no always-on brightness row; brightness is one of the 4 primary icons and
                    // only reveals a slider on demand).
                    if isBrightnessVisible {
                        HStack(spacing: 12) {
                            Image(systemName: "sun.min")
                            Slider(value: $screenBrightness, in: 0...1)
                                .onChange(of: screenBrightness) { _, newValue in
                                    UIScreen.main.brightness = CGFloat(newValue)
                                }
                            Image(systemName: "sun.max")
                        }
                    }

                    if isReadAloudSpeaking {
                        HStack(spacing: 20) {
                            Button {
                                readAloudPreviousParagraph()
                            } label: {
                                Image(systemName: "backward.end")
                            }
                            Button {
                                toggleReadAloudPause()
                            } label: {
                                Image(systemName: isReadAloudPaused ? "play.fill" : "pause.fill")
                            }
                            Button {
                                readAloudNextParagraph()
                            } label: {
                                Image(systemName: "forward.end")
                            }
                            Button(role: .destructive) {
                                stopReadAloud()
                            } label: {
                                Image(systemName: "stop.fill")
                            }
                        }
                        .font(.title3)
                    }

                    // Chapter-progress row -- prev/next chapter text flanking a real draggable
                    // seekbar in paginated mode, matching the reference app's own prominent
                    // progress bar in this exact position (jumps immediately on release, no
                    // confirmation). `.scroll` mode has no equivalent accurate position to seek
                    // (there's nowhere this reader tracks *real* scroll offset, only the step-wise
                    // `volumeScrollIndex` approximation used elsewhere) -- showing a seekbar there
                    // would risk being actively misleading rather than just plain, so it stays as
                    // text-only progress for that mode.
                    HStack(spacing: 4) {
                        // `.padding` + `.contentShape(Rectangle())` so the tappable area is a real
                        // ~44pt-tall button, not just the tiny `.caption`-sized text glyphs -- same
                        // "too small to reliably tap" feedback as the top bar's icons.
                        Button("上一章") { goTo(currentIndex - 1) }
                            .font(.caption)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                            .disabled(currentIndex <= 0)

                        if pageTurnStyle.isPaginated, let pagedPageProgress, pagedPageProgress.total > 1 {
                            Slider(
                                value: pageSeekBinding, in: 0...Double(pagedPageProgress.total - 1), step: 1,
                                onEditingChanged: { isEditing in
                                    if !isEditing {
                                        if let pageSeekDragValue { pageJumpRequest = Int(pageSeekDragValue) }
                                        pageSeekDragValue = nil
                                    }
                                }
                            )
                        } else {
                            Text(chapterProgressText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }

                        Button("下一章") { goTo(currentIndex + 1) }
                            .font(.caption)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                            .disabled(currentIndex >= chapters.count - 1)
                    }

                    // Inline expanding panel -- toggled by the "设置" icon just below, in place of
                    // that icon opening `ReaderMoreSettingsSheet` directly. Real usage feedback
                    // pointed at a reference reading app whose "设置" doesn't cover the screen with a
                    // modal at all: the page itself grows a quick-controls panel right above the
                    // primary icon row (theme swatches, font-size/line-spacing steppers, then 4
                    // shortcuts), and only "更多" underneath that reaches the deeper, less-frequently
                    // -touched settings (语速/简繁转换/护眼/触控灵敏度/净化规则报告) that still live
                    // in the full `ReaderMoreSettingsSheet`.
                    if isSettingsPanelVisible {
                        inlineSettingsPanel(proxy: scrollProxy)
                    }

                    // Bottom-most primary-function row -- matches the reference reading app's own
                    // 4-icon row exactly (目录/亮度/深色/设置), not Legado_Max's stock 目录/朗读/
                    // 界面/设置: the user pointed at a real screenshot of the app they like using,
                    // which weighs more than what the Legado source code documents. 朗读 gets its
                    // own floating quick button instead (see `body`'s `.overlay`, matching that same
                    // reference screenshot's floating "听" button); 界面 now opens from inside
                    // "设置" (its first row) instead of claiming a 5th icon slot; 搜索本书内 and
                    // 自动翻页/自动滚动 moved into the top bar's "…" overflow to keep this row to
                    // exactly the 4 the reference shows.
                    HStack {
                        bottomFunctionButton(icon: "list.bullet", label: "目录") {
                            isShowingToc = true
                        }
                        Spacer()
                        bottomFunctionButton(icon: isBrightnessVisible ? "sun.max.fill" : "sun.max", label: "亮度") {
                            isBrightnessVisible.toggle()
                        }
                        Spacer()
                        bottomFunctionButton(icon: theme == .night ? "moon.fill" : "moon", label: "深色") {
                            theme = theme == .night ? .day : .night
                        }
                        Spacer()
                        bottomFunctionButton(icon: "gearshape", label: "设置") {
                            isSettingsPanelVisible.toggle()
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.bar)
            } else {
                // A slim, always-on footer (chapter title/progress) even while the rest of the
                // chrome is hidden -- confirmed against Legado_Max's real `ReadView`/`PageView`
                // that its reading screen is never truly blank by default: a low-contrast footer
                // with chapter name + page count stays up regardless of menu state, and only the
                // *menu* (brightness/buttons/settings) is fully absent until tapped. Previously
                // this reader dropped the progress text entirely the moment chrome was hidden, so
                // there was no way to glance at "where am I" without reopening the whole menu.
                Text(chapterProgressText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        // Permanently hidden (not conditional on `isChromeVisible`) -- a custom `.overlay(alignment:
        // .top)` below draws the same buttons instead. Toggling the *native* bar's visibility was
        // the other half of the "menu open/closed changes where the safe area starts, so the text
        // itself visibly shifts" bug real usage feedback flagged (`.safeAreaInset` on the bottom was
        // the other half, fixed the same way just below): showing/hiding a real navigation bar
        // changes how much vertical space is reserved above the content, which is exactly the kind
        // of layout-affecting toggle that has to go if the reading area's size is to stay constant
        // regardless of chrome state. An overlay draws on top without reserving any space at all.
        .toolbar(.hidden, for: .navigationBar)
        // The reader is meant to take over the whole screen -- real usage feedback was that the
        // main app's 书架/发现/订阅/我的 tab bar was still visible at the bottom while reading,
        // underneath (and confusingly separate from) this reader's own bottom chrome. Pushing a
        // view via `NavigationLink` inside a `TabView`'s tab keeps the tab bar showing by default
        // unless a pushed view explicitly hides it, which nothing in this app did before.
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .top) {
            if isChromeVisible {
                HStack(spacing: 8) {
                    // Real usage feedback: these top-bar icons were too small to reliably tap --
                    // only the bare SF Symbol glyph itself was tappable (maybe 20pt), well under
                    // Apple's own 44x44pt minimum touch-target guidance. `.frame(width: 44, height:
                    // 44).contentShape(Rectangle())` on every icon here (and the bottom bar's) makes
                    // the whole 44x44 square tappable, not just the visible glyph inside it.
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    Text(chapter.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Menu {
                        Button {
                            isShowingChangeSource = true
                        } label: {
                            Label("换源（整本书）", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button {
                            isShowingChapterSourceSwitch = true
                        } label: {
                            Label("本章换源", systemImage: "doc.badge.arrow.up")
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    Menu {
                        Button {
                            Task { await toggleBookmark() }
                        } label: {
                            Label(
                                isCurrentChapterBookmarked ? "移除书签" : "加入书签",
                                systemImage: isCurrentChapterBookmarked ? "bookmark.fill" : "bookmark"
                            )
                        }
                        Button {
                            isShowingContentEdit = true
                        } label: {
                            Label("编辑正文", systemImage: "pencil")
                        }
                        Button {
                            isShowingContentSearch = true
                        } label: {
                            Label("搜索本书内", systemImage: "magnifyingglass")
                        }
                        Button {
                            isShowingReplaceRules = true
                        } label: {
                            Label("替换净化", systemImage: "wand.and.stars")
                        }
                        Button {
                            if pageTurnStyle.isPaginated {
                                toggleAutoPage()
                            } else {
                                toggleAutoScroll(proxy: scrollProxy)
                            }
                        } label: {
                            let isRunning = pageTurnStyle.isPaginated ? isAutoPaging : isAutoScrolling
                            Label(
                                isRunning ? "停止自动翻页" : "自动翻页",
                                systemImage: isRunning ? "pause.circle" : "play.circle"
                            )
                        }
                        Button {
                            isShowingAISummary = true
                        } label: {
                            Label("AI 摘要", systemImage: "sparkles")
                        }
                        Button {
                            isShowingDictLookup = true
                        } label: {
                            Label("查词", systemImage: "character.book.closed")
                        }
                        Button {
                            isShowingWebSearch = true
                        } label: {
                            Label("网页搜索", systemImage: "globe")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(.bar)
            } else {
                // Matches the reference reading app's chrome-hidden state: a slim chapter-name
                // readout stays up top even with the rest of the menu gone (paired with the
                // symmetric bottom-edge footer below).
                HStack {
                    Text(chapter.title)
                        .lineLimit(1)
                    Spacer()
                    Text(bookTitle)
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isChromeVisible)
        // Keyed on source+index (not just index) so switching source always triggers a reload even
        // on the rare occasion the new chapter index happens to numerically match the old one --
        // `.task(id:)` only refires when its id value actually changes.
        .task(id: "\(source.bookSourceUrl)#\(currentIndex)") { await load() }
        .task { httpTTSEngines = (try? await env.httpTTSEngineStore.all()) ?? [] }
        .sheet(isPresented: $isShowingStyleSheet) {
            ReaderStyleSheet()
        }
        .sheet(isPresented: $isShowingMoreSettings) {
            ReaderMoreSettingsSheet()
        }
        .sheet(isPresented: $isShowingTapZoneConfig) {
            NavigationStack {
                TapZoneConfigView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { isShowingTapZoneConfig = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $isShowingReplaceRules) {
            NavigationStack {
                ReplaceRuleListView()
            }
        }
        .sheet(isPresented: $isShowingChangeSource) {
            NavigationStack {
                ChangeSourceView(
                    currentBookSourceUrl: source.bookSourceUrl, bookName: bookTitle, bookAuthor: nil
                ) { newSource, match in
                    await switchSource(to: newSource, match: match)
                }
            }
        }
        .sheet(isPresented: $isShowingChapterSourceSwitch) {
            NavigationStack {
                ChangeSourceView(
                    currentBookSourceUrl: source.bookSourceUrl, bookName: bookTitle, bookAuthor: nil
                ) { newSource, match in
                    await switchChapterSource(to: newSource, match: match)
                }
            }
        }
        .overlay {
            ReaderTocDrawerView(
                isPresented: $isShowingToc,
                chapters: chapters.map { ReaderTocDrawerView.ChapterItem(id: $0.index, title: $0.title) },
                currentIndex: currentIndex,
                bookIdentifier: bookUrl,
                bookmarkStore: env.bookmarkStore,
                matchedReplaceRules: matchedReplaceRules,
                searchScopeNotice: "仅搜索已下载缓存的章节，未下载的章节不在搜索范围内",
                loadChaptersForSearch: loadCachedChaptersForSearch,
                onSelectChapter: { index in goTo(index) }
            )
        }
        .sheet(isPresented: $isShowingContentSearch) {
            ChapterContentSearchView(
                loadChapters: { await loadCachedChaptersForSearch() },
                onSelect: { index in goTo(index) },
                scopeNotice: "仅搜索已下载缓存的章节，未下载的章节不在搜索范围内"
            )
        }
        .sheet(isPresented: $isShowingAISummary) {
            AIChapterSummaryView(chapterTitle: chapter.title, chapterText: text)
        }
        .sheet(isPresented: $isShowingDictLookup) {
            DictLookupView()
        }
        .sheet(isPresented: $isShowingContentEdit) {
            ChapterEditView(source: source, chapter: chapter, bookUrl: bookUrl, currentText: text) { edited in
                text = edited
            }
        }
        .sheet(isPresented: $isShowingWebSearch) {
            WebSearchPanelView()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepScreenOn
            startVolumeButtonPagingIfEnabled(proxy: scrollProxy)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            stopReadAloud()
            stopAutoScroll()
            stopAutoPage()
            volumeButtonController.stop()
            saveReadingProgress()
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
            stopReadAloud()
            // Same reasoning as read-aloud: an auto-scroll loop mid-flight is walking paragraph
            // indices that belonged to the chapter that just got replaced, so it has to stop too
            // rather than silently continuing to scroll a chapter that no longer matches its state.
            stopAutoScroll()
            volumeScrollIndex = 0
            pagedPageProgress = nil
            // Real usage feedback: tapping "下一章"/"上一章" landed at the *same scroll offset* as
            // before instead of the top of the new chapter -- `ScrollView` preserves its raw pixel
            // scroll offset across a content swap; it has no idea "chapter changed" should mean
            // "start over at the top." Calling this now (against what's still the *old* chapter's
            // paragraph 0, since `load()` for the new chapter hasn't run yet) still works: a
            // `ScrollView`'s position is a raw offset, not tied to which content is showing, so
            // resetting that offset to 0 now is what actually lands at the top once the new
            // chapter's content swaps in a moment later, without needing to wait for `load()` and
            // add a second asynchronous scroll step.
            // A seamless preview-commit (see `commitToNextChapterPreview`) must *not* jump the scroll
            // position -- nothing about what's on screen actually changed, only which paragraphs
            // count as "current." Skipping this only for that one path (not paginated mode's own
            // separate anchor system) is exactly what `suppressScrollResetOnNextChapterChange` is for.
            if suppressScrollResetOnNextChapterChange {
                suppressScrollResetOnNextChapterChange = false
            } else if !pageTurnStyle.isPaginated {
                withAnimation(nil) {
                    // -1 is the chapter heading's id (see `chapterHeading`'s call site), not
                    // paragraph 0 -- landing on a new chapter should show its title too, not leave
                    // it scrolled just out of view above the first paragraph.
                    scrollProxy.scrollTo(-1, anchor: .top)
                }
            }
        }
        }
    }

    /// Volume Up steps back, Volume Down steps forward -- Legado's own convention wasn't confirmed
    /// during research (its volume-key handling just maps to the same "previous/next" actions a
    /// paginated reader already has, without a documented up/down convention to match exactly), so
    /// this picked the mapping that reads as intuitive for a reading gesture (down = further into
    /// the content) rather than copying an unverified assumption.
    private func startVolumeButtonPagingIfEnabled(proxy: ScrollViewProxy) {
        guard volumeKeyPageEnabled else { return }
        guard let window = Self.keyWindow() else { return }
        volumeButtonController.onVolumeUp = { handleVolumeKeyTurn(direction: -1, proxy: proxy) }
        volumeButtonController.onVolumeDown = { handleVolumeKeyTurn(direction: 1, proxy: proxy) }
        volumeButtonController.start(in: window)
    }

    private func handleVolumeKeyTurn(direction: Int, proxy: ScrollViewProxy) {
        guard !pageTurnStyle.isPaginated else {
            pageTurnRequest = direction > 0 ? .next : .previous
            return
        }
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

    /// `anchor` only matters in paginated mode (see `PagedChapterReaderView`'s doc comment) --
    /// `.last` is for the one case where continuing to page backward past a chapter's first page
    /// should land on the new chapter's *last* page, matching where a physical book would be;
    /// every other caller (explicit chapter-list/search/bookmark jumps, the toolbar's 上一章/下一章
    /// buttons, paging forward across a boundary) wants the default `.first`.
    private func goTo(_ index: Int, anchor: PageAnchor = .first) {
        guard chapters.indices.contains(index) else { return }
        // An explicit jump (buttons/TOC/search/bookmark) invalidates whatever was queued as "the
        // next chapter after wherever I currently am" -- if it's stale, `loadNextChapterPreview`
        // (called again at the end of the resulting `load()`) fetches the right one for the new
        // position instead.
        nextChapterPreview = nil
        pageAnchor = anchor
        currentIndex = index
    }

    // MARK: - Read-aloud routing
    //
    // Two independent controllers exist (`readAloud` wraps AVSpeechSynthesizer, `httpReadAloud`
    // fetches audio from a configured HttpTTSEngine) rather than one shared abstraction -- see
    // `HttpReadAloudController`'s doc comment for why. `selectedHttpTTSEngineID` (empty = system
    // voice) picks which one is "active"; these helpers are the single place that branches on it,
    // so the rest of the view just calls e.g. `stopReadAloud()` without needing to know which
    // underlying controller is actually running.

    private var isUsingHttpTTS: Bool { !selectedHttpTTSEngineID.isEmpty }
    private var isReadAloudSpeaking: Bool { isUsingHttpTTS ? httpReadAloud.isSpeaking : readAloud.isSpeaking }
    private var isReadAloudPaused: Bool { isUsingHttpTTS ? httpReadAloud.isPaused : readAloud.isPaused }
    private var readAloudCurrentParagraphIndex: Int {
        isUsingHttpTTS ? httpReadAloud.currentParagraphIndex : readAloud.currentParagraphIndex
    }

    private func startOrStopReadAloud() {
        if isReadAloudSpeaking {
            stopReadAloud()
        } else if isUsingHttpTTS, let engine = httpTTSEngines.first(where: { $0.id == selectedHttpTTSEngineID }) {
            httpReadAloud.start(
                paragraphs: paragraphs, engine: engine, cache: env.httpTTSCache,
                bookTitle: bookTitle, chapterTitle: chapter.title
            )
        } else {
            readAloud.setRate(Float(readAloudRate))
            readAloud.start(paragraphs: paragraphs, bookTitle: bookTitle, chapterTitle: chapter.title)
        }
    }

    private func stopReadAloud() {
        readAloud.stop()
        httpReadAloud.stop()
    }

    private func toggleReadAloudPause() {
        if isUsingHttpTTS { httpReadAloud.togglePause() } else { readAloud.togglePause() }
    }

    private func readAloudPreviousParagraph() {
        if isUsingHttpTTS { httpReadAloud.previousParagraph() } else { readAloud.previousParagraph() }
    }

    private func readAloudNextParagraph() {
        if isUsingHttpTTS { httpReadAloud.nextParagraph() } else { readAloud.nextParagraph() }
    }

    /// Icon-over-label button matching Legado's real bottom-most row style (`ll_catalog` etc. in
    /// `view_read_menu.xml` are icon+text, not bare icons) -- a plain icon-only button doesn't say
    /// what it does until you've already memorized it, which was part of what made the previous
    /// all-icon utility row hard to use at a glance.
    @ViewBuilder
    private func bottomFunctionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption2)
            }
            // Same "too small to tap" fix as the top bar -- the icon+label VStack's own natural
            // bounds were the entire touch target before this, well under a comfortable tap size.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
    }

    /// Quick-access controls shown above the primary icon row when "设置" is tapped -- see the call
    /// site's doc comment for why this replaced opening `ReaderMoreSettingsSheet` directly. The 4
    /// shortcuts at the bottom route into whichever existing sheet/action already owns that setting
    /// rather than reimplementing it a second time inline (自动阅读 toggles the same auto-scroll/
    /// auto-page state the old overflow menu item did; 翻页动画 and 更多 just open `ReaderStyleSheet`
    /// /`ReaderMoreSettingsSheet` a click sooner than before).
    private func inlineSettingsPanel(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSwatchPicker(theme: $theme)

            HStack {
                Text("字号").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Stepper(value: $fontSize, in: 12...32, step: 1) {
                    Text("\(Int(fontSize))").font(.caption).monospacedDigit().frame(minWidth: 20)
                }
                .fixedSize()
            }
            HStack {
                Text("行距").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Stepper(value: $lineSpacing, in: 0...24, step: 1) {
                    Text("\(Int(lineSpacing))").font(.caption).monospacedDigit().frame(minWidth: 20)
                }
                .fixedSize()
            }
            // Real usage feedback: the inline panel had 字号/行距 quick steppers but not 段距,
            // even though the full "界面" sheet always had all three -- an easy thing to miss if
            // you never happened to open "更多"/"翻页动画" to find the full sheet underneath.
            HStack {
                Text("段距").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Stepper(value: $paragraphSpacing, in: 0...32, step: 1) {
                    Text("\(Int(paragraphSpacing))").font(.caption).monospacedDigit().frame(minWidth: 20)
                }
                .fixedSize()
            }

            Divider()

            HStack {
                settingsQuickLink(icon: pageTurnStyle.isPaginated ? (isAutoPaging ? "pause.circle" : "play.circle") : (isAutoScrolling ? "pause.circle" : "play.circle"), label: "自动阅读") {
                    if pageTurnStyle.isPaginated {
                        toggleAutoPage()
                    } else {
                        toggleAutoScroll(proxy: proxy)
                    }
                }
                Spacer()
                settingsQuickLink(icon: "square.grid.3x3", label: "点击区域") {
                    isShowingTapZoneConfig = true
                }
                Spacer()
                settingsQuickLink(icon: "rectangle.on.rectangle", label: "翻页动画") {
                    isShowingStyleSheet = true
                }
                Spacer()
                settingsQuickLink(icon: "ellipsis", label: "更多") {
                    isShowingMoreSettings = true
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    private func settingsQuickLink(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.body)
                Text(label).font(.caption2)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
    }

    /// Resolves a raw tap location to one of the 3x3 zones and runs whatever action the user has
    /// configured for it (default: side columns turn chapters, middle column toggles chrome --
    /// see `ReaderTapZoneGrid.standard`). Zones are measured against the screen bounds rather than
    /// a `GeometryReader`-measured local size, matching the same approximation already used for the
    /// scroll content's `minHeight` a few lines up in `body`.
    private func handleTap(at location: CGPoint, proxy: ScrollViewProxy) {
        let screenSize = UIScreen.main.bounds.size
        let col = min(2, max(0, Int(location.x / (screenSize.width / 3))))
        let row = min(2, max(0, Int(location.y / (screenSize.height / 3))))
        perform(ReaderTapZoneGrid.decode(tapZoneGridRaw).action(row: row, col: col), proxy: proxy)
    }

    private func perform(_ action: ReaderTapZoneAction, proxy: ScrollViewProxy) {
        switch action {
        case .none:
            break
        case .toggleChrome:
            isChromeVisible.toggle()
        case .previousChapter:
            goTo(currentIndex - 1)
        case .nextChapter:
            goTo(currentIndex + 1)
        case .openToc:
            isShowingToc = true
        case .nextPage:
            // Reuses the exact same step-based scroll the volume-key paging already does -- there
            // are no real "pages" in a continuous-scroll reader, so this is the same honest
            // paragraph-step approximation, just triggered by a tap zone instead of a hardware key.
            handleVolumeKeyTurn(direction: 1, proxy: proxy)
        case .previousPage:
            handleVolumeKeyTurn(direction: -1, proxy: proxy)
        case .exitReader:
            dismiss()
        }
    }

    private func toggleAutoScroll(proxy: ScrollViewProxy) {
        if isAutoScrolling {
            stopAutoScroll()
        } else {
            startAutoScroll(proxy: proxy)
        }
    }

    /// Advances one paragraph per `autoScrollInterval` seconds, hands-free -- not a continuous
    /// pixel-by-pixel scroll (SwiftUI's `ScrollViewProxy` only exposes anchor-based `scrollTo`, not
    /// an arbitrary offset), so this reads more like an auto-advancing teleprompter than a smoothly
    /// gliding page. Stops on its own at the last paragraph rather than rolling into the next
    /// chapter automatically -- chapter auto-advance already has its own distinct trigger (the
    /// bottom sentinel in `attemptAutoAdvance`), and conflating the two risked skipping the user
    /// past a chapter boundary while they weren't looking at the screen.
    private func startAutoScroll(proxy: ScrollViewProxy) {
        autoScrollTask?.cancel()
        isAutoScrolling = true
        autoScrollTask = Task {
            var index = 0
            while !Task.isCancelled && index < paragraphs.count {
                withAnimation {
                    proxy.scrollTo(index, anchor: .top)
                }
                index += 1
                try? await Task.sleep(nanoseconds: UInt64(max(autoScrollInterval, 0.5) * 1_000_000_000))
            }
            if !Task.isCancelled {
                isAutoScrolling = false
            }
        }
    }

    private func stopAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        isAutoScrolling = false
    }

    /// Paginated-mode equivalent of auto-scroll -- Legado's real "自动翻页" (`AutoPager`) works this
    /// way regardless of page-turn style since its reader is always page-based; this reader only
    /// has a real page concept in the 4 non-`.scroll` styles, so this is the paginated-only half of
    /// the same "hands-free reading" feature, reusing the same `autoScrollInterval` setting and the
    /// `pageTurnRequest` channel volume keys already drive.
    private func toggleAutoPage() {
        if isAutoPaging {
            stopAutoPage()
        } else {
            startAutoPage()
        }
    }

    private func startAutoPage() {
        autoPageTask?.cancel()
        isAutoPaging = true
        autoPageTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(max(autoScrollInterval, 0.5) * 1_000_000_000))
                guard !Task.isCancelled else { break }
                pageTurnRequest = .next
            }
        }
    }

    private func stopAutoPage() {
        autoPageTask?.cancel()
        autoPageTask = nil
        isAutoPaging = false
    }

    private func applyChineseConversion(_ text: String) -> String {
        switch chineseConversion {
        case .off: return text
        case .toTraditional: return ChineseTextConverter.convert(text, direction: .simplifiedToTraditional)
        case .toSimplified: return ChineseTextConverter.convert(text, direction: .traditionalToSimplified)
        }
    }

    /// Feeds `ChapterContentSearchView` -- only chapters already saved to `chapterCacheStore` (via
    /// the "缓存全本"/per-chapter caching flow) are searchable, since fetching every remaining
    /// chapter over the network on-demand just to search it would be slow and wasteful.
    private func loadCachedChaptersForSearch() async -> [(index: Int, title: String, text: String)] {
        var result: [(index: Int, title: String, text: String)] = []
        for chapter in chapters {
            if let cached = try? await env.chapterCacheStore.chapter(bookUrl: bookUrl, index: chapter.index) {
                result.append((index: chapter.index, title: chapter.title, text: cached.text))
            }
        }
        return result
    }

    /// Advances to the next chapter without requiring an explicit tap on "下一章" -- guarded by
    /// `canAutoAdvance`'s grace period, and skipped while read-aloud is active (its own chapter
    /// change already stops speech via `onChange(of: currentIndex)`; auto-advancing mid-sentence
    /// while the user is listening, rather than reading, would be jarring rather than helpful).
    private func attemptAutoAdvance() {
        guard canAutoAdvance, !isReadAloudSpeaking, !isLoading else { return }
        // Prefer the seamless path -- the preview is usually already sitting there since
        // `loadNextChapterPreview` kicks off as soon as the current chapter finishes loading, well
        // before the user could realistically scroll this far. Falls back to the old full-reload
        // `goTo` path if the preview genuinely isn't ready yet (slow connection, or this is the very
        // last chapter and there's nothing to preview) -- `pageLayout != nil` specifically, not just
        // the preview existing, since committing a preview whose pages haven't finished computing
        // yet would promote a chapter with nothing to actually render.
        if let preview = nextChapterPreview, preview.pageLayout != nil {
            commitToNextChapterPreview(preview)
            return
        }
        guard currentIndex < chapters.count - 1 else { return }
        goTo(currentIndex + 1)
    }

    /// Adopts a different source for the book currently being read, in place -- fetches the new
    /// source's own table of contents, carries the chapter *index* over as a best-effort
    /// approximation (same convention `ShelfView.switchSource` already uses: chapter numbering is
    /// usually close enough across sources for the same book, clamped if the new list is shorter),
    /// and updates the shelf entry too if this book happens to be shelved -- reading a book doesn't
    /// require it to be on the shelf (e.g. reached via "立即阅读" from the detail page), so that part
    /// is skipped when there's nothing to update.
    private func switchSource(to newSource: BookSource, match: SearchResult) async {
        let oldBookUrl = bookUrl
        let bookInfo = try? await BookInfoService.fetchBookInfo(source: newSource, bookURL: match.bookUrl, httpClient: env.httpClient)
        guard let tocUrl = bookInfo?.tocUrl else { return }
        let newChapters = (try? await TocService.fetchChapterList(source: newSource, tocURL: tocUrl, httpClient: env.httpClient)) ?? []
        guard !newChapters.isEmpty else { return }

        let newIndex = min(currentIndex, newChapters.count - 1)
        source = newSource
        bookUrl = match.bookUrl
        self.tocUrl = tocUrl
        chapters = newChapters
        bookTitle = bookInfo?.name ?? match.name
        currentIndex = newIndex

        if let existing = try? await env.shelfStore.book(bookUrl: oldBookUrl) {
            let updated = ShelfBook(
                bookSourceUrl: newSource.bookSourceUrl,
                bookUrl: match.bookUrl,
                name: bookInfo?.name ?? match.name,
                author: bookInfo?.author ?? match.author,
                coverUrl: bookInfo?.coverUrl ?? match.coverUrl,
                intro: bookInfo?.intro ?? match.intro,
                tocUrl: tocUrl,
                lastChapterTitle: bookInfo?.lastChapter ?? match.lastChapter,
                addedAt: existing.addedAt,
                group: existing.group,
                lastReadChapterIndex: newIndex,
                lastReadChapterTitle: newChapters[newIndex].title,
                lastReadCharacterOffset: 0,
                lastReadAt: existing.lastReadAt,
                totalChapterCount: newChapters.count
            )
            try? await env.shelfStore.remove(bookUrl: oldBookUrl)
            try? await env.shelfStore.addOrUpdate(updated)
        }
    }

    /// Fixes just the chapter currently on screen without switching the book's source for anything
    /// else -- finds this chapter's title in another source's table of contents (falling back to
    /// the same index if no title matches), fetches its content from there, and saves it into
    /// `chapterCacheStore` under the *original* book/index. `load()`'s existing cache-first lookup
    /// then picks it up transparently, exactly as if the chapter had been downloaded normally, so
    /// the fix persists across relaunches without any new loading path.
    private func switchChapterSource(to newSource: BookSource, match: SearchResult) async {
        let originalIndex = chapter.index
        let originalTitle = chapter.title
        isLoading = true
        do {
            let bookInfo = try await BookInfoService.fetchBookInfo(source: newSource, bookURL: match.bookUrl, httpClient: env.httpClient)
            let altChapters = try await TocService.fetchChapterList(source: newSource, tocURL: bookInfo.tocUrl, httpClient: env.httpClient)
            let byTitle = altChapters.first(where: { $0.title == originalTitle })
            let fallback: BookChapter? = altChapters.indices.contains(originalIndex) ? altChapters[originalIndex] : altChapters.first
            guard let matchedChapter = byTitle ?? fallback else {
                errorMessage = "对方书源没有可用章节"
                isLoading = false
                return
            }
            let content = try await ContentService.fetchContent(source: newSource, chapter: matchedChapter, httpClient: env.httpClient)
            try await env.chapterCacheStore.save(bookUrl: bookUrl, index: originalIndex, content: content)
        } catch {
            errorMessage = "本章换源失败: \(error)"
            isLoading = false
            return
        }
        await load()
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
                return partial + Text(segment.text).foregroundStyle(theme.textColor(for: colorScheme, customText: Color(hex: customThemeTextHex)))
            }
        }
    }

    /// Prepends `paragraphIndent` full-width spaces before running the paragraph through
    /// `highlightedText` -- real usage feedback wanted every paragraph's first line indented like
    /// real Chinese print typesetting, not just the ones lucky enough to come from a book source
    /// whose own `replaceRegex` happened to add it (see `ReaderSettingsKey.paragraphIndent`'s doc
    /// comment). Prepending before highlighting is safe: the indent is plain, unstyled leading
    /// whitespace, so it can't shift where a highlight rule's own match offsets land in the rest of
    /// the (unindented) source text used to compute `segments`.
    private func indentedText(_ paragraph: String) -> Text {
        guard paragraphIndent > 0 else { return highlightedText(paragraph) }
        return Text(String(repeating: "　", count: paragraphIndent)) + highlightedText(paragraph)
    }

    /// Bold, centered chapter title shown inline in the reading area itself -- real usage feedback,
    /// with a reference screenshot, wanted this for *every* chapter section (including the very
    /// first/current one, which previously relied on the top bar alone) and wanted the gap before it
    /// to read as genuine blank space, not a drawn rule -- a plain `Divider()` line was tried first
    /// and reads as "a UI element," not "empty space between chapters," so this is just padding.
    private func chapterHeading(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(theme.textColor(for: colorScheme, customText: Color(hex: customThemeTextHex)))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
            .padding(.bottom, 12)
            .padding(.horizontal, 4)
    }

    /// Real, screen-measured `.scroll` mode rendering -- pulled out of `body`'s `if`/`else` into its
    /// own function because inlining this whole `GeometryReader`/`ScrollView`/`ForEach`/gesture tree
    /// directly in `body` made the combined expression too large for the type checker to resolve in
    /// reasonable time (`Xcode` build error: "unable to type-check this expression"). `GeometryReader`
    /// measures the actual on-screen content area, exactly like `PagedChapterReaderView` already does
    /// for its own 4 paginated styles -- `ChapterPaginator` needs to know how many points of height
    /// are actually available to know how much text fits one "page." Confirmed against Legado_Max's
    /// real source that `.scroll` mode there is built on this exact same screen-measured
    /// page-splitting engine, not a raw continuous-text flow; this whole branch replaces this
    /// reader's previous "just flow every paragraph in one long VStack" implementation to match.
    @ViewBuilder
    private func scrollModeBody(scrollProxy: ScrollViewProxy) -> some View {
        GeometryReader { geo in
            let contentSize = CGSize(
                width: max(geo.size.width - pageMarginLeading - pageMarginTrailing, 0),
                height: max(geo.size.height - pageMarginTop - pageMarginBottom, 0)
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Real usage feedback: only the *appended next chapter* got a heading before this
                    // -- the very first (current) chapter shown had no inline title at all, only the
                    // top bar's. Every chapter section, including this first one, now gets the same
                    // bold centered heading so the reading area alone tells you which chapter you're
                    // in. `"heading"`'s id is what `.onChange(of: currentIndex)`'s "scroll to top"
                    // reset targets, so landing on a new chapter shows its heading too, not just its
                    // first page.
                    chapterHeading(chapter.title)
                        .id("heading")

                    if let pageLayout {
                        ForEach(0..<pageLayout.pages.count, id: \.self) { pageIndex in
                            pageBlock(pageIndex, layout: pageLayout)
                                .id("page-\(pageIndex)")
                                // Reports this page's position so `currentPageIndexInChapter` can
                                // track real reading position (see its own doc comment) -- real usage
                                // feedback: reopening a book always landed at the *start* of the
                                // last-read chapter, never the exact spot, because nothing tracked
                                // position within a chapter.
                                .background(
                                    GeometryReader { pageGeo in
                                        Color.clear.preference(
                                            key: PageTopOffsetKey.self,
                                            value: [pageIndex: pageGeo.frame(in: .named("readerScroll")).minY]
                                        )
                                    }
                                )
                        }
                    }

                    // Next chapter, appended right below -- real usage feedback (with a reference
                    // screenshot) asked for chapters to visually connect: the previous chapter's
                    // ending, a gap, then the next chapter's title as a heading, then its own text,
                    // all in one continuous scroll, instead of the screen reloading to a blank top
                    // once you hit the bottom. `nextChapterPreview` is already fully fetched+purified
                    // +paginated by the time it's showing here (see `loadNextChapterPreview`), so
                    // there's no loading gap to paper over -- it's simply already there once you
                    // scroll far enough.
                    if let preview = nextChapterPreview, let previewLayout = preview.pageLayout {
                        chapterHeading(preview.title)
                            .id("next-heading")

                        ForEach(0..<previewLayout.pages.count, id: \.self) { pageIndex in
                            pageBlock(pageIndex, layout: previewLayout)
                                .id("next-page-\(pageIndex)")
                        }
                    }

                    // Invisible sentinel below the last page (of the current chapter, or of the
                    // appended next-chapter preview when there is one) -- its appearance means the
                    // user has scrolled (or the content was short enough to start fully visible) to
                    // the very bottom.
                    Color.clear
                        .frame(height: 1)
                        .onAppear { attemptAutoAdvance() }
                }
                .padding(EdgeInsets(top: pageMarginTop, leading: pageMarginLeading, bottom: pageMarginBottom, trailing: pageMarginTrailing))
                .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height, alignment: .topLeading)
                .contentShape(Rectangle())
                // A zero-distance DragGesture rather than .onTapGesture -- SwiftUI's plain tap gesture
                // doesn't expose *where* the tap landed, and the 3x3 zone grid needs that location to
                // pick which of the 9 regions was hit (see `handleTap`). `touchSlop` filters out
                // releases too far from where the finger went down -- a scroll attempt that only moved
                // a little shouldn't also register as a tap-zone tap.
                //
                // `.simultaneousGesture`, not `.gesture` -- a plain `.gesture(DragGesture(minimumDistance:
                // 0))` on content *inside* a `ScrollView` can win the touch outright and starve the
                // ScrollView's own built-in pan/scroll gesture of it, which reads as "scrolling just
                // doesn't work" (real-device feedback: the page never moves at all in `.scroll` mode).
                // `.simultaneousGesture` lets both this tap-zone recognizer and the ScrollView's native
                // scrolling see the same touch instead of one exclusively claiming it.
                //
                // `coordinateSpace: .global` -- real usage feedback: tap zones stopped doing anything
                // once scrolled even a little way into a chapter. Root cause: `DragGesture`'s `.location`
                // defaults to `.local`, i.e. relative to *this VStack's own bounds* -- which, now that
                // pages plus a whole appended next-chapter preview can span many screens' worth of
                // height, is nowhere close to the screen. `handleTap` compares that value against
                // `UIScreen.main.bounds`, so any real scroll position produced a huge local Y that always
                // clamped to the bottom row, no matter where on the actual screen the tap landed. `.global`
                // makes `.location` screen-relative, matching what `handleTap` already assumes.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onEnded { value in
                            guard hypot(value.translation.width, value.translation.height) <= touchSlop else { return }
                            handleTap(at: value.location, proxy: scrollProxy)
                        }
                )
            }
            .coordinateSpace(name: "readerScroll")
            .onPreferenceChange(PageTopOffsetKey.self) { offsets in
                // Whichever page's top edge is closest to the scroll viewport's own top edge is
                // "currently being read" -- matches how a reader visually tracks position (whatever's
                // at the top of the screen right now).
                if let closest = offsets.min(by: { abs($0.value) < abs($1.value) }) {
                    currentPageIndexInChapter = closest.key
                }
            }
            .task(id: scrollPaginationKey(size: contentSize)) {
                await repaginateForScroll(size: contentSize, proxy: scrollProxy)
            }
        }
    }

    /// Renders one screen-measured page's worth of chunks. `chunkOffset == 0` needing special
    /// handling is the one real subtlety `ChapterPageLayout` warns about in its own doc comment: a
    /// paragraph that got split mid-way by pagination (it doesn't happen to end exactly at this
    /// page's boundary) shows up as the *last* chunk of one page and the *first* chunk of the next,
    /// both sharing the same `paragraphIndex` -- indenting that continuation chunk as if it were a
    /// fresh paragraph start would visibly indent text mid-sentence, which is wrong. Comparing this
    /// page's first chunk's `paragraphIndex` against the *previous* page's last chunk catches exactly
    /// that case (verified by `ChapterPageLayoutTests`'s own mid-paragraph-split fixture).
    @ViewBuilder
    private func pageBlock(_ index: Int, layout: ChapterPageLayout) -> some View {
        let chunks = layout.chunks(forPage: index)
        let previousPageLastParagraphIndex = index > 0 ? layout.chunks(forPage: index - 1).last?.paragraphIndex : nil
        VStack(alignment: .leading, spacing: paragraphSpacing) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { chunkOffset, chunk in
                let isContinuation = chunkOffset == 0 && chunk.paragraphIndex == previousPageLastParagraphIndex
                Group {
                    if isContinuation {
                        highlightedText(chunk.text)
                    } else {
                        indentedText(chunk.text)
                    }
                }
                .font(.system(size: fontSize))
                .lineSpacing(lineSpacing)
                .padding(.horizontal, 4)
                .background(
                    isReadAloudSpeaking && chunk.paragraphIndex == readAloudCurrentParagraphIndex
                        ? Color.accentColor.opacity(0.15) : Color.clear
                )
                // Real usage feedback pointed at a reference app whose long-press-to-select popup
                // has custom 净化/全文搜索/百科/网络搜索 buttons instead of the plain system Copy
                // menu. That specific customization needs UIKit (SwiftUI has no documented hook to
                // inject items into `.textSelection`'s own menu), and doing that would mean routing
                // a `UITextView` through this exact rendering path -- the same `ScrollView` this
                // session's other real fix (see the `.simultaneousGesture` doc comment above) just
                // untangled from a gesture conflict real usage caught. Adding real selection at all
                // (there was previously no way to copy text out of this reader) without that riskier
                // rewrite is the safer increment; the custom menu is deferred.
                .textSelection(.enabled)
            }
        }
        .padding(.vertical, 8)
    }

    private func load() async {
        if justCommittedFromPreview {
            // A seamless preview-commit (see `commitToNextChapterPreview`) already set `text`/
            // `matchedReplaceRules` correctly for this `currentIndex` without any network round trip
            // -- re-running the full fetch+purify pipeline here (which `.task(id:)` would otherwise
            // trigger just from `currentIndex` changing) would both waste a redundant fetch and,
            // worse, flash the loading spinner over content that's already sitting on screen mid-
            // scroll, undoing the whole point of committing seamlessly in the first place.
            justCommittedFromPreview = false
            return
        }
        isLoading = true
        errorMessage = nil
        canAutoAdvance = false
        do {
            let cached = try? await env.chapterCacheStore.chapter(bookUrl: bookUrl, index: chapter.index)
            let content: ChapterContent
            if let cached {
                content = cached
            } else {
                content = try await ContentService.fetchContent(source: source, chapter: chapter, httpClient: env.httpClient)
            }
            let replaceRules = (try? await env.replaceRuleStore.enabled()) ?? []
            let purified = ReplaceRuleApplier.applyReportingMatches(replaceRules, to: content.text, sourceUrl: source.bookSourceUrl)
            text = applyChineseConversion(purified.result)
            matchedReplaceRules = purified.matchedRules
            highlightRules = (try? await env.highlightRuleStore.enabled()) ?? []
            try? await env.shelfStore.updateProgress(
                bookUrl: bookUrl, chapterIndex: chapter.index, chapterTitle: chapter.title, characterOffset: 0
            )
            isCurrentChapterBookmarked = (try? await env.bookmarkStore.isBookmarked(
                bookIdentifier: bookUrl, chapterIndex: chapter.index
            )) ?? false
            // Resuming mid-chapter (see `init`'s `resumeCharacterOffset` doc comment) is handled in
            // `repaginateForScroll` now, not here -- converting a saved character offset into a
            // scroll target needs the actual page layout (which page's `NSRange` contains that
            // offset), and this function has no access to that; `pendingResumeCharacterOffset` stays
            // set until pagination runs against this chapter's real (non-empty) text and consumes it.
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
        armAutoAdvance()
        prefetchUpcomingChapters()
        await loadNextChapterPreview()
    }

    /// Prefetches and fully purifies+paginates the *next* chapter's content ahead of time so it can
    /// be appended right below the current chapter's own pages (see `nextChapterPreview`'s doc
    /// comment for why). Reuses `ChapterCacheStore` -- the same cache `prefetchUpcomingChapters`
    /// already warms -- so this is usually an instant cache hit rather than a second network
    /// request racing that one. Skips pagination (leaves `pageLayout` `nil` on the returned preview)
    /// if `scrollPageSize` hasn't been measured yet or the reader is in a paginated style -- either
    /// way `attemptAutoAdvance` only commits a preview once its `pageLayout` is actually ready.
    private func loadNextChapterPreview() async {
        let nextIndex = currentIndex + 1
        guard chapters.indices.contains(nextIndex) else {
            nextChapterPreview = nil
            return
        }
        let nextChapter = chapters[nextIndex]
        let cached = try? await env.chapterCacheStore.chapter(bookUrl: bookUrl, index: nextIndex)
        let content: ChapterContent
        if let cached {
            content = cached
        } else {
            guard let fetched = try? await ContentService.fetchContent(
                source: source, chapter: nextChapter, httpClient: env.httpClient
            ) else {
                nextChapterPreview = nil
                return
            }
            content = fetched
        }
        // Guards against a stale response landing after the user has already moved past this
        // chapter some other way (e.g. jumped via TOC/search while this fetch was still in flight).
        guard nextIndex == currentIndex + 1 else { return }
        let replaceRules = (try? await env.replaceRuleStore.enabled()) ?? []
        let purified = ReplaceRuleApplier.applyReportingMatches(replaceRules, to: content.text, sourceUrl: source.bookSourceUrl)
        let previewText = applyChineseConversion(purified.result)
        var preview = NextChapterPreview(
            index: nextIndex, title: nextChapter.title, text: previewText, matchedRules: purified.matchedRules
        )
        if !pageTurnStyle.isPaginated, scrollPageSize.width > 0, scrollPageSize.height > 0 {
            let font = UIFont.systemFont(ofSize: fontSize)
            let pages = ChapterPaginator.paginate(
                text: previewText, font: font, lineSpacing: lineSpacing, paragraphSpacing: paragraphSpacing,
                pageSize: scrollPageSize
            )
            preview.pageLayout = ChapterPageLayout(paragraphs: previewText.components(separatedBy: "\n"), pages: pages)
        }
        nextChapterPreview = preview
    }

    /// Promotes an already-fetched-and-purified-and-paginated preview straight to "current" -- no
    /// network round trip, no re-pagination, and critically no `ScrollView` content-swap-then-reset-
    /// to-top the way `goTo` needs (see `onChange(of: currentIndex)`'s doc comment): the preview's
    /// pages are already sitting in the same `ScrollView` right where they've been all along, so
    /// promoting it just relabels which pages count as "the current chapter" for read-aloud/
    /// highlight/bookmark/position-tracking purposes. The two "suppress" flags stop that relabeling
    /// from *also* triggering a redundant reload or an unwanted scroll-to-top -- both would undo the
    /// whole point of committing silently.
    private func commitToNextChapterPreview(_ preview: NextChapterPreview) {
        justCommittedFromPreview = true
        suppressScrollResetOnNextChapterChange = true
        currentIndex = preview.index
        text = preview.text
        matchedReplaceRules = preview.matchedRules
        pageLayout = preview.pageLayout
        lastPaginatedScrollText = preview.text
        currentPageIndexInChapter = 0
        nextChapterPreview = nil
        canAutoAdvance = false
        armAutoAdvance()
        Task {
            try? await env.shelfStore.updateProgress(
                bookUrl: bookUrl, chapterIndex: preview.index, chapterTitle: preview.title, characterOffset: 0
            )
            isCurrentChapterBookmarked = (try? await env.bookmarkStore.isBookmarked(
                bookIdentifier: bookUrl, chapterIndex: preview.index
            )) ?? false
        }
        Task { await loadNextChapterPreview() }
        prefetchUpcomingChapters()
    }

    /// Same shape as `PagedChapterReaderView.paginationKey` -- everything that can change how a
    /// chapter's text breaks into pages (the text itself, font size, line/paragraph spacing, and the
    /// measured screen area) is part of the key, so `.task(id:)` only re-paginates when something
    /// that actually affects page breaks changes, not on every unrelated body re-evaluation.
    private func scrollPaginationKey(size: CGSize) -> String {
        "\(text.count)-\(text.hashValue)-\(fontSize)-\(lineSpacing)-\(paragraphSpacing)-\(Int(size.width))-\(Int(size.height))"
    }

    /// Real, TextKit-measured pagination for `.scroll` mode -- see `pageLayout`'s doc comment for
    /// why this reuses the exact same `ChapterPaginator`/`ChapterPageLayout` machinery
    /// `PagedChapterReaderView` already uses for its own 4 paginated styles, rather than a second,
    /// separately-risked implementation. Also the single place that consumes
    /// `pendingResumeCharacterOffset` (see `init`'s doc comment): converting a saved character
    /// offset into a scroll target needs to know *which page's `NSRange` contains that offset*, which
    /// only exists once pagination has actually run.
    private func repaginateForScroll(size: CGSize, proxy: ScrollViewProxy) async {
        guard size.width > 0, size.height > 0, !text.isEmpty else { return }
        scrollPageSize = size
        let font = UIFont.systemFont(ofSize: fontSize)
        let pages = ChapterPaginator.paginate(
            text: text, font: font, lineSpacing: lineSpacing, paragraphSpacing: paragraphSpacing, pageSize: size
        )
        guard !Task.isCancelled else { return }
        let newLayout = ChapterPageLayout(paragraphs: paragraphs, pages: pages)

        let isSameChapterReflow = lastPaginatedScrollText == text
        if isSameChapterReflow, let oldLayout = pageLayout, oldLayout.pages.indices.contains(currentPageIndexInChapter) {
            // Only a reading-settings slider changed (font/margins/etc), not the chapter -- try to
            // stay on roughly the same paragraph instead of jumping back to page 1.
            let anchorParagraph = oldLayout.chunks(forPage: currentPageIndexInChapter).first?.paragraphIndex ?? 0
            currentPageIndexInChapter = newLayout.pageIndex(forParagraphIndex: anchorParagraph)
        } else {
            currentPageIndexInChapter = 0
        }
        pageLayout = newLayout
        lastPaginatedScrollText = text

        if let offset = pendingResumeCharacterOffset {
            pendingResumeCharacterOffset = nil
            let targetPage = newLayout.pages.firstIndex { $0.location + $0.length > offset } ?? 0
            currentPageIndexInChapter = targetPage
            let targetID = "page-\(targetPage)"
            DispatchQueue.main.async {
                withAnimation(nil) {
                    proxy.scrollTo(targetID, anchor: .top)
                }
            }
        }
    }

    /// Persists the current page's starting character offset (a real `NSRange.location` from
    /// `ChapterPaginator`'s TextKit measurement, not an approximation) as this chapter's exact resume
    /// position -- called periodically (`scheduleTimer`, already firing every 60s for the eye-care
    /// schedule) and on `.onDisappear`, not on every scroll frame, since writing to disk that often
    /// would be wasteful. Scroll-mode only, matching `currentPageIndexInChapter`'s own scope.
    private func saveReadingProgress() {
        guard !pageTurnStyle.isPaginated, !isLoading, let pageLayout,
              pageLayout.pages.indices.contains(currentPageIndexInChapter) else { return }
        let offset = pageLayout.pages[currentPageIndexInChapter].location
        Task {
            try? await env.shelfStore.updateProgress(
                bookUrl: bookUrl, chapterIndex: chapter.index, chapterTitle: chapter.title, characterOffset: offset
            )
        }
    }

    /// Fires a best-effort background fetch for the next `prefetchChapterCount` chapters so tapping
    /// "下一章" is usually an instant cache hit instead of a network wait -- the single most common
    /// action in a reading session, and previously always a fresh network round-trip no matter how
    /// predictable "the next chapter" is. Silent on failure/skip (a miss just falls back to `load()`'s
    /// own normal network fetch, exactly like before this existed); re-checks `chapters.indices`
    /// inside the loop rather than trusting a range computed once, since 换源 can shrink `chapters`
    /// out from under an in-flight prefetch if the user switches source mid-fetch.
    private func prefetchUpcomingChapters() {
        guard prefetchChapterCount > 0 else { return }
        let targetIndices = (currentIndex + 1)..<(currentIndex + 1 + prefetchChapterCount)
        Task {
            for index in targetIndices {
                guard chapters.indices.contains(index) else { break }
                if (try? await env.chapterCacheStore.chapter(bookUrl: bookUrl, index: index)) != nil { continue }
                guard let content = try? await ContentService.fetchContent(
                    source: source, chapter: chapters[index], httpClient: env.httpClient
                ) else { continue }
                try? await env.chapterCacheStore.save(bookUrl: bookUrl, index: index, content: content)
            }
        }
    }

    /// Bookmarks are chapter-level (this reader doesn't track a finer scroll position anywhere),
    /// so the button is a simple toggle -- one bookmark per (book, chapter) at most.
    private func toggleBookmark() async {
        if isCurrentChapterBookmarked {
            try? await env.bookmarkStore.remove(bookIdentifier: bookUrl, chapterIndex: chapter.index)
            isCurrentChapterBookmarked = false
        } else {
            let bookmark = Bookmark(
                isLocal: false, bookSourceUrl: source.bookSourceUrl, bookIdentifier: bookUrl,
                tocUrl: tocUrl, bookTitle: bookTitle, chapterIndex: chapter.index, chapterTitle: chapter.title
            )
            try? await env.bookmarkStore.add(bookmark)
            isCurrentChapterBookmarked = true
        }
    }

    /// Runs once per chapter load (both the reader's very first chapter and every subsequent
    /// transition, since this is called from `load()` rather than `.onChange(of: currentIndex)`,
    /// which never fires for a view's initial state) -- the delay gives a short-enough-to-fit-on
    /// -one-screen chapter a moment before the bottom sentinel's mere presence can trigger another
    /// auto-advance.
    private func armAutoAdvance() {
        let loadedIndex = currentIndex
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, currentIndex == loadedIndex else { return }
            canAutoAdvance = true
        }
    }
}
