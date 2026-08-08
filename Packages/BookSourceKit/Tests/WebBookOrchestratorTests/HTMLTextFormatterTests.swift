import XCTest
@testable import WebBookOrchestrator

final class HTMLTextFormatterTests: XCTestCase {
    func testParagraphTagsBecomeLineBreaks() {
        let html = "<p>First paragraph.</p><p>Second paragraph.</p>"
        XCTAssertEqual(HTMLTextFormatter.plainText(from: html), "First paragraph.\nSecond paragraph.")
    }

    func testBrTagsBecomeLineBreaks() {
        let html = "Line one<br>Line two<br/>Line three<br />Line four"
        XCTAssertEqual(HTMLTextFormatter.plainText(from: html), "Line one\nLine two\nLine three\nLine four")
    }

    func testRemainingTagsAreStripped() {
        let html = "<div><span class=\"bold\">Hello</span> <em>world</em></div>"
        XCTAssertEqual(HTMLTextFormatter.plainText(from: html), "Hello world")
    }

    func testNamedEntitiesAreUnescaped() {
        let html = "Tom &amp; Jerry &lt;3 &quot;friends&quot;&nbsp;forever"
        XCTAssertEqual(HTMLTextFormatter.plainText(from: html), "Tom & Jerry <3 \"friends\" forever")
    }

    func testNumericEntitiesAreUnescaped() {
        let html = "&#20013;&#25991; and &#x4E2D;&#x6587;"
        XCTAssertEqual(HTMLTextFormatter.plainText(from: html), "中文 and 中文")
    }

    func testBlankLinesFromTagStrippingAreDropped() {
        let html = "<p>First</p>\n\n<p></p>\n<p>Second</p>"
        XCTAssertEqual(HTMLTextFormatter.plainText(from: html), "First\nSecond")
    }
}
