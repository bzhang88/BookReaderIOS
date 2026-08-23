import XCTest
@testable import NetworkClient

final class CharsetDetectorTests: XCTestCase {
    // MARK: - Detection (portable string logic, no platform-specific decoding involved)

    func testDetectsCharsetFromContentTypeHeader() {
        let charset = CharsetDetector.detect(contentTypeHeader: "text/html; charset=gbk", rawBytes: Data())
        XCTAssertEqual(charset, "gbk")
    }

    func testContentTypeHeaderCharsetIsCaseInsensitiveKeyword() {
        let charset = CharsetDetector.detect(contentTypeHeader: "text/html; CHARSET=GBK", rawBytes: Data())
        XCTAssertEqual(charset, "GBK")
    }

    func testDetectsCharsetFromSimpleMetaTag() {
        let html = "<html><head><meta charset=\"gbk\"></head><body></body></html>"
        let charset = CharsetDetector.detect(contentTypeHeader: nil, rawBytes: Data(html.utf8))
        XCTAssertEqual(charset, "gbk")
    }

    func testDetectsCharsetFromHttpEquivMetaTag() {
        let html = "<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=gb2312\"></head></html>"
        let charset = CharsetDetector.detect(contentTypeHeader: nil, rawBytes: Data(html.utf8))
        XCTAssertEqual(charset, "gb2312")
    }

    func testHeaderTakesPrecedenceOverMetaTag() {
        let html = "<html><head><meta charset=\"gb2312\"></head></html>"
        let charset = CharsetDetector.detect(contentTypeHeader: "text/html; charset=utf-8", rawBytes: Data(html.utf8))
        XCTAssertEqual(charset, "utf-8")
    }

    func testReturnsNilWhenNoCharsetInfoIsPresent() {
        let html = "<html><head><title>No charset here</title></head></html>"
        let charset = CharsetDetector.detect(contentTypeHeader: "text/html", rawBytes: Data(html.utf8))
        XCTAssertNil(charset)
    }

    // MARK: - Decoding

    func testUnknownOrMissingCharsetDecodesAsUTF8() {
        let text = "Hello 世界"
        let data = Data(text.utf8)
        XCTAssertEqual(CharsetDetector.decode(data, charset: nil), text)
        XCTAssertEqual(CharsetDetector.decode(data, charset: "utf-8"), text)
        XCTAssertEqual(CharsetDetector.decode(data, charset: "totally-unknown-charset"), text)
    }

    #if canImport(CoreFoundation)
    func testGBKBytesDecodeCorrectlyOnApplePlatforms() {
        // GBK encoding of "中文": 0xD6D0 0xCEC4 (a standard, well-known mapping).
        let gbkBytes = Data([0xD6, 0xD0, 0xCE, 0xC4])
        XCTAssertEqual(CharsetDetector.decode(gbkBytes, charset: "gbk"), "中文")
        XCTAssertEqual(CharsetDetector.decode(gbkBytes, charset: "GB2312"), "中文")
    }
    #else
    func testGBKDecodingDegradesGracefullyWithoutCoreFoundation() {
        // On this platform (no CoreFoundation -- confirmed via canImport at build time) GBK bytes
        // can't be correctly decoded; the important thing is it degrades to *something* rather
        // than crashing, and real GBK bytes are not valid UTF-8 so the lossy path is exercised.
        let gbkBytes = Data([0xD6, 0xD0, 0xCE, 0xC4])
        let result = CharsetDetector.decode(gbkBytes, charset: "gbk")
        XCTAssertFalse(result.isEmpty)
    }
    #endif

    // MARK: - Autodetecting decode (local file import, no header/meta-tag signal available)

    func testAutodetectDecodesValidUTF8Bytes() {
        let text = "第一章 开始\n这是正文内容。"
        let data = Data(text.utf8)
        XCTAssertEqual(CharsetDetector.decodeAutodetectingBytes(data), text)
    }

    /// Real gap found comparing against Legado: a "Unicode" (UTF-16LE) save from Windows Notepad --
    /// a real, common way local TXT novels get produced -- used to fail strict UTF-8 and fall
    /// through to GB18030/lossy-UTF-8, producing garbage. Plain `Foundation` API, not gated behind
    /// `canImport(CoreFoundation)` the way GB18030/Big5 are, so this is real cross-platform coverage.
    func testAutodetectDecodesUTF16LittleEndianWithBOM() throws {
        let text = "第一章 你好，世界"
        let utf16Data = try XCTUnwrap(text.data(using: .utf16LittleEndian))
        let bom = Data([0xFF, 0xFE])
        XCTAssertEqual(CharsetDetector.decodeAutodetectingBytes(bom + utf16Data), text)
    }

    func testAutodetectDecodesUTF16BigEndianWithBOM() throws {
        let text = "第一章 你好，世界"
        let utf16Data = try XCTUnwrap(text.data(using: .utf16BigEndian))
        let bom = Data([0xFE, 0xFF])
        XCTAssertEqual(CharsetDetector.decodeAutodetectingBytes(bom + utf16Data), text)
    }

    func testAutodetectWithoutBOMIsNotMisreadAsUTF16() {
        // No BOM present -- must fall through to the UTF-8 path rather than guessing UTF-16.
        let text = "第一章 开始"
        let data = Data(text.utf8)
        XCTAssertEqual(CharsetDetector.decodeAutodetectingBytes(data), text)
    }

    #if canImport(CoreFoundation)
    func testAutodetectDecodesGBKBytesOnApplePlatforms() {
        // GBK encoding of "中文": 0xD6D0 0xCEC4 -- not a valid UTF-8 byte sequence, so strict
        // UTF-8 decoding fails and the GB18030 fallback should kick in.
        let gbkBytes = Data([0xD6, 0xD0, 0xCE, 0xC4])
        XCTAssertEqual(CharsetDetector.decodeAutodetectingBytes(gbkBytes), "中文")
    }
    #else
    func testAutodetectDegradesGracefullyWithoutCoreFoundation() {
        let gbkBytes = Data([0xD6, 0xD0, 0xCE, 0xC4])
        let result = CharsetDetector.decodeAutodetectingBytes(gbkBytes)
        XCTAssertFalse(result.isEmpty)
    }
    #endif
}
