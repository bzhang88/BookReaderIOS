import XCTest
@testable import WebBookOrchestrator

final class ZipWriterTests: XCTestCase {
    /// The canonical CRC-32 test vector for the IEEE 802.3/zlib polynomial -- if this doesn't match,
    /// the table generation or bit order is wrong.
    func testCRC32MatchesTheStandardTestVector() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF43926)
    }

    func testCRC32OfEmptyDataIsZero() {
        XCTAssertEqual(CRC32.checksum(Data()), 0)
    }

    func testArchiveStartsWithLocalFileHeaderSignature() {
        var zip = ZipWriter()
        zip.addEntry(name: "mimetype", data: Data("application/epub+zip".utf8))
        let archive = zip.finalize()
        XCTAssertEqual(Array(archive.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
    }

    func testFinalizedArchiveEndsWithEndOfCentralDirectorySignature() {
        var zip = ZipWriter()
        zip.addEntry(name: "a.txt", data: Data("hello".utf8))
        zip.addEntry(name: "b.txt", data: Data("world".utf8))
        let archive = zip.finalize()
        // EOCD record is fixed at 22 bytes (no archive comment) and is always the last thing written.
        let eocd = archive.suffix(22)
        XCTAssertEqual(Array(eocd.prefix(4)), [0x50, 0x4B, 0x05, 0x06])
    }

    /// Parses the archive back out using the same layout `ZipWriter` writes (local file header ->
    /// name -> data, repeated) and checks every entry's name/bytes/CRC round-trip correctly -- the
    /// strongest self-consistency check available without a real unzip tool in the test process
    /// itself.
    func testEntriesRoundTripThroughAHandWrittenReader() {
        var zip = ZipWriter()
        zip.addEntry(name: "mimetype", data: Data("application/epub+zip".utf8))
        zip.addEntry(name: "OEBPS/chapter1.xhtml", data: Data("<html>第一章 你好</html>".utf8))
        let archive = zip.finalize()

        var offset = 0
        func readUInt16() -> UInt16 {
            let value = UInt16(archive[archive.startIndex + offset]) | (UInt16(archive[archive.startIndex + offset + 1]) << 8)
            offset += 2
            return value
        }
        func readUInt32() -> UInt32 {
            var value: UInt32 = 0
            for i in 0..<4 {
                value |= UInt32(archive[archive.startIndex + offset + i]) << (8 * i)
            }
            offset += 4
            return value
        }

        var parsedNames: [String] = []
        var parsedContents: [Data] = []
        for _ in 0..<2 {
            let signature = readUInt32()
            XCTAssertEqual(signature, 0x04034b50)
            _ = readUInt16() // version
            _ = readUInt16() // flags
            _ = readUInt16() // method
            _ = readUInt16() // time
            _ = readUInt16() // date
            let crc = readUInt32()
            let compressedSize = readUInt32()
            let uncompressedSize = readUInt32()
            XCTAssertEqual(compressedSize, uncompressedSize) // STORE-only, so these always match.
            let nameLength = Int(readUInt16())
            let extraLength = Int(readUInt16())
            let nameData = archive.subdata(in: (archive.startIndex + offset)..<(archive.startIndex + offset + nameLength))
            offset += nameLength + extraLength
            let content = archive.subdata(in: (archive.startIndex + offset)..<(archive.startIndex + offset + Int(uncompressedSize)))
            offset += Int(uncompressedSize)
            XCTAssertEqual(CRC32.checksum(content), crc)
            parsedNames.append(String(data: nameData, encoding: .utf8)!)
            parsedContents.append(content)
        }

        XCTAssertEqual(parsedNames, ["mimetype", "OEBPS/chapter1.xhtml"])
        XCTAssertEqual(String(data: parsedContents[0], encoding: .utf8), "application/epub+zip")
        XCTAssertEqual(String(data: parsedContents[1], encoding: .utf8), "<html>第一章 你好</html>")
    }
}

final class EpubExporterTests: XCTestCase {
    func testBuildsAValidZipContainer() {
        let data = EpubExporter.build(
            bookTitle: "测试书名", author: "测试作者",
            chapters: [(title: "第一章", text: "这是第一段。\n这是第二段。")]
        )
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        XCTAssertEqual(Array(data.suffix(22).prefix(4)), [0x50, 0x4B, 0x05, 0x06])
    }

    func testContainsExpectedEntryNamesAndContent() throws {
        let data = EpubExporter.build(
            bookTitle: "测试书名", author: "测试作者",
            chapters: [(title: "第一章 开始", text: "正文内容")]
        )
        let whole = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(whole.contains("mimetype"))
        XCTAssertTrue(whole.contains("application/epub+zip"))
        XCTAssertTrue(whole.contains("META-INF/container.xml"))
        XCTAssertTrue(whole.contains("OEBPS/content.opf"))
        XCTAssertTrue(whole.contains("OEBPS/toc.ncx"))
        XCTAssertTrue(whole.contains("OEBPS/chapter1.xhtml"))
        XCTAssertTrue(whole.contains("测试书名"))
        XCTAssertTrue(whole.contains("正文内容"))
    }

    func testEscapesXMLSpecialCharactersInTitleAndText() {
        let data = EpubExporter.build(
            bookTitle: "A & B <Test>", author: nil,
            chapters: [(title: "章节 <1>", text: "包含 & 符号的内容")]
        )
        let whole = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(whole.contains("A &amp; B &lt;Test&gt;"))
        XCTAssertTrue(whole.contains("章节 &lt;1&gt;"))
        XCTAssertTrue(whole.contains("包含 &amp; 符号的内容"))
        XCTAssertFalse(whole.contains("A & B <Test>"))
    }

    /// Writes a real .epub file to the OS temp directory (not asserted on -- just a side effect) so
    /// it can be opened with a real unzip tool as a one-time manual sanity check outside the test
    /// process itself, the same way `swift test` output gets checked by hand elsewhere in this
    /// project when no Mac is available to open the actual file.
    func testWritesARealFileForManualUnzipVerification() throws {
        let data = EpubExporter.build(
            bookTitle: "手动验证用书", author: "测试作者",
            chapters: [
                (title: "第一章", text: "第一段。\n第二段。"),
                (title: "第二章", text: "另一段内容。")
            ]
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("manual-verify.epub")
        try data.write(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
