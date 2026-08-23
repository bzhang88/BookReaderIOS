import SwiftUI
import UIKit
import BookSourceModel
import WebBookOrchestrator
import Persistence
import RuleEngine

/// Fully fetched-and-purified adjacent-chapter content, ready to display immediately (see
/// `ReaderView.prevChapterPreview`/`nextChapterPreview`'s doc comments) or promote straight to
/// "current" with no further network/purification work needed. `pageLayout` is filled in once
/// pagination (which needs the measured screen size) has actually run against `text` -- may briefly
/// be `nil` right after the text itself arrives, and is recomputed by `repaginateForScroll` whenever
/// reading settings that affect page breaks change, exactly like the current chapter's own
/// `pageLayout`. Used for both the previous and the next chapter -- confirmed against Legado_Max's
/// `ReadBook` (`prevTextChapter`/`curTextChapter`/`nextTextChapter`) that its scroll mode keeps
/// exactly this same 3-chapter window resident, not just "current + next."
private struct AdjacentChapterPreview {
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
    // Real bug found comparing against Legado: this reader never tracked the book's author at all,
    // so both its own 换源/章节换源 sheets hardcoded `bookAuthor: nil` into `ChangeSourceView` --
    // weakening its same-book filter to name-only matching only for these two in-reader entry
    // points (BookDetailView/ShelfView's own change-source flows already passed a real author).
    @State private var bookAuthor: String?
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
    /// Non-nil once `switchChapterSource` has auto-matched a candidate chapter and fetched the
    /// alternate source's real TOC -- drives `ChapterSourcePickerView` via `.sheet(item:)`. See that
    /// context type's own doc comment.
    @State private var chapterSourcePicker: ChapterSourcePickerContext?
    @State private var isShowingToc = false
    @State private var isShowingContentSearch = false
    @State private var isShowingAISummary = false
    @State private var isShowingDictLookup = false
    @State private var isShowingContentEdit = false
    @State private var isShowingWebSearch = false
    @State private var isShowingReplaceRules = false
    // Drive the reader's custom long-press-paragraph menu (`pageBlock`'s `.contextMenu`, `.scroll`
    // mode only -- see that modifier's doc comment for why paginated mode isn't included). One
    // shared holder for "which paragraph's text is this action about" rather than a separate copy
    // per action, since only one of dict/web-search/content-search/purify-seed is ever open at once.
    @State private var paragraphMenuText = ""
    @State private var isShowingReplaceRuleSeed = false
    @State private var isShowingParagraphShareSheet = false
    @State private var isChromeVisible = true
    // Brightness is a toggleable quick-access row (tap the "亮度" icon to reveal/hide it), not a
    // permanently-visible slider -- matches the reference reading app the user pointed at directly
    // (a slider taking up a full row at all times, whether or not anyone's about to touch it, was
    // part of what made the previous chrome feel cluttered).
    @State private var isBrightnessVisible = false
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
    @Environment(\.scenePhase) private var scenePhase

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
    @AppStorage(ReaderSettingsKey.backwardPrefetchChapterCount) private var backwardPrefetchChapterCount: Int = 1
    @AppStorage(ReaderSettingsKey.screenOrientationLock) private var screenOrientationLock: ReaderOrientationLock = .followSystem
    @AppStorage(ReaderSettingsKey.progressBarBehavior) private var progressBarBehavior: ProgressBarBehavior = .page
    // Shared between `prefetchUpcomingChapters`/`prefetchPreviousChapters` so together they never
    // have more than 2 chapter fetches in flight -- see `PrefetchLimiter`'s doc comment. `@State`
    // (not a plain `let`) because a SwiftUI View struct's stored properties are recreated on every
    // body re-evaluation; only `@State`'s underlying storage survives across those, which this needs
    // to stay one actor instance for the life of the reading session, not a fresh one per re-render.
    @State private var prefetchLimiter = PrefetchLimiter(limit: 2)
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
    // Same idea as `pageSeekDragValue`, for `.chapter` progress-bar mode's seekbar.
    @State private var chapterSeekDragValue: Double?
    // `ReadMenu.kt`'s `confirmSkipToChapter` -- Legado only asks "确定要跳转章节吗？" once per reading
    // session (this reader instance's lifetime), not on every single chapter-jump drag.
    @State private var hasConfirmedChapterJumpThisSession = false
    @State private var pendingChapterJumpIndex: Int?
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
    /// Which page of the current chapter is showing in `.scroll` mode -- the single authoritative
    /// reading-position variable, advanced exactly once per full page crossing by `stepToNextPage`/
    /// `stepToPreviousPage` (never guessed at after the fact). *Persisted* to `ShelfStore`
    /// periodically (`scheduleTimer`) and on `.onDisappear`/backgrounding (see those handlers), not
    /// on every drag frame, since writing to disk that often would be wasteful. Scoped to `.scroll`
    /// mode only -- `PagedChapterReaderView` already tracks its own page position independently for
    /// the 4 paginated styles.
    @State private var currentPageIndexInChapter = 0
    /// Live pixel offset of the *current* page from its resting position in `.scroll` mode --
    /// positive means dragged down (revealing the previous page/chapter above), negative means
    /// dragged up (revealing the next page/chapter below). Exactly mirrors Legado_Max's real
    /// `ContentTextView.pageOffset`: driven directly by raw touch deltas rather than a native
    /// `ScrollView`, and only ever adjusted (by exactly one page's height) at the instant a page or
    /// chapter boundary is actually crossed (`commitPageOffset`) -- never snapped back to 0 just
    /// because a drag ended, so it can rest at any sub-page position exactly like a real continuous
    /// scroll. This reader's previous `.scroll` mode was built on a native `ScrollView` plus
    /// SwiftUI preference-key position *detection* instead -- real-device testing repeatedly found
    /// that "detect after the fact and correct" approach racy (chapters failing to connect,
    /// backward-cascade jumps that got progressively harder to fully close off) in a way this
    /// direct, deterministic port of Legado's own mechanism doesn't have room for: there's no
    /// separate detection step to race against, the crossing *is* the state update.
    @State private var dragOffset: CGFloat = 0
    /// `dragOffset`'s value at the moment the current drag gesture began, so each subsequent
    /// `.onChanged` call (whose own `value.translation` is always relative to *that* gesture's own
    /// start, resetting to zero every time a new touch begins) can be added on top of wherever
    /// `dragOffset` already was resting, instead of overwriting it.
    @State private var dragGestureBaseOffset: CGFloat = 0
    /// Set while an *animated* page turn (volume key, tap zone, auto-scroll) is sliding into place
    /// -- mirrors `PagedChapterReaderView.pendingTransitionTask`'s exact purpose: the visual slide
    /// runs under `withAnimation` immediately, but the actual page-index commit (and the chance to
    /// cross a chapter boundary) is deliberately deferred until the animation would have visually
    /// finished, matching Legado's own `PageDelegate.nextPageByAnim`/`startScroll` (animate first,
    /// commit once the scroll settles) as distinct from a live finger-drag's immediate, un-animated
    /// `commitPageOffset` calls.
    @State private var pendingPageStepTask: Task<Void, Never>?
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
    /// chapter's own paragraphs -- see the rendering code in `scrollModeBody` and
    /// `commitToNextChapterPreview` for the full picture. Real usage feedback pointed at a reference
    /// app (screenshot: chapter 3's ending, a gap, then chapter 4's title as a heading, then chapter
    /// 4's own text -- all in one continuous scroll) where chapters visually flow into each other
    /// instead of this reader's previous behavior (hit the bottom -> the whole screen reloads to a
    /// blank top).
    @State private var nextChapterPreview: AdjacentChapterPreview?
    /// Same idea as `nextChapterPreview`, mirrored backward -- the previous chapter's content,
    /// prepended above the current chapter's own heading, so scrolling *up* past the top connects
    /// into the previous chapter exactly the same way scrolling down connects into the next one.
    /// Real usage feedback: this reader only ever kept "current + next" resident, requiring an
    /// explicit "下一章" tap to see anything beyond the one chapter ahead and never letting you
    /// scroll backward at all -- confirmed against Legado_Max's `ReadBook` that it keeps a symmetric
    /// 3-chapter window (`prevTextChapter`/`curTextChapter`/`nextTextChapter`) resident at all times,
    /// not just one chapter ahead. See `commitToPrevChapterPreview` for how crossing into this
    /// chapter promotes it to current (a pure pointer-shuffle, no refetch -- the chapter that was
    /// "current" a moment ago becomes the new `nextChapterPreview` for free, exactly mirroring
    /// `ReadBook.moveToPrevChapter`'s `nextTextChapter = curTextChapter; curTextChapter = prevTextChapter`).
    @State private var prevChapterPreview: AdjacentChapterPreview?
    /// Set right before a seamless preview-commit changes `currentIndex` -- consumed by `load()` (see
    /// its own doc comment) so `.task(id:)` firing from that same `currentIndex` change doesn't
    /// redundantly re-fetch content that's already sitting on screen, which would also flash the
    /// loading spinner over it.
    @State private var justCommittedFromPreview = false
    /// Same idea as `justCommittedFromPreview` but consumed by `.onChange(of: currentIndex)` instead
    /// of `load()` -- kept as its own separate flag rather than reusing `justCommittedFromPreview`
    /// because there's no guaranteed ordering between `.task(id:)` (which resets that one, inside
    /// `load()`) and `.onChange(of:)` both firing off the same `currentIndex` mutation, and a rapid
    /// second navigation could plausibly land before the first one's `load()` task gets a chance to
    /// run at all. This flag is consumed synchronously, in `.onChange(of: currentIndex)` itself, so
    /// it can never be stale by the time the *next* `currentIndex` change reads it.
    @State private var isSeamlessChapterTransition = false
    /// Set right before `advanceReadAloudToNextChapter` commits a chapter change on read-aloud's own
    /// behalf -- `.onChange(of: currentIndex)` normally stops read-aloud on *any* chapter change
    /// (manual navigation while listening would desync speech from what's on screen, since a
    /// controller's `paragraphs` array is a snapshot taken at `start()`, not dynamically linked to
    /// `text`), but that exact same chapter change is what read-aloud crossing into the next chapter
    /// *is* here -- stopping it would undo the continuation `advanceReadAloudToNextChapter` just
    /// started. Consumed synchronously in `.onChange(of: currentIndex)`, same pattern as
    /// `isSeamlessChapterTransition`.
    @State private var isReadAloudAdvancing = false

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
        bookTitle: String, bookAuthor: String? = nil, resumeCharacterOffset: Int = 0
    ) {
        self._source = State(initialValue: source)
        self._bookUrl = State(initialValue: bookUrl)
        self._tocUrl = State(initialValue: tocUrl)
        self._chapters = State(initialValue: chapters)
        self._bookTitle = State(initialValue: bookTitle)
        self._bookAuthor = State(initialValue: bookAuthor)
        self._currentIndex = State(initialValue: currentIndex)
        self._pendingResumeCharacterOffset = State(initialValue: resumeCharacterOffset > 0 ? resumeCharacterOffset : nil)
    }

    private var chapter: BookChapter { chapters[currentIndex] }
    private var paragraphs: [String] { text.components(separatedBy: "\n") }

    /// Real usage feedback, with a reference screenshot, pointed at a bottom-left "10/10" indicator
    /// showing which page of the current chapter you're on -- paginated mode already had this via
    /// `pagedPageProgress`, but `.scroll` mode showed only the chapter number, nothing about position
    /// *within* it, even though `pageLayout`/`currentPageIndexInChapter` (added for real progress
    /// tracking, see their own doc comments) already carry exactly that information.
    private var chapterProgressText: String {
        let chapterPart = "第 \(currentIndex + 1) / \(chapters.count) 章"
        if pageTurnStyle.isPaginated, let pagedPageProgress {
            return "\(chapterPart) · 第 \(pagedPageProgress.current) / \(pagedPageProgress.total) 页 · \(wholeBookProgressText)"
        }
        if let pageLayout, !pageLayout.pages.isEmpty {
            return "\(chapterPart) · 第 \(currentPageIndexInChapter + 1) / \(pageLayout.pages.count) 页 · \(wholeBookProgressText)"
        }
        return "\(chapterPart) · \(wholeBookProgressText)"
    }

    /// Whole-book reading percentage -- confirmed against Legado_Max's own `TextPage.readProgress`
    /// (`TextPage.kt:245-259`): `chapterIndex/chapterSize + (1/chapterSize)*(pageIndex+1)/pageSize`,
    /// one decimal place, with the same "never actually show 100.0% unless this really is the very
    /// last page of the very last chapter" clamp -- rounding tipping the number over to "100%" a
    /// page or two early reads as a bug once you notice it, same as it would in Legado.
    private var wholeBookProgressText: String {
        let chapterSize = chapters.count
        guard chapterSize > 0 else { return "0.0%" }
        let pageIndex: Int
        let pageSize: Int
        if pageTurnStyle.isPaginated, let pagedPageProgress {
            pageIndex = pagedPageProgress.current - 1
            pageSize = pagedPageProgress.total
        } else if let pageLayout, !pageLayout.pages.isEmpty {
            pageIndex = currentPageIndexInChapter
            pageSize = pageLayout.pages.count
        } else {
            pageIndex = 0
            pageSize = 0
        }
        guard pageSize > 0 else {
            return String(format: "%.1f%%", Double(currentIndex + 1) / Double(chapterSize) * 100)
        }
        let percent = Double(currentIndex) / Double(chapterSize)
            + (1 / Double(chapterSize)) * Double(pageIndex + 1) / Double(pageSize)
        let formatted = String(format: "%.1f%%", percent * 100)
        let isTrulyLast = currentIndex + 1 == chapterSize && pageIndex + 1 == pageSize
        return (formatted == "100.0%" && !isTrulyLast) ? "99.9%" : formatted
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

    /// Drives the `.chapter` progress-bar mode's seekbar -- same live-drag-position pattern as
    /// `pageSeekBinding`, just tracking `currentIndex` (whole book) instead of `pagedPageProgress`
    /// (one chapter).
    private var chapterSeekBinding: Binding<Double> {
        Binding(
            get: { chapterSeekDragValue ?? Double(currentIndex) },
            set: { chapterSeekDragValue = $0 }
        )
    }

    // `showsChapterSeekbar`/`showsPageSeekbar` and `chapterSeekbar`/`pageSeekbar` below are split out
    // of what used to be one `if progressBarBehavior == .chapter, chapters.count > 1 { ... } else if
    // progressBarBehavior == .page, pageTurnStyle.isPaginated, let pagedPageProgress, ... { ... }
    // else { ... }` directly inside the seekbar `HStack` -- that compiled locally but CI's real
    // `xcodebuild` (Release, whole-module optimization, a much stricter type-checker budget than
    // Windows `swift build` ever exercises on this cross-platform-only package) failed with "the
    // compiler is unable to type-check this expression in reasonable time": a multi-condition
    // `if`/`else if` mixing booleans and `let` bindings, each branch holding a `Slider` with its own
    // multi-line trailing closure, is a well-known trigger for that -- splitting the condition and
    // each branch's view into their own separately-typed properties is the standard fix, since it
    // gives the type-checker much smaller expressions to solve one at a time instead of one giant one.
    private var showsChapterSeekbar: Bool {
        progressBarBehavior == .chapter && chapters.count > 1
    }

    private var showsPageSeekbar: Bool {
        guard progressBarBehavior == .page, pageTurnStyle.isPaginated, let pagedPageProgress else { return false }
        return pagedPageProgress.total > 1
    }

    /// Matches Legado's real "chapter" mode: jumps only commit on release (`requestChapterJump`),
    /// gated behind a one-time-per-session confirmation -- see that function's doc comment.
    private var chapterSeekbar: some View {
        Slider(
            value: chapterSeekBinding, in: 0...Double(chapters.count - 1), step: 1,
            onEditingChanged: { isEditing in
                if !isEditing {
                    if let chapterSeekDragValue { requestChapterJump(to: Int(chapterSeekDragValue)) }
                    chapterSeekDragValue = nil
                }
            }
        )
    }

    private var pageSeekbar: some View {
        Slider(
            value: pageSeekBinding, in: 0...Double((pagedPageProgress?.total ?? 1) - 1), step: 1,
            onEditingChanged: { isEditing in
                if !isEditing {
                    if let pageSeekDragValue { pageJumpRequest = Int(pageSeekDragValue) }
                    pageSeekDragValue = nil
                }
            }
        )
    }

    /// Matches Legado's real "chapter" progress-bar mode (`ReadMenu.kt`'s `onStopTrackingTouch`):
    /// a chapter jump is a much bigger, harder-to-undo action than a within-chapter page jump, so
    /// the *first* one in a reading session asks for confirmation; once confirmed,
    /// `hasConfirmedChapterJumpThisSession` skips the prompt for the rest of this reader instance's
    /// lifetime, exactly like Legado's own `confirmSkipToChapter` flag.
    private func requestChapterJump(to index: Int) {
        guard chapters.indices.contains(index), index != currentIndex else { return }
        if hasConfirmedChapterJumpThisSession {
            goTo(index)
        } else {
            pendingChapterJumpIndex = index
        }
    }

    // `body`'s modifier chain is split into `stage1`/`stage2`/(the final `return`) purely to keep CI's
    // real `xcodebuild` (Release, whole-module optimization) type-checker from timing out on it as
    // one giant expression -- confirmed to actually happen this session ("the compiler is unable to
    // type-check this expression in reasonable time"), and Windows `swift build` can't reproduce or
    // catch it since it only ever compiles the cross-platform package, never this app target. Each
    // stage gets its own independently-inferred `some View` type instead of one combined one; no
    // modifier's content or order changes at all, this is a pure compile-time-cost split.
    var body: some View {
        let stage1 = Group {
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
                scrollModeBody()
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
                            Menu {
                                if readAloudSleepTimerRemainingSeconds != nil {
                                    Button("关闭定时", role: .destructive) { cancelReadAloudSleepTimer() }
                                }
                                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                                    Button("\(minutes) 分钟后暂停") { startReadAloudSleepTimer(minutes: minutes) }
                                }
                            } label: {
                                if let remaining = readAloudSleepTimerRemainingSeconds {
                                    Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                                        .font(.caption)
                                } else {
                                    Image(systemName: "moon.zzz")
                                }
                            }
                        }
                        .font(.title3)
                    }

                    // Chapter-progress row -- prev/next chapter text flanking a real draggable
                    // seekbar, matching the reference app's own prominent progress bar in this exact
                    // position. Which of the two `ProgressBarBehavior` modes actually gets a working
                    // slider here depends on `pageTurnStyle`: `.page` mode's slider needs
                    // `pagedPageProgress` (only paginated styles produce that -- `.scroll` mode
                    // tracks a real page position too via `currentPageIndexInChapter`, but wiring a
                    // seekbar to it, jump-to-page without a smooth scroll through what's skipped, is
                    // a separate feature this doesn't attempt); `.chapter` mode only needs
                    // `chapters.count`, so it works in both page-turn styles.
                    HStack(spacing: 4) {
                        // `.padding` + `.contentShape(Rectangle())` so the tappable area is a real
                        // ~44pt-tall button, not just the tiny `.caption`-sized text glyphs -- same
                        // "too small to reliably tap" feedback as the top bar's icons.
                        Button("上一章") { goToPreviousChapter() }
                            .font(.caption)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                            .disabled(currentIndex <= 0)

                        if showsChapterSeekbar {
                            chapterSeekbar
                        } else if showsPageSeekbar {
                            pageSeekbar
                        } else {
                            Text(chapterProgressText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }

                        Button("下一章") { goToNextChapter() }
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
                        inlineSettingsPanel()
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
        let stage2 = stage1
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
                            paragraphMenuText = ""
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
                                toggleAutoScroll()
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
                            paragraphMenuText = ""
                            isShowingDictLookup = true
                        } label: {
                            Label("查词", systemImage: "character.book.closed")
                        }
                        Button {
                            paragraphMenuText = ""
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
        return stage2
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
                    currentBookSourceUrl: source.bookSourceUrl, bookName: bookTitle, bookAuthor: bookAuthor
                ) { newSource, match in
                    await switchSource(to: newSource, match: match)
                }
            }
        }
        .sheet(isPresented: $isShowingChapterSourceSwitch) {
            NavigationStack {
                ChangeSourceView(
                    currentBookSourceUrl: source.bookSourceUrl, bookName: bookTitle, bookAuthor: bookAuthor
                ) { newSource, match in
                    await switchChapterSource(to: newSource, match: match)
                }
            }
        }
        .sheet(item: $chapterSourcePicker) { context in
            ChapterSourcePickerView(context: context) { chosen in
                await commitChapterSourcePick(
                    source: context.source, chapters: context.chapters, originalIndex: context.originalIndex, chosen: chosen
                )
            }
        }
        .overlay {
            ReaderTocDrawerView(
                isPresented: $isShowingToc,
                chapters: chapters.map {
                    ReaderTocDrawerView.ChapterItem(id: $0.index, title: $0.title, isVolume: $0.isVolume, isVip: $0.isVip, isPay: $0.isPay)
                },
                currentIndex: currentIndex,
                bookIdentifier: bookUrl,
                bookmarkStore: env.bookmarkStore,
                matchedReplaceRules: matchedReplaceRules,
                searchScopeNotice: "仅搜索已下载缓存的章节，未下载的章节不在搜索范围内",
                loadChaptersForSearch: loadCachedChaptersForSearch,
                loadDownloadedIndices: { (try? await env.chapterCacheStore.downloadedIndices(bookUrl: bookUrl)) ?? [] },
                onSelectChapter: { index, offset in
                    if let offset, offset > 0 { pendingResumeCharacterOffset = offset }
                    goTo(index)
                }
            )
        }
        .sheet(isPresented: $isShowingContentSearch) {
            ChapterContentSearchView(
                loadChapters: { await loadCachedChaptersForSearch() },
                onSelect: { index in goTo(index) },
                scopeNotice: "仅搜索已下载缓存的章节，未下载的章节不在搜索范围内",
                initialKeyword: paragraphMenuText
            )
        }
        .sheet(isPresented: $isShowingAISummary) {
            AIChapterSummaryView(chapterTitle: chapter.title, chapterText: text)
        }
        .sheet(isPresented: $isShowingDictLookup) {
            DictLookupView(initialWord: paragraphMenuText)
        }
        .sheet(isPresented: $isShowingContentEdit) {
            ChapterEditView(source: source, chapter: chapter, bookUrl: bookUrl, currentText: text) { edited in
                text = edited
            }
        }
        .sheet(isPresented: $isShowingWebSearch) {
            WebSearchPanelView(initialQuery: paragraphMenuText)
        }
        .sheet(isPresented: $isShowingReplaceRuleSeed) {
            // `rule:` non-nil pre-fills the form with the pressed paragraph's text as the match
            // pattern (as plain text, not regex -- an arbitrary paragraph excerpt is almost never
            // meant literally as a regex) -- this rule was never actually persisted, so `onSave`
            // still goes through `.add`, exactly like `ReplaceRuleListView`'s own "新建" flow.
            // Accepted, minor cosmetic mismatch: `ReplaceRuleEditView` shows "编辑规则" as its title
            // for any non-nil `rule`, including this seeded-but-unsaved one.
            ReplaceRuleEditView(rule: ReplaceRule(name: "", pattern: paragraphMenuText, isRegex: false)) { newRule in
                Task { try? await env.replaceRuleStore.add(newRule) }
            }
        }
        .sheet(isPresented: $isShowingParagraphShareSheet) {
            ShareSheet(items: [paragraphMenuText])
        }
        .alert(
            "章节跳转确认", isPresented: Binding(get: { pendingChapterJumpIndex != nil }, set: { if !$0 { pendingChapterJumpIndex = nil } })
        ) {
            Button("取消", role: .cancel) { pendingChapterJumpIndex = nil }
            Button("确定") {
                if let index = pendingChapterJumpIndex {
                    hasConfirmedChapterJumpThisSession = true
                    goTo(index)
                }
                pendingChapterJumpIndex = nil
            }
        } message: {
            Text("确定要跳转章节吗？")
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepScreenOn
            startVolumeButtonPagingIfEnabled()
            // Confirmed against Legado_Max's own `BaseReadAloudService.nextChapter()` that real
            // read-aloud crosses chapter boundaries automatically -- see `advanceReadAloudToNextChapter`
            // and `ReadAloudController.onReachedEnd`'s own doc comments for the full picture.
            // Reassigning on every `.onAppear` is harmless (idempotent); simplest place to wire this
            // up given these are `@StateObject`s constructed before `self` exists to close over.
            readAloud.onReachedEnd = { advanceReadAloudToNextChapter() }
            httpReadAloud.onReachedEnd = { advanceReadAloudToNextChapter() }
            OrientationLock.mask = screenOrientationLock.mask
            OrientationLock.applyToActiveScene()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            stopReadAloud()
            stopAutoScroll()
            stopAutoPage()
            volumeButtonController.stop()
            pendingPageStepTask?.cancel()
            pendingPageStepTask = nil
            saveReadingProgress()
            // Matches Legado_Max's `BaseReadBookActivity` only ever calling `setOrientation()` on
            // itself -- leaving the reader hands orientation control back to whatever the rest of the
            // app (书架/发现/我的) uses, rather than the lock leaking into every other screen.
            OrientationLock.mask = .allButUpsideDown
            OrientationLock.applyToActiveScene()
        }
        .onChange(of: screenOrientationLock) { _, newValue in
            OrientationLock.mask = newValue.mask
            OrientationLock.applyToActiveScene()
        }
        // `.onDisappear` alone only covers leaving the reader *within* the app (back button, TOC nav,
        // etc.) -- it never fires for backgrounding the app itself (home button/app switch/incoming
        // call), which SwiftUI treats as the view staying mounted, just not visible. Real usage
        // feedback: reading to the middle of a chapter then leaving the app (not tapping back) and
        // reopening it later landed back on the chapter's first page -- the only other save path was
        // the 60s `scheduleTimer` tick, so anyone backgrounding sooner than that lost their exact spot
        // even though the chapter-level position was remembered fine. Any transition away from
        // `.active` (backgrounding or the app being interrupted) now saves immediately too.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                saveReadingProgress()
            }
        }
        .onChange(of: keepScreenOn) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
        .onChange(of: volumeKeyPageEnabled) { _, isEnabled in
            if isEnabled {
                startVolumeButtonPagingIfEnabled()
            } else {
                volumeButtonController.stop()
            }
        }
        .onChange(of: readAloudRate) { _, newValue in
            // AVSpeechSynthesizer can't change an utterance's rate mid-speech -- this takes effect
            // starting with the next paragraph, not a jarring restart of the current one.
            readAloud.setRate(Float(newValue))
        }
        // `.scroll` mode's own equivalent of `PagedChapterReaderView`'s `.onChange(of:
        // readAloudParagraphIndex)` (which already does exactly this for its own 4 paginated styles)
        // -- confirmed against Legado_Max's `ReadBookActivity.applyReadAloudProgress` that real
        // read-aloud drives the visible page/scroll position to follow along as it speaks, not just
        // highlight whatever already happens to be on screen. Without this, `pageBlock`'s highlight
        // (`readAloudCurrentParagraphIndex`) would silently scroll off-screen the moment speech moved
        // past whatever page was showing when playback started, with nothing bringing it back.
        .onChange(of: readAloudCurrentParagraphIndex) { _, newValue in
            guard isReadAloudSpeaking, !pageTurnStyle.isPaginated, let pageLayout else { return }
            let targetPage = pageLayout.pageIndex(forParagraphIndex: newValue)
            guard pageLayout.pages.indices.contains(targetPage), targetPage != currentPageIndexInChapter else { return }
            currentPageIndexInChapter = targetPage
            dragOffset = 0
            saveReadingProgress()
        }
        .onChange(of: currentIndex) { _, _ in
            // Chapter navigation invalidates whatever was being read from the old chapter's text --
            // a controller's `paragraphs` array is a snapshot taken at `start()`, not dynamically
            // linked to `text`, so continuing to speak it after `text` moved on to a different
            // chapter would desync speech from what's on screen. `isReadAloudAdvancing` is the one
            // exception: that flag means read-aloud itself is *why* `currentIndex` just changed
            // (`advanceReadAloudToNextChapter` already started the next chapter's speech), so
            // stopping here would immediately undo the continuation it just began.
            if isReadAloudAdvancing {
                isReadAloudAdvancing = false
            } else {
                stopReadAloud()
            }
            // Same reasoning as read-aloud: an auto-scroll loop mid-flight is walking pages that
            // belonged to the chapter that just got replaced, so it has to stop too rather than
            // silently continuing to scroll a chapter that no longer matches its state.
            stopAutoScroll()
            pagedPageProgress = nil
            // A seamless preview-commit (see `commitToNextChapterPreview`/`commitToPrevChapterPreview`)
            // already set `dragOffset`/`currentPageIndexInChapter` correctly itself (that's the whole
            // point of committing seamlessly -- the drag that caused the crossing carries straight
            // through with no reset at all). Only an actual hard jump (`goTo`: TOC/search/bookmark, a
            // 下一章/上一章 tap when no preview was ready, resuming a book on launch) needs the reading
            // position reset to the top of the newly-loaded chapter -- `repaginateForScroll` sets
            // `currentPageIndexInChapter` itself once that chapter's real pagination lands, so this
            // only needs to clear the *drag* state so nothing carries over from whatever chapter was
            // showing a moment ago.
            if isSeamlessChapterTransition {
                isSeamlessChapterTransition = false
            } else {
                pendingPageStepTask?.cancel()
                pendingPageStepTask = nil
                dragOffset = 0
            }
        }
    }

    /// Volume Up steps back, Volume Down steps forward -- Legado's own convention wasn't confirmed
    /// during research (its volume-key handling just maps to the same "previous/next" actions a
    /// paginated reader already has, without a documented up/down convention to match exactly), so
    /// this picked the mapping that reads as intuitive for a reading gesture (down = further into
    /// the content) rather than copying an unverified assumption.
    private func startVolumeButtonPagingIfEnabled() {
        guard volumeKeyPageEnabled else { return }
        guard let window = Self.keyWindow() else { return }
        volumeButtonController.onVolumeUp = { handleVolumeKeyTurn(direction: -1) }
        volumeButtonController.onVolumeDown = { handleVolumeKeyTurn(direction: 1) }
        volumeButtonController.start(in: window)
    }

    private func handleVolumeKeyTurn(direction: Int) {
        guard !pageTurnStyle.isPaginated else {
            pageTurnRequest = direction > 0 ? .next : .previous
            return
        }
        animatedPageStep(direction: direction)
    }

    private static func keyWindow() -> UIView? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    /// `.last` is honored by both paginated mode (see `PagedChapterReaderView`'s doc comment) and
    /// `.scroll` mode (`repaginateForScroll` lands on the new chapter's last page instead of its
    /// first) -- for continuing to page backward past a chapter's first page, matching where a
    /// physical book would be; every other caller (explicit chapter-list/search/bookmark jumps, and
    /// `goToNextChapter`/`goToPreviousChapter`'s own fallback when no preview is ready yet) wants the
    /// default `.first`. A full reload: fetches fresh content over the network/cache and re-paginates
    /// from scratch, unlike the seamless preview-commit `goToNextChapter`/`goToPreviousChapter`
    /// prefer when possible.
    private func goTo(_ index: Int, anchor: PageAnchor = .first) {
        guard chapters.indices.contains(index) else { return }
        // An explicit jump (buttons/TOC/search/bookmark) invalidates whatever was queued as "the
        // chapter before/after wherever I currently am" -- if either is stale, `loadPrevChapterPreview`/
        // `loadNextChapterPreview` (called again at the end of the resulting `load()`) fetch the
        // right ones for the new position instead.
        prevChapterPreview = nil
        nextChapterPreview = nil
        pageAnchor = anchor
        currentIndex = index
    }

    /// Prefers a seamless commit over `goTo`'s full reload for the toolbar's 下一章 button and the
    /// matching tap zone -- `nextChapterPreview` is usually already sitting there fully fetched and
    /// paginated (prefetched the moment the current chapter loaded), so committing it directly avoids
    /// a wasted refetch of content the reader already has. Falls back to `goTo` only when no ready
    /// preview exists yet (tapping faster than prefetch keeps up, paginated mode, or this is the
    /// last chapter).
    private func goToNextChapter() {
        if let preview = nextChapterPreview, preview.pageLayout != nil {
            commitToNextChapterPreview(preview, arrivingAtPageIndex: 0)
        } else {
            goTo(currentIndex + 1)
        }
    }

    /// Exact mirror of `goToNextChapter`, facing backward, for the toolbar's 上一章 button and its
    /// tap zone.
    private func goToPreviousChapter() {
        if let preview = prevChapterPreview, preview.pageLayout != nil {
            commitToPrevChapterPreview(preview, arrivingAtPageIndex: 0)
        } else {
            goTo(currentIndex - 1)
        }
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
        } else {
            beginReadAloud(startIndex: 0)
        }
    }

    /// Shared by `startOrStopReadAloud` (always paragraph 0) and the long-press paragraph menu's
    /// "朗读，从这里开始" action (`chunk.paragraphIndex`) -- extracted so the engine-selection
    /// branching (system `AVSpeechSynthesizer` vs a configured `HttpTTSEngine`) only lives in one
    /// place.
    private func beginReadAloud(startIndex: Int) {
        if isUsingHttpTTS, let engine = httpTTSEngines.first(where: { $0.id == selectedHttpTTSEngineID }) {
            httpReadAloud.start(
                paragraphs: paragraphs, engine: engine, cache: env.httpTTSCache,
                bookTitle: bookTitle, chapterTitle: chapter.title, startIndex: startIndex
            )
        } else {
            readAloud.setRate(Float(readAloudRate))
            readAloud.start(paragraphs: paragraphs, bookTitle: bookTitle, chapterTitle: chapter.title, startIndex: startIndex)
        }
    }

    private func stopReadAloud() {
        readAloud.stop()
        httpReadAloud.stop()
    }

    /// Wired to `readAloud.onReachedEnd`/`httpReadAloud.onReachedEnd` in `.onAppear` -- fires when
    /// speech naturally runs out of the current chapter's paragraphs. Confirmed against Legado_Max's
    /// own `BaseReadAloudService.nextChapter()` that real read-aloud crosses chapter boundaries
    /// automatically instead of stopping at every one; without this, hands-free listening across a
    /// multi-chapter session meant manually restarting playback after every single chapter.
    ///
    /// Reuses `nextChapterPreview` exactly like `goToNextChapter`'s seamless path, but -- unlike that
    /// one -- doesn't require `pageLayout` to already be populated: starting the next chapter's
    /// speech only needs its raw purified `text` (which `loadNextChapterPreview` always fetches
    /// regardless of `pageTurnStyle`), not scroll-mode pagination, so this works the same way in
    /// paginated styles too. `isReadAloudAdvancing` (see its own doc comment) stops
    /// `.onChange(of: currentIndex)` from immediately undoing this by stopping the speech it just
    /// started.
    private func advanceReadAloudToNextChapter() {
        guard let preview = nextChapterPreview else {
            // Nothing prefetched yet -- either this is genuinely the last chapter, or prefetch
            // hasn't landed. Either way, the controller deliberately doesn't call `stop()` itself
            // once `onReachedEnd` is set (see its own doc comment), so this has to.
            stopReadAloud()
            return
        }
        isReadAloudAdvancing = true
        let wasUsingHttpTTS = isUsingHttpTTS
        let httpEngine = httpTTSEngines.first(where: { $0.id == selectedHttpTTSEngineID })
        commitToNextChapterPreview(preview, arrivingAtPageIndex: 0)
        let newParagraphs = preview.text.components(separatedBy: "\n")
        if wasUsingHttpTTS, let httpEngine {
            httpReadAloud.start(
                paragraphs: newParagraphs, engine: httpEngine, cache: env.httpTTSCache,
                bookTitle: bookTitle, chapterTitle: preview.title
            )
        } else {
            readAloud.setRate(Float(readAloudRate))
            readAloud.start(paragraphs: newParagraphs, bookTitle: bookTitle, chapterTitle: preview.title)
        }
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

    /// Real gap found comparing against Legado: read-aloud had no sleep timer at all (only the
    /// audiobook player did) -- `readAloud`/`httpReadAloud` both now implement the same
    /// `startSleepTimer`/`cancelSleepTimer` pair `AudiobookPlayerController` already had; these three
    /// just dispatch to whichever of the two is actually active, same pattern as
    /// `toggleReadAloudPause`/`readAloudPreviousParagraph`/`readAloudNextParagraph` above.
    private var readAloudSleepTimerRemainingSeconds: Int? {
        isUsingHttpTTS ? httpReadAloud.sleepTimerRemainingSeconds : readAloud.sleepTimerRemainingSeconds
    }

    private func startReadAloudSleepTimer(minutes: Int) {
        if isUsingHttpTTS { httpReadAloud.startSleepTimer(minutes: minutes) } else { readAloud.startSleepTimer(minutes: minutes) }
    }

    private func cancelReadAloudSleepTimer() {
        if isUsingHttpTTS { httpReadAloud.cancelSleepTimer() } else { readAloud.cancelSleepTimer() }
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
    private func inlineSettingsPanel() -> some View {
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
                        toggleAutoScroll()
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
    /// scroll content's own sizing a few lines up in `body`.
    private func handleTap(at location: CGPoint) {
        let screenSize = UIScreen.main.bounds.size
        let col = min(2, max(0, Int(location.x / (screenSize.width / 3))))
        let row = min(2, max(0, Int(location.y / (screenSize.height / 3))))
        perform(ReaderTapZoneGrid.decode(tapZoneGridRaw).action(row: row, col: col))
    }

    private func perform(_ action: ReaderTapZoneAction) {
        switch action {
        case .none:
            break
        case .toggleChrome:
            isChromeVisible.toggle()
        case .previousChapter:
            goToPreviousChapter()
        case .nextChapter:
            goToNextChapter()
        case .openToc:
            isShowingToc = true
        case .nextPage:
            animatedPageStep(direction: 1)
        case .previousPage:
            animatedPageStep(direction: -1)
        case .exitReader:
            dismiss()
        case .readAloudPreviousParagraph:
            readAloudPreviousParagraph()
        case .readAloudNextParagraph:
            readAloudNextParagraph()
        case .toggleReadAloudPauseResume:
            toggleReadAloudPause()
        case .toggleBookmark:
            Task { await toggleBookmark() }
        case .editContent:
            isShowingContentEdit = true
        case .togglePurification:
            isShowingReplaceRules = true
        case .contentSearch:
            paragraphMenuText = ""
            isShowingContentSearch = true
        }
    }

    private func toggleAutoScroll() {
        if isAutoScrolling {
            stopAutoScroll()
        } else {
            startAutoScroll()
        }
    }

    /// Advances one real page per `autoScrollInterval` seconds, hands-free, via the same animated
    /// slide `animatedPageStep` gives a volume-key/tap-zone turn -- this used to be a paragraph-step
    /// approximation scrolling to a raw (and, after the page-based rewrite, nonexistent) `Int`
    /// content id, silently a no-op; real page tracking now makes a real per-page auto-advance
    /// possible instead. Crosses chapter boundaries automatically (via `animatedPageStep` →
    /// `commitPageOffset` → `stepToNextPage`'s own existing chapter-crossing) and only stops at the
    /// genuine end of the book -- confirmed against Legado_Max's own `AutoPager`/`TextPageFactory.
    /// moveToNext` that real hands-free auto-reading runs unattended straight through chapter
    /// boundaries, not just within one chapter. This reader used to deliberately stop at each
    /// chapter's own last page instead, over-cautiously conflating "don't skip the user past a
    /// boundary mid-drag" (a real concern for the *live-drag* crossing machinery, which is driven by
    /// the user's own finger) with auto-reading, which has no such risk -- there's no finger to skip
    /// out from under.
    private func startAutoScroll() {
        autoScrollTask?.cancel()
        isAutoScrolling = true
        autoScrollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(max(autoScrollInterval, 0.5) * 1_000_000_000))
                guard !Task.isCancelled else { break }
                guard canAutoAdvanceFurther() else { break }
                animatedPageStep(direction: 1)
            }
            if !Task.isCancelled {
                isAutoScrolling = false
            }
        }
    }

    /// Whether there's anywhere further for `startAutoScroll` to advance to -- another page left in
    /// the current chapter, or a next chapter already prefetched and paginated and ready to cross
    /// into (mirrors `stepToNextPage`'s own two-branch check, without actually committing the step).
    /// `false` genuinely means "the end of the book" *or* "the next chapter hasn't finished
    /// prefetching yet" -- the latter is rare in practice (auto-scroll's multi-second interval gives
    /// `prefetchUpcomingChapters`/`loadNextChapterPreview` ample time to land between steps) and just
    /// means auto-scroll pauses at that chapter's last page rather than getting stuck retrying.
    private func canAutoAdvanceFurther() -> Bool {
        if let pageLayout, currentPageIndexInChapter < pageLayout.pages.count - 1 { return true }
        return nextChapterPreview?.pageLayout != nil
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
    /// else -- fetches the alternate source's real table of contents, auto-matches this chapter's
    /// title within it (falling back to the same index if no title matches) purely to pre-highlight
    /// a sensible default, then hands off to `ChapterSourcePickerView` for the user to confirm or pick
    /// a different chapter themselves. Real gap found comparing against Legado's own
    /// `ChangeChapterSourceDialog`: this used to auto-commit the matched chapter with no way to see
    /// the real TOC or override a wrong guess (different chapter splitting/numbering between sources
    /// is common enough that a title match can legitimately land on the wrong chapter).
    private func switchChapterSource(to newSource: BookSource, match: SearchResult) async {
        let originalIndex = chapter.index
        let originalTitle = chapter.title
        isLoading = true
        do {
            let bookInfo = try await BookInfoService.fetchBookInfo(source: newSource, bookURL: match.bookUrl, httpClient: env.httpClient)
            let altChapters = try await TocService.fetchChapterList(source: newSource, tocURL: bookInfo.tocUrl, httpClient: env.httpClient)
            guard !altChapters.isEmpty else {
                errorMessage = "对方书源没有可用章节"
                isLoading = false
                return
            }
            let byTitle = altChapters.first(where: { $0.title == originalTitle })
            let fallback: BookChapter? = altChapters.indices.contains(originalIndex) ? altChapters[originalIndex] : altChapters.first
            chapterSourcePicker = ChapterSourcePickerContext(
                source: newSource, chapters: altChapters, highlightedIndex: (byTitle ?? fallback)?.index,
                originalIndex: originalIndex
            )
        } catch {
            errorMessage = "本章换源失败: \(error)"
        }
        isLoading = false
    }

    /// The tail half of the old `switchChapterSource` -- fetches the user's actually-chosen chapter's
    /// content and saves it into `chapterCacheStore` under the *original* book/index. `load()`'s
    /// existing cache-first lookup then picks it up transparently, exactly as if the chapter had been
    /// downloaded normally, so the fix persists across relaunches without any new loading path.
    private func commitChapterSourcePick(source: BookSource, chapters: [BookChapter], originalIndex: Int, chosen: BookChapter) async {
        do {
            let content = try await ContentService.fetchContent(
                source: source, chapter: chosen, httpClient: env.httpClient,
                nextChapterUrl: chapters.indices.contains(chosen.index + 1) ? chapters[chosen.index + 1].url : nil
            )
            try await env.chapterCacheStore.save(bookUrl: bookUrl, index: originalIndex, content: content)
        } catch {
            errorMessage = "本章换源失败: \(error)"
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
            if let rule = segment.rule {
                return partial + Text.highlighted(segment.text, rule: rule)
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
    ///
    /// Strips the paragraph's own leading whitespace first -- real usage feedback (a second round,
    /// after this Stepper already existed): dragging it down still left an oddly-large indent for
    /// books from a source whose `ruleContent.replaceRegex` *also* adds its own leading full-width
    /// spaces (`ContentService.applyReplaceRegex` -- a real, common, still-supported convention, not
    /// a bug there), stacking with this setting's own instead of replacing it. Stripping first makes
    /// this Stepper the *one* true source of the visible indent amount regardless of what a source
    /// already baked in, rather than only ever being able to add on top of an unknown amount. Purely
    /// a rendering-time normalization -- the underlying `text`/`paragraphs`/`ChapterPageLayout`
    /// character offsets that bookmarks/read-aloud/highlighting all key off of are untouched, so nothing
    /// downstream of pagination needs to change to stay consistent with this.
    private func indentedText(_ paragraph: String) -> Text {
        let normalized = String(paragraph.drop(while: \.isWhitespace))
        guard paragraphIndent > 0 else { return highlightedText(normalized) }
        return Text(String(repeating: "　", count: paragraphIndent)) + highlightedText(normalized)
    }

    /// Bold, centered chapter title shown inline in the reading area itself -- real usage feedback,
    /// with a reference screenshot, wanted this for *every* chapter section (including the very
    /// first/current one, which previously relied on the top bar alone) and wanted the gap before it
    /// to read as genuine blank space, not a drawn rule -- a plain `Divider()` line was tried first
    /// and reads as "a UI element," not "empty space between chapters," so this is just padding.
    private func chapterHeading(_ title: String) -> some View {
        highlightedTitleText(title)
            .font(.title3.bold())
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
            .padding(.bottom, 12)
            .padding(.horizontal, 4)
    }

    /// Same `HighlightRuleApplier` pipeline `highlightedText` runs body paragraphs through, just with
    /// `isTitle: true` -- previously this heading never ran highlight rules at all, so a rule scoped
    /// to "仅标题" had nowhere in the reading UI it could ever actually show up.
    private func highlightedTitleText(_ title: String) -> Text {
        let segments = HighlightRuleApplier.segments(highlightRules, in: title, isTitle: true)
        return segments.reduce(Text("")) { partial, segment in
            if let rule = segment.rule {
                return partial + Text.highlighted(segment.text, rule: rule)
            } else {
                return partial + Text(segment.text).foregroundStyle(theme.textColor(for: colorScheme, customText: Color(hex: customThemeTextHex)))
            }
        }
    }

    /// Real, screen-measured `.scroll` mode rendering, built directly on Legado_Max's own real
    /// mechanism instead of a native `ScrollView` -- confirmed against `ContentTextView`/
    /// `ScrollPageDelegate`/`ReadBook` that Legado's continuous-scroll mode isn't a system scroll
    /// container at all: it composites up to 3 screen-sized `TextPage`s at fixed vertical offsets
    /// from a single pixel value it tracks itself (`pageOffset`), moved directly by raw touch
    /// deltas, and steps `durPageIndex`/`durChapterIndex` by exactly one page/chapter the instant
    /// that offset would exceed one page's height -- there's no separate "detect where the scroll
    /// ended up and decide what that means" step at all. This reader's own `.scroll` mode used to be
    /// a native `ScrollView` plus a SwiftUI preference-key position *detector*; repeated real-device
    /// testing found that "detect after the fact" approach fundamentally racy (chapters failing to
    /// connect, backward-cascade jumps that kept finding new gaps to slip through even after several
    /// rounds of fixes targeting each one) in a way this direct port isn't, because there's no
    /// detection step left to race against -- `dragOffset`/`commitPageOffset` (see their own doc
    /// comments) *are* the state, exactly the way Legado's `pageOffset`/`ContentTextView.scroll` are.
    @ViewBuilder
    private func scrollModeBody() -> some View {
        GeometryReader { geo in
            let contentSize = CGSize(
                width: max(geo.size.width - pageMarginLeading - pageMarginTrailing, 0),
                height: max(geo.size.height - pageMarginTop - pageMarginBottom, 0)
            )
            ZStack(alignment: .topLeading) {
                // Up to 3 stacked slots (previous page / current page / next page, each exactly one
                // screen tall) positioned purely by `dragOffset` -- mirrors Legado_Max's own
                // `ContentTextView.drawPage` compositing up to 3 `TextPage`s at once (simplified to
                // exactly 3, not the extra "plus-one" buffer Legado uses purely to avoid a blank
                // flash on very fast flings). The 3 offsets are always exactly `contentSize.height`
                // apart, so the slots never overlap regardless of `dragOffset`'s value -- no need for
                // per-slot opacity/background the way `PagedChapterReaderView`'s slide/cover
                // animations need (those genuinely stack one page over another mid-transition).
                pageSlot(relativeIndex: -1, size: contentSize)
                    .offset(y: dragOffset - contentSize.height)
                pageSlot(relativeIndex: 0, size: contentSize)
                    .offset(y: dragOffset)
                pageSlot(relativeIndex: 1, size: contentSize)
                    .offset(y: dragOffset + contentSize.height)
            }
            .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .padding(EdgeInsets(top: pageMarginTop, leading: pageMarginLeading, bottom: pageMarginBottom, trailing: pageMarginTrailing))
            // `minimumDistance: 0` (fires from touch-down, not after some slop) plus `coordinateSpace:
            // .global` (so `handleTap`'s screen-bounds zone math keeps working unchanged) -- the same
            // tap-vs-scroll disambiguation this reader already used before this rewrite (`hypot
            // (translation) <= touchSlop` in `.onEnded` below), just now the *only* gesture on this
            // content instead of a `.simultaneousGesture` running alongside a `ScrollView`'s own
            // competing pan recognizer, since there's no `ScrollView` here anymore to compete with.
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        // `value.translation` resets to zero at the start of every new gesture, but
                        // `dragOffset` is meant to persist across separate drags (see its own doc
                        // comment) -- capturing what it already rested at the instant a fresh gesture
                        // begins (its translation is exactly `.zero` on that very first callback,
                        // since `minimumDistance: 0` means this fires immediately on touch-down) is
                        // what lets each subsequent callback add on top of that instead of overwriting
                        // it. A fresh touch-down also grabs control away from any still-settling fling
                        // or animated page-turn from a moment ago, matching how grabbing a real
                        // decelerating scroll view stops it dead rather than fighting your finger.
                        if value.translation == .zero {
                            pendingPageStepTask?.cancel()
                            pendingPageStepTask = nil
                            dragGestureBaseOffset = dragOffset
                        }
                        commitPageOffset(dragGestureBaseOffset + value.translation.height)
                    }
                    .onEnded { value in
                        if hypot(value.translation.width, value.translation.height) <= touchSlop {
                            handleTap(at: value.location)
                            return
                        }
                        // Fling: `predictedEndTranslation` is SwiftUI's own estimate of where this
                        // gesture would have naturally decelerated to (the same estimate UIKit's own
                        // scroll views use) -- mirrors Legado_Max's `ScrollPageDelegate.onAnimStart`
                        // handing the release velocity to a `Scroller` for inertial scrolling, just
                        // built on SwiftUI's equivalent instead of reimplementing velocity tracking
                        // and a deceleration curve from scratch. Clamped to at most one further page
                        // beyond wherever the raw drag already ended (see `settleDrag`'s doc comment
                        // for why) rather than flinging an unbounded distance.
                        let pageHeight = scrollPageSize.height
                        guard pageHeight > 0 else { return }
                        let rawOffset = dragGestureBaseOffset + value.translation.height
                        let predictedOffset = dragGestureBaseOffset + value.predictedEndTranslation.height
                        let target = min(max(predictedOffset, rawOffset - pageHeight), rawOffset + pageHeight)
                        settleDrag(to: target)
                    }
            )
            .task(id: scrollPaginationKey(size: contentSize)) {
                await repaginateForScroll(size: contentSize)
            }
        }
    }

    /// One page's worth of content, sized to fill exactly one screen -- the unit `scrollModeBody`
    /// stacks 3 of at fixed offsets. `resolvedPage(relativeIndex:)` does the actual cross-chapter
    /// lookup; this just turns the result into a view, rendering nothing (not crashing) when that
    /// page doesn't exist yet -- very start/end of the whole book, or a neighboring chapter's
    /// preview genuinely hasn't finished loading. `commitPageOffset` already refuses to scroll past
    /// that boundary, so an empty slot here is only ever visible for a fraction of a drag before it
    /// clamps, not something a user can actually linger on.
    @ViewBuilder
    private func pageSlot(relativeIndex: Int, size: CGSize) -> some View {
        if let resolved = resolvedPage(relativeIndex: relativeIndex) {
            VStack(alignment: .leading, spacing: 0) {
                // Real usage feedback, with a reference screenshot, wanted a chapter's title shown
                // inline the moment its first page comes into view (not just the top bar's own
                // title) -- rendered directly inside this fixed-height slot rather than as its own
                // separate page, so it doesn't need the paginator to reserve space for it; on very
                // large font sizes this can mean a chapter's very first page shows marginally less
                // body text than its other pages, an acceptable trade against the complexity of
                // giving the heading its own slot in the page-index math.
                if resolved.isFirstPageOfChapter {
                    chapterHeading(resolved.chapterTitle)
                }
                pageBlock(resolved.pageIndex, layout: resolved.layout, isCurrentChapter: resolved.isCurrentChapter)
                Spacer(minLength: 0)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        } else {
            Color.clear.frame(width: size.width, height: size.height)
        }
    }

    private struct ResolvedPage {
        let layout: ChapterPageLayout
        let pageIndex: Int
        let chapterTitle: String
        let isFirstPageOfChapter: Bool
        /// Whether this slot's `layout` is `self.pageLayout` (the chapter `text`/`chapter`/
        /// `pageLayout` state already describes) rather than a neighboring `prevChapterPreview`'s/
        /// `nextChapterPreview`'s own pagination. `pageBlock`'s long-press menu needs this: its
        /// "朗读，从这里开始"/"添加书签" actions read `paragraphs`/`chapter`/`pageLayout` directly
        /// (the *current* chapter's state), which would be silently wrong -- attributing a bookmark
        /// to the wrong chapter, or starting read-aloud from an unrelated paragraph index -- if shown
        /// for a chunk that actually belongs to a neighboring chapter's preview slot instead. That
        /// preview sliver is only ever reachable mid-drag near a chapter boundary (see
        /// `scrollModeBody`'s `.clipped()` -- at rest only the current page is visible at all), but
        /// it *is* reachable, not hypothetical.
        let isCurrentChapter: Bool
    }

    /// Looks up which page belongs `relativeIndex` steps from `currentPageIndexInChapter` (-1 =
    /// previous page, 0 = current, +1 = next), crossing into `prevChapterPreview`'s/
    /// `nextChapterPreview`'s own pagination at the current chapter's first/last page exactly like
    /// Legado_Max's own up-to-3-page compositing (`ContentTextView.drawPage`/`TextPageFactory.
    /// relativePage`) does. `nil` when that page doesn't exist (yet, or ever -- start/end of book).
    private func resolvedPage(relativeIndex: Int) -> ResolvedPage? {
        let target = currentPageIndexInChapter + relativeIndex
        if let pageLayout, pageLayout.pages.indices.contains(target) {
            return ResolvedPage(
                layout: pageLayout, pageIndex: target, chapterTitle: chapter.title, isFirstPageOfChapter: target == 0,
                isCurrentChapter: true
            )
        }
        if target < 0, let preview = prevChapterPreview, let layout = preview.pageLayout {
            let idx = layout.pages.count + target
            guard layout.pages.indices.contains(idx) else { return nil }
            return ResolvedPage(
                layout: layout, pageIndex: idx, chapterTitle: preview.title, isFirstPageOfChapter: idx == 0,
                isCurrentChapter: false
            )
        }
        if let pageLayout, target >= pageLayout.pages.count, let preview = nextChapterPreview, let layout = preview.pageLayout {
            let idx = target - pageLayout.pages.count
            guard layout.pages.indices.contains(idx) else { return nil }
            return ResolvedPage(
                layout: layout, pageIndex: idx, chapterTitle: preview.title, isFirstPageOfChapter: idx == 0,
                isCurrentChapter: false
            )
        }
        return nil
    }

    /// Commits a live offset against page/chapter boundaries exactly like Legado_Max's
    /// `ContentTextView.scroll` -- while `newOffset` sits strictly inside `(-pageHeight, pageHeight)`
    /// it's just how far the current page has visually scrolled, nothing else changes. The instant it
    /// would reach or exceed one full page's height in either direction, this steps `currentPageIndexInChapter`
    /// (and, at a chapter's own boundary, the whole prev/cur/next window -- see `stepToNextPage`/
    /// `stepToPreviousPage`) by exactly one and subtracts that page's height back out, so the
    /// *visual* motion stays perfectly continuous across the crossing: there's never a moment where
    /// the screen jumps, freezes, or shows the wrong chapter's content, because the crossing *is*
    /// the state update, not something inferred afterward. Clamps instead of scrolling past content
    /// that doesn't exist yet (start/end of the whole book, or a neighboring chapter's preview
    /// genuinely hasn't loaded).
    private func commitPageOffset(_ newOffset: CGFloat) {
        var offset = newOffset
        let pageHeight = scrollPageSize.height
        guard pageHeight > 0 else {
            dragOffset = 0
            return
        }
        // `>=`/`<=`, not strict -- `animatedPageStep` targets an offset of *exactly* one page height
        // (a full, deliberate page turn), which a strict `>`/`<` here would never actually cross.
        while offset >= pageHeight {
            guard stepToPreviousPage() else {
                offset = pageHeight
                break
            }
            offset -= pageHeight
        }
        while offset <= -pageHeight {
            guard stepToNextPage() else {
                offset = -pageHeight
                break
            }
            offset += pageHeight
        }
        // Real-device testing: holding a finger down past a page boundary (not lifting, sometimes
        // barely moving at all) kept advancing pages over and over for as long as the touch stayed
        // down. Root cause -- `scrollModeBody`'s `.onChanged` always recomputes `newOffset` as
        // `dragGestureBaseOffset + value.translation.height`, an *absolute* target from the gesture's
        // fixed starting point, not an incremental delta since the last call. Real touch hardware
        // keeps redelivering `.onChanged` continuously while a finger is down -- natural hand tremor
        // alone produces a stream of near-identical `translation` values even when the finger "isn't
        // moving." Every one of those redeliveries was recomputing the *same* already-consumed
        // pre-crossing total from the untouched baseline and re-running the exact same page advance
        // against it, because nothing here ever told `dragGestureBaseOffset` that part of its
        // distance had already been spent. Subtracting exactly what this call consumed
        // (`newOffset - offset`) back out of it means the next callback -- even carrying the same raw
        // `translation.height` as this one -- recomputes the already-settled `offset`, not the
        // original oversized `newOffset`, so it becomes a no-op instead of repeating the crossing.
        dragGestureBaseOffset -= (newOffset - offset)
        dragOffset = offset
    }

    /// Advances exactly one page forward, crossing into `nextChapterPreview` (a pure pointer-shuffle
    /// promotion, see `commitToNextChapterPreview`) at the current chapter's last page -- `false`
    /// when nothing further is available yet (preview not ready, or this is the last chapter),
    /// which `commitPageOffset` treats as "clamp here, don't scroll past it."
    private func stepToNextPage() -> Bool {
        if let pageLayout, currentPageIndexInChapter + 1 < pageLayout.pages.count {
            currentPageIndexInChapter += 1
            saveReadingProgress()
            return true
        }
        guard let preview = nextChapterPreview, preview.pageLayout != nil else { return false }
        commitToNextChapterPreview(preview, arrivingAtPageIndex: 0)
        return true
    }

    /// Exact mirror of `stepToNextPage`, facing backward -- lands on `prevChapterPreview`'s own
    /// *last* page when crossing into it, matching where a physical book would be.
    private func stepToPreviousPage() -> Bool {
        if currentPageIndexInChapter > 0 {
            currentPageIndexInChapter -= 1
            saveReadingProgress()
            return true
        }
        guard let preview = prevChapterPreview, let previewLayout = preview.pageLayout,
              !previewLayout.pages.isEmpty else { return false }
        commitToPrevChapterPreview(preview, arrivingAtPageIndex: previewLayout.pages.count - 1)
        return true
    }

    /// Animated single-page turn for volume keys, tap zones, and auto-scroll -- as opposed to a live
    /// finger-drag's immediate, un-animated `commitPageOffset` calls. Slides `dragOffset` a full page
    /// under `withAnimation` first, matching Legado_Max's own distinction between raw drag tracking
    /// (`ScrollPageDelegate.onScroll`, immediate) and a tap/button-triggered turn (`nextPageByAnim`/
    /// `prevPageByAnim`, animated via `Scroller.startScroll`) -- then defers the actual page-index
    /// commit until that slide would have visually finished, exactly like
    /// `PagedChapterReaderView.beginTransition`'s own `pendingTransitionTask` does for its 3 non-
    /// `.scroll` styles. Ignores new requests while one is still animating (same guard
    /// `beginTransition` uses) rather than queuing them up.
    private func animatedPageStep(direction: Int) {
        guard pendingPageStepTask == nil else { return }
        let pageHeight = scrollPageSize.height
        guard pageHeight > 0 else { return }
        // A *fixed* target (one page height, not `dragOffset` plus one page height) -- matches
        // Legado_Max's own `calcNextPageOffset`/`calcPrevPageOffset`, which compute a turn distance
        // from wherever the current page is already sitting, not always a blind full page's worth on
        // top of that. A live drag can leave `dragOffset` resting at any sub-page position (that's
        // the whole point of not snapping back on release -- see its own doc comment); if a button
        // press right after that just added a fixed `±pageHeight` to whatever `dragOffset` already
        // was, the result would overshoot the next boundary by however much of the current page was
        // already scrolled, landing mid-page instead of cleanly on the next one. Animating toward
        // this fixed target from `dragOffset`'s actual current value still gives a shorter/longer
        // slide depending on how close the rest position already was -- just correctly *ends* exactly
        // on the next/previous page boundary (`dragOffset` settling back to precisely 0) every time.
        let targetOffset: CGFloat = direction > 0 ? -pageHeight : pageHeight
        animateAndCommit(to: targetOffset, duration: 0.25, animation: .easeInOut(duration: 0.25))
    }

    /// Finishes a released drag that still had momentum -- see `scrollModeBody`'s `.onEnded` for
    /// where `target` comes from (SwiftUI's own `predictedEndTranslation`, clamped to at most one
    /// further page beyond wherever the raw drag ended). Duration scales with distance -- a harder
    /// flick travels further *and* takes a bit longer to visually settle, within a bounded range --
    /// a reasonable stand-in for Legado_Max's real `Scroller`-based deceleration physics without
    /// reimplementing velocity/friction curves from scratch.
    ///
    /// The one-page clamp (in `.onEnded`, not here) matters for a structural reason, not just
    /// restraint: `pageSlot`'s 3 slots only ever resolve content *relative to whatever's currently
    /// committed* (`resolvedPage(relativeIndex: -1/0/1)`). Animating `dragOffset` further than one
    /// page out ahead of that commit would slide those slots past content that doesn't exist in the
    /// rendered tree at all (nothing resolves page ±2), showing blank space mid-flick before the
    /// eventual `commitPageOffset` call catches back up -- clamping keeps every frame of the
    /// animation showing real, already-resolved content throughout.
    private func settleDrag(to target: CGFloat) {
        let distance = abs(target - dragOffset)
        let duration = min(0.5, max(0.2, Double(distance) / 2000))
        animateAndCommit(to: target, duration: duration, animation: .easeOut(duration: duration))
    }

    /// Shared driver behind `animatedPageStep`/`settleDrag`: slide `dragOffset` to `target` under
    /// `animation` immediately, but defer the actual page/chapter-crossing commit (`commitPageOffset`)
    /// until that slide would have visually finished -- exactly `PagedChapterReaderView.
    /// beginTransition`'s own `pendingTransitionTask` pattern for its 3 non-`.scroll` styles, and
    /// distinct from a live finger-drag's immediate, un-animated `commitPageOffset` calls in
    /// `scrollModeBody`'s `.onChanged`.
    private func animateAndCommit(to target: CGFloat, duration: Double, animation: Animation) {
        withAnimation(animation) {
            dragOffset = target
        }
        pendingPageStepTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            commitPageOffset(target)
            pendingPageStepTask = nil
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
    private func pageBlock(_ index: Int, layout: ChapterPageLayout, isCurrentChapter: Bool) -> some View {
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
                // Real usage feedback pointed at a reference app whose long-press popup has custom
                // 净化/全文搜索/百科/网络搜索 buttons instead of the plain system Copy/Look Up/Share
                // menu `.textSelection(.enabled)` used to show here. Getting arbitrary drag-selected
                // *substrings* the way Legado's own selection handles do would need a `UITextView`
                // bridge (`.textSelection` has no hook to inject custom items, and SwiftUI `Text` has
                // no selection-change callback at all) -- routing one through this exact rendering
                // path risks real interference with `scrollModeBody`'s `DragGesture(minimumDistance:
                // 0, ...)`, which needs to win every touch from pixel zero to tell a tap from a page-
                // turn drag; a competing UIKit gesture recognizer sitting underneath it is a genuine,
                // unverifiable-without-a-device risk to the one interaction this reader has had the
                // most real bugs in. `.contextMenu` sidesteps that entirely -- it's SwiftUI's own
                // long-press-to-menu primitive (not a raw UIKit recognizer bolted on), designed to
                // coexist with other gestures on the same view tree, so the worst case is a slightly
                // less responsive long-press, never a broken page-turn. Scoped to whichever whole
                // paragraph was pressed rather than an arbitrary substring (a real, honest difference
                // from Legado's drag-handle selection, not a fake stand-in for it) -- each action
                // below reuses an already-existing feature (`DictLookupView`/`WebSearchPanelView`/
                // `ChapterContentSearchView`'s `initial*` params were literally built for and left
                // unwired for exactly this hookup, see their own doc comments) rather than
                // introducing new ones. `isCurrentChapter` (see `ResolvedPage`'s doc comment) hides
                // the two actions that read *current-chapter* state (朗读/书签) when this chunk
                // actually belongs to a neighboring chapter's preview slot, so those two can't ever
                // silently act against the wrong chapter.
                .contextMenu {
                    paragraphContextMenuItems(chunk, isCurrentChapter: isCurrentChapter)
                }
            }
        }
        .padding(.vertical, 8)
    }

    /// The custom long-press menu's actual items -- see `pageBlock`'s `.contextMenu` doc comment for
    /// why this exists instead of `.textSelection`'s system menu. Every action operates on
    /// `chunk.text` (the whole pressed paragraph, this reader's unit of selection) except 朗读/书签,
    /// which additionally need `chunk.paragraphIndex` to mean an index into the *current* chapter's
    /// `paragraphs`/`pageLayout` -- see `ResolvedPage.isCurrentChapter`'s doc comment for why those
    /// two are hidden entirely (rather than shown and risking acting on the wrong chapter) when
    /// `isCurrentChapter` is false.
    @ViewBuilder
    private func paragraphContextMenuItems(_ chunk: ChapterPageLayout.Chunk, isCurrentChapter: Bool) -> some View {
        Button {
            UIPasteboard.general.string = chunk.text
        } label: {
            Label("复制", systemImage: "doc.on.doc")
        }
        Button {
            paragraphMenuText = chunk.text
            isShowingParagraphShareSheet = true
        } label: {
            Label("分享", systemImage: "square.and.arrow.up")
        }
        if isCurrentChapter {
            Button {
                beginReadAloud(startIndex: chunk.paragraphIndex)
            } label: {
                Label("朗读，从这里开始", systemImage: "waveform")
            }
            Button {
                addBookmark(forParagraph: chunk)
            } label: {
                Label("添加书签", systemImage: "bookmark")
            }
        }
        Button {
            paragraphMenuText = chunk.text
            isShowingDictLookup = true
        } label: {
            Label("查词典", systemImage: "character.book.closed")
        }
        Button {
            paragraphMenuText = chunk.text
            isShowingContentSearch = true
        } label: {
            Label("搜索本书", systemImage: "magnifyingglass")
        }
        Button {
            paragraphMenuText = chunk.text
            isShowingWebSearch = true
        } label: {
            Label("网络搜索", systemImage: "globe")
        }
        Button {
            paragraphMenuText = chunk.text
            isShowingReplaceRuleSeed = true
        } label: {
            Label("新建净化规则", systemImage: "wand.and.stars")
        }
    }

    /// Always adds a fresh bookmark (matching Legado's `menu_bookmark` -- "书签" on the long-press
    /// menu creates one, it isn't a toggle the way the toolbar's 书签 button is) at the pressed
    /// paragraph's exact character offset, independent of whichever page/paragraph is actually
    /// current -- `pageLayout` is captured here (not `currentPageIndexInChapter`) precisely because
    /// the long-pressed paragraph might not be the page's first one.
    private func addBookmark(forParagraph chunk: ChapterPageLayout.Chunk) {
        let offset = pageLayout?.characterOffset(forParagraphIndex: chunk.paragraphIndex)
        let bookmark = Bookmark(
            isLocal: false, bookSourceUrl: source.bookSourceUrl, bookIdentifier: bookUrl,
            tocUrl: tocUrl, bookTitle: bookTitle, chapterIndex: chapter.index, chapterTitle: chapter.title,
            characterOffset: offset, excerpt: Bookmark.makeExcerpt(from: chunk.text)
        )
        Task {
            try? await env.bookmarkStore.add(bookmark)
            isCurrentChapterBookmarked = true
        }
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
        do {
            let cached = try? await env.chapterCacheStore.chapter(bookUrl: bookUrl, index: chapter.index)
            let content: ChapterContent
            if let cached {
                content = cached
            } else {
                content = try await ContentService.fetchContent(
                    source: source, chapter: chapter, httpClient: env.httpClient,
                    nextChapterUrl: chapters.indices.contains(currentIndex + 1) ? chapters[currentIndex + 1].url : nil
                )
            }
            let replaceRules = (try? await env.replaceRuleStore.enabled()) ?? []
            let purified = ReplaceRuleApplier.applyReportingMatches(replaceRules, to: content.text, bookName: bookTitle, sourceUrl: source.bookSourceUrl)
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
        prefetchUpcomingChapters()
        prefetchPreviousChapters()
        await loadPrevChapterPreview()
        await loadNextChapterPreview()
    }

    /// Prefetches and fully purifies+paginates the *previous* chapter's content ahead of time so it
    /// can be prepended above the current chapter's own heading (see `prevChapterPreview`'s doc
    /// comment for why) -- exact mirror of `loadNextChapterPreview`, just facing the other direction.
    private func loadPrevChapterPreview() async {
        let prevIndex = currentIndex - 1
        guard chapters.indices.contains(prevIndex) else {
            prevChapterPreview = nil
            return
        }
        let prevChapter = chapters[prevIndex]
        let cached = try? await env.chapterCacheStore.chapter(bookUrl: bookUrl, index: prevIndex)
        let content: ChapterContent
        if let cached {
            content = cached
        } else {
            guard let fetched = try? await ContentService.fetchContent(
                source: source, chapter: prevChapter, httpClient: env.httpClient,
                nextChapterUrl: chapters.indices.contains(prevIndex + 1) ? chapters[prevIndex + 1].url : nil
            ) else {
                prevChapterPreview = nil
                return
            }
            content = fetched
        }
        // Guards against a stale response landing after the user has already moved past this
        // chapter some other way (e.g. jumped via TOC/search while this fetch was still in flight).
        guard prevIndex == currentIndex - 1 else { return }
        let replaceRules = (try? await env.replaceRuleStore.enabled()) ?? []
        let purified = ReplaceRuleApplier.applyReportingMatches(replaceRules, to: content.text, bookName: bookTitle, sourceUrl: source.bookSourceUrl)
        let previewText = applyChineseConversion(purified.result)
        var preview = AdjacentChapterPreview(
            index: prevIndex, title: prevChapter.title, text: previewText, matchedRules: purified.matchedRules
        )
        if !pageTurnStyle.isPaginated, scrollPageSize.width > 0, scrollPageSize.height > 0 {
            let font = UIFont.systemFont(ofSize: fontSize)
            let pages = ChapterPaginator.paginate(
                text: previewText, font: font, lineSpacing: lineSpacing, paragraphSpacing: paragraphSpacing,
                pageSize: scrollPageSize
            )
            preview.pageLayout = ChapterPageLayout(paragraphs: previewText.components(separatedBy: "\n"), pages: pages)
        }
        prevChapterPreview = preview
    }

    /// Prefetches and fully purifies+paginates the *next* chapter's content ahead of time so it can
    /// be appended right below the current chapter's own pages (see `nextChapterPreview`'s doc
    /// comment for why). Reuses `ChapterCacheStore` -- the same cache `prefetchUpcomingChapters`
    /// already warms -- so this is usually an instant cache hit rather than a second network
    /// request racing that one. Skips pagination (leaves `pageLayout` `nil` on the returned preview)
    /// if `scrollPageSize` hasn't been measured yet or the reader is in a paginated style --
    /// `stepToNextPage` only crosses into a preview once its `pageLayout` is actually ready.
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
                source: source, chapter: nextChapter, httpClient: env.httpClient,
                nextChapterUrl: chapters.indices.contains(nextIndex + 1) ? chapters[nextIndex + 1].url : nil
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
        let purified = ReplaceRuleApplier.applyReportingMatches(replaceRules, to: content.text, bookName: bookTitle, sourceUrl: source.bookSourceUrl)
        let previewText = applyChineseConversion(purified.result)
        var preview = AdjacentChapterPreview(
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
    /// network round trip, no re-pagination needed: the preview's pages already exist, so promoting
    /// it just relabels which pages count as "the current chapter" for read-aloud/highlight/bookmark/
    /// position-tracking purposes. `justCommittedFromPreview` stops `load()` from redundantly
    /// re-fetching content that's already sitting there (see its own doc comment) -- unlike the old
    /// `ScrollView`-based reader, there's no separate "reset the scroll position" step to also
    /// suppress here, since `dragOffset`/`currentPageIndexInChapter` were already updated by
    /// whichever caller (a live drag's `commitPageOffset`, or an animated `animatedPageStep`)
    /// triggered this crossing in the first place -- nothing about what's on screen jumps.
    /// `arrivingAtPageIndex` is which page of `preview` the crossing actually landed on -- 0 for an
    /// animated/button-triggered turn, but not necessarily 0 for a live drag, since a fast swipe can
    /// cross straight into the middle of the next chapter's first visible page.
    ///
    /// The chapter that was "current" until now becomes the new `prevChapterPreview` for free -- it's
    /// already fully fetched/purified/paginated, so no refetch is needed, exactly mirroring
    /// Legado_Max's `ReadBook.moveToNextChapter` (`prevTextChapter = curTextChapter; curTextChapter =
    /// nextTextChapter`): the 3-chapter window slides by one instead of growing or shrinking.
    private func commitToNextChapterPreview(_ preview: AdjacentChapterPreview, arrivingAtPageIndex: Int) {
        justCommittedFromPreview = true
        isSeamlessChapterTransition = true
        prevChapterPreview = AdjacentChapterPreview(
            index: currentIndex, title: chapter.title, text: text, matchedRules: matchedReplaceRules, pageLayout: pageLayout
        )
        currentIndex = preview.index
        text = preview.text
        matchedReplaceRules = preview.matchedRules
        pageLayout = preview.pageLayout
        lastPaginatedScrollText = preview.text
        currentPageIndexInChapter = arrivingAtPageIndex
        nextChapterPreview = nil
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
        prefetchPreviousChapters()
    }

    /// Exact mirror of `commitToNextChapterPreview`, facing backward: the chapter that was "current"
    /// becomes the new `nextChapterPreview` for free (no refetch), matching Legado_Max's
    /// `ReadBook.moveToPrevChapter` (`nextTextChapter = curTextChapter; curTextChapter =
    /// prevTextChapter`).
    private func commitToPrevChapterPreview(_ preview: AdjacentChapterPreview, arrivingAtPageIndex: Int) {
        justCommittedFromPreview = true
        isSeamlessChapterTransition = true
        nextChapterPreview = AdjacentChapterPreview(
            index: currentIndex, title: chapter.title, text: text, matchedRules: matchedReplaceRules, pageLayout: pageLayout
        )
        currentIndex = preview.index
        text = preview.text
        matchedReplaceRules = preview.matchedRules
        pageLayout = preview.pageLayout
        lastPaginatedScrollText = preview.text
        currentPageIndexInChapter = arrivingAtPageIndex
        prevChapterPreview = nil
        Task {
            try? await env.shelfStore.updateProgress(
                bookUrl: bookUrl, chapterIndex: preview.index, chapterTitle: preview.title, characterOffset: 0
            )
            isCurrentChapterBookmarked = (try? await env.bookmarkStore.isBookmarked(
                bookIdentifier: bookUrl, chapterIndex: preview.index
            )) ?? false
        }
        Task { await loadPrevChapterPreview() }
        prefetchUpcomingChapters()
        prefetchPreviousChapters()
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
    /// offset into a target page needs to know *which page's `NSRange` contains that offset*, which
    /// only exists once pagination has actually run. Doesn't need to touch `dragOffset` at all --
    /// `.onChange(of: currentIndex)` already reset it to 0 for a hard `goTo` jump before this ever
    /// runs, and a seamless crossing-commit already adjusted it correctly itself (see
    /// `commitPageOffset`'s doc comment) using the screen's own measured height, which doesn't
    /// depend on which chapter's text this is re-paginating. This is the one big simplification the
    /// move away from a native `ScrollView` bought: no scroll-position compensation to get right,
    /// because nothing here ever needs to re-anchor a scroll offset in the first place.
    private func repaginateForScroll(size: CGSize) async {
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
            // A genuinely new chapter -- `pageAnchor` matters here the same way it does for
            // `PagedChapterReaderView.repaginate`'s `initialAnchor`: `.last` for continuing to page
            // backward past a chapter's first page (see `goTo`'s doc comment), `.first` (page 0)
            // for every other entry into a fresh chapter.
            currentPageIndexInChapter = pageAnchor == .first ? 0 : max(newLayout.pages.count - 1, 0)
        }
        pageLayout = newLayout
        lastPaginatedScrollText = text

        // Re-paginates both adjacent-chapter previews on *every* run here, not just once when
        // `pageLayout` is still `nil` -- real usage feedback: after enlarging the font, the current
        // chapter reflowed correctly, but scrolling into the next/previous chapter still showed the
        // old, stale page breaks computed under the old font size, since a one-shot nil-check never
        // revisits a preview that already has a `pageLayout`. `loadNextChapterPreview`/
        // `loadPrevChapterPreview` skipping pagination when `scrollPageSize` isn't known yet also
        // means this is genuinely the *first* pagination for a brand-new preview essentially every
        // time (see their own doc comments: `prefetchUpcomingChapters` keeps neighboring chapters'
        // content warm enough that the cache hit routinely beats this function's own TextKit work),
        // so this one unconditional pass covers both "never paginated yet" and "stale from an old
        // font size" with the same code path. Neither of these can shift what's currently on screen
        // out from under the user the way it could when this reader appended/prepended them into one
        // shared `ScrollView` -- each of `resolvedPage`'s 3 slots is independently positioned, so a
        // preview's page count changing just means its *own* slot shows different content next time
        // it's resolved, nothing moves.
        if var next = nextChapterPreview {
            let nextPages = ChapterPaginator.paginate(
                text: next.text, font: font, lineSpacing: lineSpacing, paragraphSpacing: paragraphSpacing, pageSize: size
            )
            next.pageLayout = ChapterPageLayout(paragraphs: next.text.components(separatedBy: "\n"), pages: nextPages)
            nextChapterPreview = next
        }
        if var prev = prevChapterPreview {
            let prevPages = ChapterPaginator.paginate(
                text: prev.text, font: font, lineSpacing: lineSpacing, paragraphSpacing: paragraphSpacing, pageSize: size
            )
            prev.pageLayout = ChapterPageLayout(paragraphs: prev.text.components(separatedBy: "\n"), pages: prevPages)
            prevChapterPreview = prev
        }

        if let offset = pendingResumeCharacterOffset {
            pendingResumeCharacterOffset = nil
            currentPageIndexInChapter = newLayout.pages.firstIndex { $0.location + $0.length > offset } ?? 0
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
    /// own normal network fetch, exactly like before this existed).
    private func prefetchUpcomingChapters() {
        guard prefetchChapterCount > 0 else { return }
        prefetchChapters(in: (currentIndex + 1)..<(currentIndex + 1 + prefetchChapterCount))
    }

    /// Backward mirror of `prefetchUpcomingChapters` -- confirmed against Legado_Max's own
    /// `ReadBook.preDownload`, which warms raw chapter text on *both* sides of the resident reading
    /// window (`backwardPreDownloadNum`, not just `preDownloadNum`), not only forward. Without this,
    /// scrolling/paging backward past `prevChapterPreview`'s own one-chapter buffer (re-reading, or
    /// just continuing a backward scroll) always hit the network fresh, unlike continuing forward.
    /// Closest chapter first (`currentIndex - 1`, then `- 2`, ...) -- the reverse of
    /// `prefetchUpcomingChapters`'s naturally-ascending order, since naively walking this range
    /// ascending would fetch the *farthest* backward chapter first and the nearest (most likely to
    /// actually be needed next) last.
    private func prefetchPreviousChapters() {
        guard backwardPrefetchChapterCount > 0 else { return }
        let lowerBound = max(0, currentIndex - backwardPrefetchChapterCount)
        prefetchChapters(in: lowerBound..<currentIndex, closestFirst: true)
    }

    /// Shared driver behind `prefetchUpcomingChapters`/`prefetchPreviousChapters` -- re-checks
    /// `chapters.indices` inside the loop rather than trusting `indices` as computed, since 换源 can
    /// shrink `chapters` out from under an in-flight prefetch if the user switches source mid-fetch.
    /// Throttled to match Legado_Max's own `ReadBook.downloadIndex`: a `PRE_DOWNLOAD_DELAY_MS` (1s)
    /// pacing delay before each network fetch a cache-miss actually needs (no delay for a cache hit,
    /// same as Legado skipping `downloadIndex` entirely for an already-downloaded chapter), plus
    /// `prefetchLimiter` capping how many of those fetches run at once across both this loop and its
    /// forward/backward counterpart -- without it, jumping several chapters in a row (each firing its
    /// own forward+backward prefetch pair) could pile up many simultaneous requests against a book
    /// source's server instead of a bounded, gentle trickle.
    private func prefetchChapters(in indices: Range<Int>, closestFirst: Bool = false) {
        guard !indices.isEmpty else { return }
        let orderedIndices = closestFirst ? Array(indices.reversed()) : Array(indices)
        Task {
            for index in orderedIndices {
                guard chapters.indices.contains(index) else { continue }
                if (try? await env.chapterCacheStore.chapter(bookUrl: bookUrl, index: index)) != nil { continue }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await prefetchLimiter.acquire()
                if let content = try? await ContentService.fetchContent(
                    source: source, chapter: chapters[index], httpClient: env.httpClient,
                    nextChapterUrl: chapters.indices.contains(index + 1) ? chapters[index + 1].url : nil
                ) {
                    try? await env.chapterCacheStore.save(bookUrl: bookUrl, index: index, content: content)
                }
                await prefetchLimiter.release()
            }
        }
    }

    /// One bookmark per (book, chapter) at most -- the button is a simple toggle, not a "add
    /// another one here" action (see `Bookmark.characterOffset`'s doc comment for why that's a
    /// deliberately separate, larger feature this doesn't attempt). In `.scroll` mode, captures the
    /// exact character offset of whatever page is currently showing -- the same value
    /// `saveReadingProgress` computes -- so jumping back to this bookmark later (via
    /// `BookmarkListView`'s `BookOpenerView`, or the in-reader 书签 tab's `onSelectChapter`) lands
    /// on the actual spot, not just the chapter's first page. `nil` in paginated mode, which has no
    /// equivalent character-offset exposed back to this function.
    private func toggleBookmark() async {
        if isCurrentChapterBookmarked {
            try? await env.bookmarkStore.remove(bookIdentifier: bookUrl, chapterIndex: chapter.index)
            isCurrentChapterBookmarked = false
        } else {
            let offset: Int? = {
                guard !pageTurnStyle.isPaginated, let pageLayout,
                      pageLayout.pages.indices.contains(currentPageIndexInChapter) else { return nil }
                return pageLayout.pages[currentPageIndexInChapter].location
            }()
            let excerpt: String? = {
                guard !pageTurnStyle.isPaginated, let pageLayout else { return nil }
                let chunks = pageLayout.chunks(forPage: currentPageIndexInChapter)
                guard let firstNonBlank = chunks.first(where: {
                    !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }) else { return nil }
                return Bookmark.makeExcerpt(from: firstNonBlank.text)
            }()
            let bookmark = Bookmark(
                isLocal: false, bookSourceUrl: source.bookSourceUrl, bookIdentifier: bookUrl,
                tocUrl: tocUrl, bookTitle: bookTitle, chapterIndex: chapter.index, chapterTitle: chapter.title,
                characterOffset: offset, excerpt: excerpt
            )
            try? await env.bookmarkStore.add(bookmark)
            isCurrentChapterBookmarked = true
        }
    }
}

/// A counting semaphore for `async`/`await` code -- mirrors Legado_Max's own
/// `ReadBook.preDownloadSemaphore` (`kotlinx.coroutines.sync.Semaphore(PRE_DOWNLOAD_CONCURRENCY)`),
/// which Swift Concurrency has no direct standard-library equivalent for. `acquire()` returns
/// immediately while under `limit`; once at capacity, callers suspend on a FIFO queue of
/// continuations and are resumed one at a time as `release()` is called, so no acquired permit is
/// ever handed out beyond `limit` concurrently.
private actor PrefetchLimiter {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
        active += 1
    }

    func release() {
        active -= 1
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        }
    }
}
