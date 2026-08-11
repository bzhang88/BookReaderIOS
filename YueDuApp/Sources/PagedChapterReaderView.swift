import SwiftUI
import UIKit
import BookSourceModel
import WebBookOrchestrator
import RuleEngine

/// Where a freshly (re)paginated chapter should start -- `.last` when the reader arrived here by
/// paging *backward* past the previous chapter's first page (continuing the reading flow, matching
/// where a physical book would "still be" if you kept turning back), `.first` for every other entry
/// point (an explicit chapter-list jump, paging forward, or just opening the book).
enum PageAnchor: Equatable {
    case first, last
}

/// A page-turn request a parent view (volume keys, in `ReaderView`/`LocalReaderView`) can push down
/// without needing a direct reference to this view's internal state -- consumed and reset to `nil`
/// by this view's own `.onChange`.
enum PageTurnRequest: Equatable {
    case previous, next
}

/// Real, TextKit-measured pagination with all 4 non-scroll page-turn styles (`.none`/`.slide`/
/// `.cover`/`.curl`) -- the reader's original continuous `ScrollView` body (`.scroll` style) is left
/// completely untouched and lives in `ReaderView`/`LocalReaderView` directly; this view is only
/// ever shown when the user has picked one of the other 4.
///
/// Turning past a chapter's first/last page calls `onRequestPreviousChapter`/`onRequestNextChapter`
/// rather than handling chapter transitions itself -- this view only knows about the one chapter's
/// text it was given; the parent owns chapter navigation (and re-creates this view, via SwiftUI's
/// normal `.task(id:)`-driven reload, for the new chapter's text).
struct PagedChapterReaderView: View {
    let text: String
    let style: PageTurnStyle
    let fontSize: Double
    let lineSpacing: Double
    let paragraphSpacing: Double
    let textColor: Color
    /// Applied explicitly per-page (not left to the parent's own `.background()`) because `.curl`
    /// hosts each page inside its own `UIHostingController` -- a separate opaque UIKit view that
    /// would otherwise default to plain white behind the curl animation regardless of the current
    /// theme, most noticeably wrong in the night theme.
    let backgroundColor: Color
    let highlightRules: [HighlightRule]
    /// The paragraph read-aloud is currently speaking, if any -- this view auto-turns to whichever
    /// page contains it and tints that paragraph the same way the `.scroll` reader already does.
    let readAloudParagraphIndex: Int?
    let initialAnchor: PageAnchor
    @Binding var pageTurnRequest: PageTurnRequest?
    let touchSlop: Double
    let onTapMiddle: () -> Void
    let onRequestPreviousChapter: () -> Void
    let onRequestNextChapter: () -> Void
    /// (currentPageOneBased, totalPages) -- purely for the parent's progress display; this view
    /// doesn't render its own page-count UI.
    let onPageChanged: (Int, Int) -> Void

    @State private var layout: ChapterPageLayout?
    @State private var currentPageIndex: Int = 0
    @State private var transition: PageTransitionState?
    @State private var transitionProgress: CGFloat = 0
    /// The exact text pagination last ran against -- lets `repaginate` tell "the chapter changed"
    /// (use `initialAnchor`) apart from "only font/line/paragraph spacing changed, same chapter"
    /// (keep showing roughly the same paragraph instead of jumping back to the anchor page every
    /// time the user tweaks a reading-settings slider).
    @State private var lastPaginatedText: String?
    /// Cancelled by `repaginate` on a genuine chapter change -- without this, a slide/cover
    /// animation's delayed "commit the new page index" step (see `beginTransition`) could still
    /// fire after the user jumped chapters some other way (e.g. the toolbar's 下一章 button, which
    /// bypasses this view entirely) mid-animation, overwriting the freshly-loaded chapter's page
    /// index with a stale one from the chapter that's no longer showing.
    @State private var pendingTransitionTask: Task<Void, Never>?

