import Foundation

/// Maps a paginated chapter's character-range pages (as produced by the app target's
/// `ChapterPaginator`, which needs real UIKit/TextKit font metrics and so can't live in this
/// cross-platform package) back onto paragraph identity -- lets a page render as its own
/// paragraph-spaced chunks (matching the un-paginated `.scroll` reader's visual rhythm, since a
/// page's first/last chunk can be a partial paragraph continuing onto a neighboring page) and lets
/// a paragraph index (as tracked by read-aloud, or a full-book search hit) be turned into "which
/// page is that on right now". Pure `NSRange`/`NSString` arithmetic with no UIKit dependency, so
/// unlike the rest of the pagination feature this one piece is actually unit-testable via
/// `swift test` on Windows/macOS CI, not just verifiable by the iOS build steps.
public struct ChapterPageLayout {
    public struct Chunk: Equatable {
        /// Index into the chapter's full `paragraphs` array -- not necessarily unique to this page,
        /// since the paragraph this chunk belongs to may continue from the previous page or onto
        /// the next one.
        public let paragraphIndex: Int
        public let text: String
    }

    public let pages: [NSRange]
    /// Stored (not taken as a `chunks(forPage:)` parameter) so this type is always self-consistent
    /// with its own `pages` ranges -- a caller holding onto a slightly-stale `ChapterPageLayout`
    /// across a chapter change (the moment between the parent's `text` prop updating and this
    /// layout's owner re-running pagination for the new text) can't accidentally hand it the *new*
    /// text and read `pages` ranges computed against the *old* one, which would risk an
    /// out-of-bounds `NSString.substring(with:)` crash.
    private let fullText: NSString
    private let paragraphStartOffsets: [Int]

    public init(paragraphs: [String], pages: [NSRange]) {
        self.pages = pages
        self.fullText = paragraphs.joined(separator: "\n") as NSString
        var offsets: [Int] = []
        var running = 0
        for paragraph in paragraphs {
            offsets.append(running)
            // +1 accounts for the "\n" joining this paragraph to the next one -- matches how every
            // other paragraph-index-based feature in this reader already treats `text.components
            // (separatedBy: "\n")` as the paragraph boundary.
            running += (paragraph as NSString).length + 1
        }
        self.paragraphStartOffsets = offsets
    }

    /// Paragraph-spaced chunks for the page at `pageIndex`, in reading order.
    public func chunks(forPage pageIndex: Int) -> [Chunk] {
        guard pages.indices.contains(pageIndex) else { return [] }
        let range = pages[pageIndex]
        guard range.location >= 0, range.location + range.length <= fullText.length else { return [] }
        let pageString = fullText.substring(with: range)
        let startParagraph = paragraphIndex(forCharacterOffset: range.location)
        return pageString.components(separatedBy: "\n").enumerated().map { offset, text in
            Chunk(paragraphIndex: startParagraph + offset, text: text)
        }
    }

    /// Which page contains the start of the given paragraph -- used to auto-follow read-aloud, or
    /// to jump straight to a full-book search hit's paragraph.
    public func pageIndex(forParagraphIndex paragraphIndex: Int) -> Int {
        guard paragraphStartOffsets.indices.contains(paragraphIndex) else { return 0 }
        let offset = paragraphStartOffsets[paragraphIndex]
        for (index, range) in pages.enumerated() where range.location + range.length > offset {
            return index
        }
        return max(pages.count - 1, 0)
    }

    /// The character offset the given paragraph starts at, in the chapter's full joined text -- the
    /// inverse of `paragraphIndex(forCharacterOffset:)`. Used to give a long-pressed paragraph's
    /// custom-menu "添加书签" action the same exact-position semantics `Bookmark.characterOffset`
    /// already has for the current page (see `ReaderView.toggleBookmark`), instead of falling back
    /// to chapter-level-only for a bookmark created this way.
    public func characterOffset(forParagraphIndex index: Int) -> Int? {
        guard paragraphStartOffsets.indices.contains(index) else { return nil }
        return paragraphStartOffsets[index]
    }

    /// The paragraph whose text starts at or most recently before `offset` -- i.e. "which paragraph
    /// is this character inside of".
    private func paragraphIndex(forCharacterOffset offset: Int) -> Int {
        var result = 0
        for (index, start) in paragraphStartOffsets.enumerated() {
            if start <= offset { result = index } else { break }
        }
        return result
    }
}
