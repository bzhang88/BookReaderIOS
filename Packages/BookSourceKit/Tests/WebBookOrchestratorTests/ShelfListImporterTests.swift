import XCTest
import BookSourceModel
import NetworkClient
@testable import WebBookOrchestrator

final class ShelfListImporterTests: XCTestCase {
    private func makeSource(name: String, url: String) -> BookSource {
        var rule = SearchRule()
        rule.bookList = "@css:.item"
        rule.name = "@css:.name@text"
        rule.author = "@css:.author@text"
        rule.bookUrl = "@css:.name@href"
        return BookSource(
            bookSourceUrl: url, bookSourceName: name, searchUrl: "\(url)/search?wd=fixed", ruleSearch: rule
        )
    }

    private func html(name: String, author: String) -> String {
        """
        <ul><li class="item"><a class="name" href="/book/1">\(name)</a><span class="author">\(author)</span></li></ul>
        """
    }

    func testResolvesExactNameAndAuthorMatch() async {
        let source = makeSource(name: "S1", url: "https://s1.example.com")
        let client = StubHTTPClient(responses: [
            "https://s1.example.com/search?wd=fixed": html(name: "斗破苍穹", author: "天蚕土豆")
        ])
        let entries = [ShelfListEntry(name: "斗破苍穹", author: "天蚕土豆")]

        let (matches, unmatched) = await ShelfListImporter.resolve(entries: entries, sources: [source], httpClient: client)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.source.bookSourceUrl, "https://s1.example.com")
        XCTAssertTrue(unmatched.isEmpty)
    }

    func testAuthorMismatchIsUnmatchedRatherThanAFalsePositive() async {
        let source = makeSource(name: "S1", url: "https://s1.example.com")
        let client = StubHTTPClient(responses: [
            "https://s1.example.com/search?wd=fixed": html(name: "斗破苍穹", author: "另一个作者")
        ])
        let entries = [ShelfListEntry(name: "斗破苍穹", author: "天蚕土豆")]

        let (matches, unmatched) = await ShelfListImporter.resolve(entries: entries, sources: [source], httpClient: client)

        XCTAssertTrue(matches.isEmpty)
        XCTAssertEqual(unmatched, entries)
    }

    func testEntryWithNoAuthorOnlyMatchesResultWithNoAuthor() async {
        let source = makeSource(name: "S1", url: "https://s1.example.com")
        let client = StubHTTPClient(responses: [
            "https://s1.example.com/search?wd=fixed": html(name: "无名书", author: "")
        ])
        let entries = [ShelfListEntry(name: "无名书")]

        let (matches, unmatched) = await ShelfListImporter.resolve(entries: entries, sources: [source], httpClient: client)

        XCTAssertEqual(matches.count, 1)
        XCTAssertTrue(unmatched.isEmpty)
    }

    func testNoSourceHasTheBookLeavesEntryUnmatched() async {
        let source = makeSource(name: "S1", url: "https://s1.example.com")
        let client = StubHTTPClient(responses: [
            "https://s1.example.com/search?wd=fixed": html(name: "别的书", author: "别的作者")
        ])
        let entries = [ShelfListEntry(name: "斗破苍穹", author: "天蚕土豆")]

        let (matches, unmatched) = await ShelfListImporter.resolve(entries: entries, sources: [source], httpClient: client)

        XCTAssertTrue(matches.isEmpty)
        XCTAssertEqual(unmatched, entries)
    }

    func testBlankNameEntryIsSkippedEntirely() async {
        let source = makeSource(name: "S1", url: "https://s1.example.com")
        let client = StubHTTPClient(responses: [:])
        let entries = [ShelfListEntry(name: "   ")]

        let (matches, unmatched) = await ShelfListImporter.resolve(entries: entries, sources: [source], httpClient: client)

        XCTAssertTrue(matches.isEmpty)
        XCTAssertTrue(unmatched.isEmpty, "a blank name isn't a real entry to report as unmatched, just skipped")
    }

    func testFindsMatchOnASecondSourceAfterFirstHasNoResult() async {
        let sourceA = makeSource(name: "A", url: "https://a.example.com")
        let sourceB = makeSource(name: "B", url: "https://b.example.com")
        let client = StubHTTPClient(responses: [
            "https://a.example.com/search?wd=fixed": html(name: "别的书", author: "别的作者"),
            "https://b.example.com/search?wd=fixed": html(name: "斗破苍穹", author: "天蚕土豆")
        ])
        let entries = [ShelfListEntry(name: "斗破苍穹", author: "天蚕土豆")]

        let (matches, unmatched) = await ShelfListImporter.resolve(entries: entries, sources: [sourceA, sourceB], httpClient: client)

        XCTAssertEqual(matches.first?.source.bookSourceUrl, "https://b.example.com")
        XCTAssertTrue(unmatched.isEmpty)
    }
}