    private static let transitionDuration: Double = 0.28
    private static let pageInset: CGFloat = 16

    private var paragraphs: [String] { text.components(separatedBy: "\n") }

    var body: some View {
        GeometryReader { geo in
            let contentSize = CGSize(
                width: max(geo.size.width - Self.pageInset * 2, 0),
                height: max(geo.size.height - Self.pageInset * 2, 0)
            )
            Group {
                if let layout {
                    if style == .curl {
                        PageCurlContainerView(
                            pageCount: layout.pages.count,
                            currentPageIndex: $currentPageIndex,
                            pageBuilder: { index in AnyView(pageContent(index, layout: layout)) },
                            onTapMiddle: onTapMiddle,
                            onRequestPreviousChapter: onRequestPreviousChapter,
                            onRequestNextChapter: onRequestNextChapter
                        )
                    } else {
                        tapPager(layout: layout, size: contentSize)
                    }
                } else {
                    Color.clear
                }
            }
            .padding(Self.pageInset)
            .task(id: paginationKey(size: contentSize)) {
                await repaginate(size: contentSize)
            }
        }
        .onChange(of: readAloudParagraphIndex) { _, newValue in
            guard let newValue, let layout, transition == nil else { return }
            let target = layout.pageIndex(forParagraphIndex: newValue)
            if target != currentPageIndex {
                currentPageIndex = target
            }
        }
        .onChange(of: pageTurnRequest) { _, request in
            guard let request, let layout else { return }
            switch request {
            case .previous: beginTransition(direction: -1, layout: layout)
            case .next: beginTransition(direction: 1, layout: layout)
            }
            pageTurnRequest = nil
        }
        .onChange(of: currentPageIndex) { _, newValue in
            guard let layout else { return }
            onPageChanged(newValue + 1, layout.pages.count)
        }
    }

    private func paginationKey(size: CGSize) -> String {
        "\(text.count)-\(text.hashValue)-\(fontSize)-\(lineSpacing)-\(paragraphSpacing)-\(Int(size.width))-\(Int(size.height))"
    }

    private func repaginate(size: CGSize) async {
        guard size.width > 0, size.height > 0 else { return }
        let font = UIFont.systemFont(ofSize: fontSize)
        let pages = ChapterPaginator.paginate(
            text: text, font: font, lineSpacing: lineSpacing, paragraphSpacing: paragraphSpacing, pageSize: size
        )
        guard !Task.isCancelled else { return }
        let newLayout = ChapterPageLayout(paragraphs: paragraphs, pages: pages)

        let isSameChapterReflow = lastPaginatedText == text
        if !isSameChapterReflow {
            pendingTransitionTask?.cancel()
            pendingTransitionTask = nil
        }
        if isSameChapterReflow, let oldLayout = layout, oldLayout.pages.indices.contains(currentPageIndex) {
            let anchorParagraph = oldLayout.chunks(forPage: currentPageIndex).first?.paragraphIndex ?? 0
            currentPageIndex = newLayout.pageIndex(forParagraphIndex: anchorParagraph)
        } else {
            currentPageIndex = initialAnchor == .first ? 0 : max(newLayout.pages.count - 1, 0)
        }
        layout = newLayout
        lastPaginatedText = text
        transition = nil
        transitionProgress = 0
        onPageChanged(currentPageIndex + 1, newLayout.pages.count)
    }

