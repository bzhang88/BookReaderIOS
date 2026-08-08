import XCTest
import SwiftSoup
@testable import RuleEngine

final class RuleEngineJSONModeTests: XCTestCase {
    // Mirrors the JSONPath example source in legado-with-MD3/docs/dev/examples.md: a search API
    // response shaped like `{"..books..": [...]}` reached via recursive descent.
    private let searchResponseJSON = """
    {
        "data": {
            "books": [
                {
                    "_id": "1",
                    "title": "Book One",
                    "author": "Author A",
                    "cover": "https://x.com/1.jpg",
                    "shortIntro": "Intro one",
                    "minorCate": "Fantasy",
                    "lastChapter": "Chapter 5"
                },
                {
                    "_id": "2",
                    "title": "Book Two",
                    "author": "Author B",
                    "cover": "https://x.com/2.jpg",
                    "shortIntro": "Intro two",
                    "minorCate": "Sci-Fi",
                    "lastChapter": "Chapter 9"
                }
            ]
        }
    }
    """

    func testSearchFieldsExtractedFromRealSourceShapedRules() throws {
        let root = try JSONValue.parse(searchResponseJSON)
        let items = try RuleEngine.extractItems("$..books[*]", from: .json(root))
        XCTAssertEqual(items.count, 2)

        XCTAssertEqual(try RuleEngine.extractString("$.title", from: items[0]), "Book One")
        XCTAssertEqual(try RuleEngine.extractString("$.author", from: items[0]), "Author A")
        XCTAssertEqual(try RuleEngine.extractString("$.cover", from: items[0]), "https://x.com/1.jpg")
        XCTAssertEqual(try RuleEngine.extractString("$.shortIntro", from: items[0]), "Intro one")
        XCTAssertEqual(try RuleEngine.extractString("$.minorCate", from: items[0]), "Fantasy")

        XCTAssertEqual(try RuleEngine.extractString("$.title", from: items[1]), "Book Two")
        XCTAssertEqual(try RuleEngine.extractString("$.author", from: items[1]), "Author B")
    }

    func testTocChaptersExtractedFromRealSourceShapedRules() throws {
        let json = #"{"chapterInfo": {"chapters": [{"title": "Ch1", "link": "/c/1"}, {"title": "Ch2", "link": "/c/2"}]}}"#
        let root = try JSONValue.parse(json)
        let chapters = try RuleEngine.extractItems("$.chapterInfo.chapters.[*]", from: .json(root))
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(try RuleEngine.extractString("$.title", from: chapters[0]), "Ch1")
        XCTAssertEqual(try RuleEngine.extractString("$.link", from: chapters[0]), "/c/1")
    }

    // MARK: - Page-level JSON auto-detection

    func testUnprefixedRuleDefaultsToJSONModeWhenContentIsJSON() throws {
        // No "$." prefix at all -- relies purely on the page-level JSON sniff (see
        // JSONContentSniffer) to know this should be JSONPath, not a CSS selector.
        let root = try JSONValue.parse(#"{"author": "Jane Doe"}"#)
        XCTAssertEqual(try RuleEngine.extractString("author", from: .json(root)), "Jane Doe")
    }

    func testSameUnprefixedRuleTreatedAsCSSWhenContentIsHTML() throws {
        // The exact same bare rule text means something completely different against HTML
        // content -- this is what "page-level, not per-field" auto-detection is protecting.
        let html = "<div><p class=\"author\">Jane Doe</p></div>"
        let document = try SwiftSoup.parse(html)
        let elements = Elements()
        elements.add(document)
        XCTAssertEqual(try RuleEngine.extractString("class.author@text", from: .html(elements)), "Jane Doe")
    }

    // MARK: - Known v1 gap: embedded {$.path} URL substitution is rejected, not mis-parsed

    func testEmbeddedJSONPathURLSubstitutionThrowsRatherThanSilentlyMisparsing() {
        let root = JSONValue.object(["_id": .string("42")])
        XCTAssertThrowsError(
            try RuleEngine.extractString("/book/detail?id={$._id}", from: .json(root))
        ) { error in
            guard case .notYetImplemented = error as? RuleEngineError else {
                return XCTFail("expected .notYetImplemented, got \(error)")
            }
        }
    }
}
