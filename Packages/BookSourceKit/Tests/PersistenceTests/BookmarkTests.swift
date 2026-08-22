import XCTest
@testable import Persistence

final class BookmarkTests: XCTestCase {
    func testMakeExcerptCollapsesNewlinesAndTrims() {
        let excerpt = Bookmark.makeExcerpt(from: "  第一行\n第二行  \n")
        XCTAssertEqual(excerpt, "第一行 第二行")
    }

    func testMakeExcerptReturnsNilForAllWhitespace() {
        XCTAssertNil(Bookmark.makeExcerpt(from: "   \n\n  "))
    }

    func testMakeExcerptTruncatesLongPassagesWithEllipsis() {
        let longText = String(repeating: "字", count: 100)
        let excerpt = Bookmark.makeExcerpt(from: longText, maxLength: 60)
        XCTAssertEqual(excerpt?.count, 61) // 60 characters + the ellipsis mark
        XCTAssertTrue(excerpt?.hasSuffix("…") ?? false)
    }

    /// Migration-safety case: `excerpt` didn't exist before this field was added -- guards that
    /// decoding an old `bookmarks.json` (missing the key entirely) doesn't throw.
    func testDecodesPreExistingBookmarkJSONMissingExcerptField() throws {
        let json = """
        {
            "id": "abc", "isLocal": false, "bookIdentifier": "https://example.com/book/1",
            "bookTitle": "My Novel", "chapterIndex": 0, "chapterTitle": "Chapter 1",
            "createdAt": "2023-11-14T22:13:20Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bookmark = try decoder.decode(Bookmark.self, from: Data(json.utf8))
        XCTAssertNil(bookmark.excerpt)
    }
}
