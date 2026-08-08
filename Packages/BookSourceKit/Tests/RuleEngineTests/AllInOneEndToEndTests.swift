import XCTest
import SwiftSoup
@testable import RuleEngine

final class AllInOneEndToEndTests: XCTestCase {
    /// Mirrors the real chapterList/chapterName/chapterUrl AllInOne example from
    /// legado-with-MD3/docs/dev/examples.md:
    ///   "chapterList": "-:<li><a[^\"]+\"([^\"]*)\">([^<]*)"
    ///   "chapterName": "$2"
    ///   "chapterUrl": "$1"
    func testChapterListAllInOneWithSiblingCaptureGroupReferences() throws {
        let html = "<ul><li><a href=\"/c/1\">Chapter 1</a></li><li><a href=\"/c/2\">Chapter 2</a></li></ul>"
        let document = try SwiftSoup.parse(html)
        let elements = Elements()
        elements.add(document)
        let content = RuleContent.html(elements)

        let (chapterListRule, reversed) = ListRulePrefix.strip("-:<li><a[^\"]+\"([^\"]*)\">([^<]*)")
        XCTAssertTrue(reversed)

        let items = try RuleEngine.extractItems(chapterListRule, from: content)
        XCTAssertEqual(items.count, 2)

        let names = try items.map { try RuleEngine.extractString("$2", from: $0) }
        let urls = try items.map { try RuleEngine.extractString("$1", from: $0) }

        XCTAssertEqual(names, ["Chapter 1", "Chapter 2"])
        XCTAssertEqual(urls, ["/c/1", "/c/2"])
    }
}