    @ViewBuilder
    private func pageContent(_ index: Int, layout: ChapterPageLayout) -> some View {
        VStack(alignment: .leading, spacing: paragraphSpacing) {
            ForEach(layout.chunks(forPage: index), id: \.paragraphIndex) { chunk in
                styledChunk(chunk)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(backgroundColor)
    }

    @ViewBuilder
    private func styledChunk(_ chunk: ChapterPageLayout.Chunk) -> some View {
        let isSpeaking = readAloudParagraphIndex == chunk.paragraphIndex
        let segments = HighlightRuleApplier.segments(highlightRules, in: chunk.text)
        segments.reduce(Text("")) { partial, segment in
            if segment.isHighlighted {
                return partial + Text(segment.text).foregroundStyle(.orange).bold()
            } else {
                return partial + Text(segment.text).foregroundStyle(textColor)
            }
        }
        .font(.system(size: fontSize))
        .lineSpacing(lineSpacing)
        .background(isSpeaking ? Color.accentColor.opacity(0.15) : Color.clear)
    }

    @ViewBuilder
    private func tapPager(layout: ChapterPageLayout, size: CGSize) -> some View {
        ZStack {
            if let transition {
                pageContent(transition.fromPage, layout: layout)
                    .frame(width: size.width, height: size.height)
                    .offset(x: fromOffset(width: size.width, direction: transition.direction))
                pageContent(transition.toPage, layout: layout)
                    .frame(width: size.width, height: size.height)
                    .offset(x: toOffset(width: size.width, direction: transition.direction))
            } else {
                pageContent(currentPageIndex, layout: layout)
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        // Without clipping, a page mid-slide/cover animation would render outside its nominal
        // bounds (`.offset` shifts the view visually without cropping it) and briefly spill over
        // into the toolbar/nav-bar area around it.
        .clipped()
        .contentShape(Rectangle())
        // Zero-distance drag, same tap-vs-scroll disambiguation the `.scroll` reader's own tap
        // zones already use (see `ReaderView.handleTap`) -- live drag-following isn't implemented
        // for these 3 styles in this first pass (see this type's doc comment); only a completed,
        // slop-bounded tap turns a page or toggles chrome.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    guard hypot(value.translation.width, value.translation.height) <= touchSlop else { return }
                    handleTap(at: value.location, width: size.width, layout: layout)
                }
        )
    }

    private func handleTap(at location: CGPoint, width: CGFloat, layout: ChapterPageLayout) {
        if location.x < width * 0.3 {
            beginTransition(direction: -1, layout: layout)
        } else if location.x > width * 0.7 {
            beginTransition(direction: 1, layout: layout)
        } else {
            onTapMiddle()
        }
    }

    private func beginTransition(direction: Int, layout: ChapterPageLayout) {
        guard transition == nil else { return }
        let newIndex = currentPageIndex + direction
        guard layout.pages.indices.contains(newIndex) else {
            if direction > 0 { onRequestNextChapter() } else { onRequestPreviousChapter() }
            return
        }
        switch style {
        case .scroll:
            break // unreachable -- the caller never shows this view for `.scroll`
        case .none, .curl:
            currentPageIndex = newIndex
        case .slide, .cover:
            transition = PageTransitionState(fromPage: currentPageIndex, toPage: newIndex, direction: direction)
            transitionProgress = 0
            withAnimation(.easeInOut(duration: Self.transitionDuration)) {
                transitionProgress = 1
            }
            pendingTransitionTask = Task {
                try? await Task.sleep(for: .seconds(Self.transitionDuration))
                guard !Task.isCancelled else { return }
                currentPageIndex = newIndex
                transition = nil
                transitionProgress = 0
            }
        }
    }

    /// The outgoing page's offset -- stays put (0) for `.cover` (the incoming page slides on top of
    /// it instead), otherwise slides out the opposite edge from the incoming page.
    private func fromOffset(width: CGFloat, direction: Int) -> CGFloat {
        style == .cover ? 0 : -CGFloat(direction) * width * transitionProgress
    }

    /// The incoming page's offset -- starts fully off-screen on the side matching `direction` and
    /// animates to 0 (fully in place) as `transitionProgress` goes 0 → 1.
    private func toOffset(width: CGFloat, direction: Int) -> CGFloat {
        CGFloat(direction) * width * (1 - transitionProgress)
    }
}

private struct PageTransitionState: Equatable {
    let fromPage: Int
    let toPage: Int
    let direction: Int
}
