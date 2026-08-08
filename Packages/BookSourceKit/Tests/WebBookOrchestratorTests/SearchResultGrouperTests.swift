import XCTest
@testable import WebBookOrchestrator

final class SearchResultGrouperTests: XCTestCase {
    private func result(
        source: String, name: String, author: String? = "Author A", intro: String? = nil,
        lastChapter: String? = nil, coverUrl: String? = nil
    ) -> SearchResult {
        SearchResult(
            bookSourceUrl: "https://\(source).example.com", bookSourceName: source, name: name, author: author,
            intro: intro, lastChapter: lastChapter, bookUrl: "https://\(source).example.com/book/1", coverUrl: coverUrl
        )
    }

    func testSameNameAndAuthorFromDifferentSourcesAreGroupedTogether() {
        let a = result(source: "SiteA", name: "凡人修仙传")
        let b = result(source: "SiteB", name: "凡人修仙传")

        let groups = SearchResultGrouper.merge([a], into: [])
        let merged = SearchResultGrouper.merge([b], into: groups)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].sourceCount, 2)
        XCTAssertEqual(merged[0].entries.map(\.bookSourceName), ["SiteA", "SiteB"])
    }

    func testDifferentAuthorsWithSameTitleAreNotMerged() {
        let a = result(source: "SiteA", name: "Same Title", author: "Author One")
        let b = result(source: "SiteB", name: "Same Title", author: "Author Two")

        let groups = SearchResultGrouper.merge([a, b], into: [])

        XCTAssertEqual(groups.count, 2, "different authors under the same title must not be merged as if they were the same book")
    }

    func testNewBooksAreAppendedAfterExistingGroupsPreservingOrder() {
        let first = result(source: "SiteA", name: "Book One")
        let second = result(source: "SiteA", name: "Book Two")
        let firstAgain = result(source: "SiteB", name: "Book One")

        var groups = SearchResultGrouper.merge([first, second], into: [])
        groups = SearchResultGrouper.merge([firstAgain], into: groups)

        XCTAssertEqual(groups.map(\.name), ["Book One", "Book Two"], "existing group order must be preserved across merges")
        XCTAssertEqual(groups[0].sourceCount, 2)
        XCTAssertEqual(groups[1].sourceCount, 1)
    }

    func testIntroPrefersTheLongestAvailableAcrossSources() {
        let short = result(source: "SiteA", name: "Book", intro: "Short.")
        let long = result(source: "SiteB", name: "Book", intro: "A much longer and more detailed introduction.")

        let groups = SearchResultGrouper.merge([short, long], into: [])

        XCTAssertEqual(groups[0].intro, long.intro)
    }

    func testLastChapterAndCoverFallBackToFirstEntryThatHasOne() {
        let noExtras = result(source: "SiteA", name: "Book", lastChapter: nil, coverUrl: nil)
        let withExtras = result(source: "SiteB", name: "Book", lastChapter: "Chapter 5", coverUrl: "https://example.com/cover.jpg")

        let groups = SearchResultGrouper.merge([noExtras, withExtras], into: [])

        XCTAssertEqual(groups[0].lastChapter, "Chapter 5")
        XCTAssertEqual(groups[0].coverUrl, "https://example.com/cover.jpg")
    }

    func testNameAndAuthorWhitespaceIsTrimmedBeforeComparing() {
        let a = result(source: "SiteA", name: " 三体 ", author: " 刘慈欣")
        let b = result(source: "SiteB", name: "三体", author: "刘慈欣 ")

        let groups = SearchResultGrouper.merge([a, b], into: [])

        XCTAssertEqual(groups.count, 1, "whitespace differences alone shouldn't split what's really the same book")
    }
}
