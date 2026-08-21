import XCTest
@testable import RuleEngine

final class ChapterPageLayoutTests: XCTestCase {
    /// 3 paragraphs, 2 pages: page 0 holds all of paragraph 0 plus the first half of paragraph 1;
    /// page 1 holds the rest of paragraph 1 plus all of paragraph 2 -- exercises a page break that
    /// falls *inside* a paragraph, the case `ChapterPaginator`'s real TextKit layout produces
    /// whenever a paragraph doesn't happen to end exactly at a line boundary.
    private func makeMidParagraphSplitLayout() -> ChapterPageLayout {
        let paragraphs = ["Hello world", "ABCDEFGHIJ", "Last paragraph"]
        let fullText = paragraphs.joined(separator: "\n")
        let nsText = fullText as NSString
        XCTAssertEqual(nsText.length, "Hello world".count + 1 + "ABCDEFGHIJ".count + 1 + "Last paragraph".count)

        // "Hello world\n" is 12 chars (indices 0..<12); split paragraph 1 ("ABCDEFGHIJ") after 5
        // characters, so page 0 = [0, 17) covering "Hello world\nABCDE", page 1 = the remainder.
        let page0 = NSRange(location: 0, length: 17)
        let page1 = NSRange(location: 17, length: nsText.length - 17)
        return ChapterPageLayout(paragraphs: paragraphs, pages: [page0, page1])
    }

    func testChunksSplitsPageIntoParagraphSpacedPieces() {
        let layout = makeMidParagraphSplitLayout()
        let page0Chunks = layout.chunks(forPage: 0)
        XCTAssertEqual(page0Chunks.map(\.paragraphIndex), [0, 1])
        XCTAssertEqual(page0Chunks[0].text, "Hello world")
        XCTAssertEqual(page0Chunks[1].text, "ABCDE")
    }

    func testChunksOnNextPageContinuesThePartialParagraph() {
        let layout = makeMidParagraphSplitLayout()
        let page1Chunks = layout.chunks(forPage: 1)
        XCTAssertEqual(page1Chunks.map(\.paragraphIndex), [1, 2])
        XCTAssertEqual(page1Chunks[0].text, "FGHIJ")
        XCTAssertEqual(page1Chunks[1].text, "Last paragraph")
    }

    func testChunksForOutOfRangePageIndexReturnsEmpty() {
        let layout = makeMidParagraphSplitLayout()
        XCTAssertEqual(layout.chunks(forPage: -1), [])
        XCTAssertEqual(layout.chunks(forPage: 99), [])
    }

    func testPageIndexForParagraphIndexFindsTheContainingPage() {
        let layout = makeMidParagraphSplitLayout()
        // Paragraph 0 ("Hello world") starts at offset 0, entirely within page 0.
        XCTAssertEqual(layout.pageIndex(forParagraphIndex: 0), 0)
        // Paragraph 1 ("ABCDEFGHIJ") starts at offset 12, still within page 0's range [0, 17).
        XCTAssertEqual(layout.pageIndex(forParagraphIndex: 1), 0)
        // Paragraph 2 starts after page 0 ends, so it belongs to page 1.
        XCTAssertEqual(layout.pageIndex(forParagraphIndex: 2), 1)
    }

    func testPageIndexForOutOfRangeParagraphIndexFallsBackToZero() {
        let layout = makeMidParagraphSplitLayout()
        XCTAssertEqual(layout.pageIndex(forParagraphIndex: -1), 0)
        XCTAssertEqual(layout.pageIndex(forParagraphIndex: 999), 0)
    }

    func testSinglePageLayoutRoundTripsAllParagraphs() {
        let paragraphs = ["Only one page", "of content here"]
        let fullLength = (paragraphs.joined(separator: "\n") as NSString).length
        let layout = ChapterPageLayout(paragraphs: paragraphs, pages: [NSRange(location: 0, length: fullLength)])
        let chunks = layout.chunks(forPage: 0)
        XCTAssertEqual(chunks.map(\.text), paragraphs)
        XCTAssertEqual(chunks.map(\.paragraphIndex), [0, 1])
    }

    func testZeroLengthPageOnEmptyParagraphsReturnsSingleEmptyChunkNotACrash() {
        let layout = ChapterPageLayout(paragraphs: [], pages: [NSRange(location: 0, length: 0)])
        XCTAssertEqual(layout.chunks(forPage: 0), [ChapterPageLayout.Chunk(paragraphIndex: 0, text: "")])
    }

    /// Backs the long-press paragraph menu's "添加书签" action (`ReaderView.addBookmark(forParagraph:)`)
    /// -- the inverse of `paragraphIndex(forCharacterOffset:)`'s own private logic.
    func testCharacterOffsetForParagraphIndexReturnsEachParagraphsStartingOffset() {
        let layout = makeMidParagraphSplitLayout()
        // "Hello world" starts at 0; "ABCDEFGHIJ" starts right after "Hello world\n" (12); "Last
        // paragraph" starts right after that plus "ABCDEFGHIJ\n" (12 + 11 = 23).
        XCTAssertEqual(layout.characterOffset(forParagraphIndex: 0), 0)
        XCTAssertEqual(layout.characterOffset(forParagraphIndex: 1), 12)
        XCTAssertEqual(layout.characterOffset(forParagraphIndex: 2), 23)
    }

    func testCharacterOffsetForOutOfRangeParagraphIndexReturnsNil() {
        let layout = makeMidParagraphSplitLayout()
        XCTAssertNil(layout.characterOffset(forParagraphIndex: -1))
        XCTAssertNil(layout.characterOffset(forParagraphIndex: 999))
    }
}
