import XCTest
@testable import NetworkClient

final class WebDAVPropfindParserTests: XCTestCase {
    func testParsesResponsesWithUppercaseDPrefix() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:multistatus xmlns:D="DAV:">
          <D:response>
            <D:href>/dav/Books/</D:href>
            <D:propstat>
              <D:prop>
                <D:displayname>Books</D:displayname>
                <D:resourcetype><D:collection/></D:resourcetype>
              </D:prop>
              <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
          </D:response>
          <D:response>
            <D:href>/dav/Books/novel1.txt</D:href>
            <D:propstat>
              <D:prop>
                <D:displayname>novel1.txt</D:displayname>
                <D:resourcetype/>
              </D:prop>
              <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
          </D:response>
        </D:multistatus>
        """
        let items = try WebDAVPropfindParser.parse(Data(xml.utf8))
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].name, "Books")
        XCTAssertTrue(items[0].isDirectory)
        XCTAssertEqual(items[1].name, "novel1.txt")
        XCTAssertFalse(items[1].isDirectory)
    }

    func testParsesResponsesWithLowercaseDPrefix() throws {
        let xml = """
        <?xml version="1.0"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response>
            <d:href>/dav/novel2.txt</d:href>
            <d:propstat>
              <d:prop>
                <d:displayname>novel2.txt</d:displayname>
                <d:resourcetype/>
              </d:prop>
            </d:propstat>
          </d:response>
        </d:multistatus>
        """
        let items = try WebDAVPropfindParser.parse(Data(xml.utf8))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "novel2.txt")
        XCTAssertFalse(items[0].isDirectory)
    }

    func testFallsBackToHrefLastSegmentWhenDisplayNameIsMissing() throws {
        let xml = """
        <D:multistatus xmlns:D="DAV:">
          <D:response>
            <D:href>/dav/Books/%E5%B0%8F%E8%AF%B4.txt</D:href>
            <D:propstat>
              <D:prop>
                <D:resourcetype/>
              </D:prop>
            </D:propstat>
          </D:response>
        </D:multistatus>
        """
        let items = try WebDAVPropfindParser.parse(Data(xml.utf8))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "小说.txt")
    }

    func testDirectoryDetectionRequiresCollectionInsideResourceType() throws {
        let xml = """
        <D:multistatus xmlns:D="DAV:">
          <D:response>
            <D:href>/dav/plainfile.txt</D:href>
            <D:propstat>
              <D:prop>
                <D:displayname>plainfile.txt</D:displayname>
                <D:resourcetype/>
              </D:prop>
            </D:propstat>
          </D:response>
          <D:response>
            <D:href>/dav/subfolder/</D:href>
            <D:propstat>
              <D:prop>
                <D:displayname>subfolder</D:displayname>
                <D:resourcetype><D:collection/></D:resourcetype>
              </D:prop>
            </D:propstat>
          </D:response>
        </D:multistatus>
        """
        let items = try WebDAVPropfindParser.parse(Data(xml.utf8))
        XCTAssertEqual(items.first(where: { $0.name == "plainfile.txt" })?.isDirectory, false)
        XCTAssertEqual(items.first(where: { $0.name == "subfolder" })?.isDirectory, true)
    }

    func testEmptyMultistatusReturnsEmptyList() throws {
        let xml = """
        <D:multistatus xmlns:D="DAV:"></D:multistatus>
        """
        let items = try WebDAVPropfindParser.parse(Data(xml.utf8))
        XCTAssertTrue(items.isEmpty)
    }

    func testMalformedXMLThrows() {
        let xml = "<D:multistatus><D:response>unclosed"
        XCTAssertThrowsError(try WebDAVPropfindParser.parse(Data(xml.utf8)))
    }
}
