import XCTest
@testable import WebBookOrchestrator

final class RssFeedParserTests: XCTestCase {
    func testParsesStandardRSS2WithPlainText() throws {
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0"><channel>
            <title>Feed Title</title>
            <item>
                <title>Article One</title>
                <link>https://example.com/1</link>
                <pubDate>Mon, 01 Jan 2026 00:00:00 GMT</pubDate>
                <description>Summary one</description>
            </item>
            <item>
                <title>Article Two</title>
                <link>https://example.com/2</link>
            </item>
        </channel></rss>
        """
        let articles = try RssFeedParser.parse(Data(xml.utf8))

        XCTAssertEqual(articles.count, 2)
        XCTAssertEqual(articles[0].title, "Article One")
        XCTAssertEqual(articles[0].link, "https://example.com/1")
        XCTAssertEqual(articles[0].pubDate, "Mon, 01 Jan 2026 00:00:00 GMT")
        XCTAssertEqual(articles[0].summary, "Summary one")
        XCTAssertEqual(articles[1].title, "Article Two")
        XCTAssertNil(articles[1].pubDate)
    }

    func testParsesCDATAWrappedFields() throws {
        let xml = """
        <rss version="2.0"><channel>
            <item>
                <title><![CDATA[Title <with> special & chars]]></title>
                <link>https://example.com/1</link>
                <description><![CDATA[<p>HTML summary</p>]]></description>
            </item>
        </channel></rss>
        """
        let articles = try RssFeedParser.parse(Data(xml.utf8))

        XCTAssertEqual(articles.count, 1)
        XCTAssertEqual(articles[0].title, "Title <with> special & chars")
        XCTAssertEqual(articles[0].summary, "<p>HTML summary</p>")
    }

    func testParsesAtomFeedWithLinkHrefAttribute() throws {
        let xml = """
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Atom Feed</title>
            <entry>
                <title>Atom Article</title>
                <link href="https://example.com/atom/1"/>
                <updated>2026-01-01T00:00:00Z</updated>
                <summary>Atom summary</summary>
            </entry>
        </feed>
        """
        let articles = try RssFeedParser.parse(Data(xml.utf8))

        XCTAssertEqual(articles.count, 1)
        XCTAssertEqual(articles[0].title, "Atom Article")
        XCTAssertEqual(articles[0].link, "https://example.com/atom/1")
        XCTAssertEqual(articles[0].pubDate, "2026-01-01T00:00:00Z")
        XCTAssertEqual(articles[0].summary, "Atom summary")
    }

    func testItemsMissingTitleOrLinkAreSkipped() throws {
        let xml = """
        <rss version="2.0"><channel>
            <item><title>Has both</title><link>https://example.com/1</link></item>
            <item><title>No link</title></item>
            <item><link>https://example.com/no-title</link></item>
        </channel></rss>
        """
        let articles = try RssFeedParser.parse(Data(xml.utf8))
        XCTAssertEqual(articles.map(\.title), ["Has both"])
    }

    func testChannelLevelTitleIsNotMistakenForAnArticle() throws {
        let xml = """
        <rss version="2.0"><channel>
            <title>Channel Title Should Not Appear As An Article</title>
            <link>https://example.com/</link>
            <item><title>Real Article</title><link>https://example.com/1</link></item>
        </channel></rss>
        """
        let articles = try RssFeedParser.parse(Data(xml.utf8))
        XCTAssertEqual(articles.count, 1)
        XCTAssertEqual(articles[0].title, "Real Article")
    }

    func testMalformedXMLThrows() {
        let xml = "<rss><channel><item><title>Unclosed"
        XCTAssertThrowsError(try RssFeedParser.parse(Data(xml.utf8))) { error in
            XCTAssertEqual(error as? RssFeedParserError, .malformedXML)
        }
    }

    func testEmptyFeedReturnsEmptyArray() throws {
        let xml = "<rss version=\"2.0\"><channel></channel></rss>"
        let articles = try RssFeedParser.parse(Data(xml.utf8))
        XCTAssertTrue(articles.isEmpty)
    }
}
