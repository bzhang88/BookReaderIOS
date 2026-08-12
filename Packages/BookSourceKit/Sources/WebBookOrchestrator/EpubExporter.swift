import Foundation

/// Builds a minimal, spec-valid EPUB 2 file (OPF package + NCX navigation + one XHTML file per
/// chapter) via `ZipWriter` -- the only local export this app had before was plain TXT
/// (`TxtExporter`); EPUB is the other format real e-readers (and Legado itself) commonly expect.
/// EPUB 2 rather than 3 -- its OPF/NCX shape is simpler and still universally readable by every
/// modern EPUB app, and this app has no per-chapter semantic structure (headings, images, etc.)
/// that would actually benefit from EPUB 3's richer markup.
public enum EpubExporter {
    public static func build(bookTitle: String, author: String?, chapters: [(title: String, text: String)]) -> Data {
        var zip = ZipWriter()
        // Must be the very first entry, stored (not compressed) -- `ZipWriter` only ever stores, so
        // that half of the requirement is automatic; ordering is guaranteed by adding it first.
        zip.addEntry(name: "mimetype", data: Data("application/epub+zip".utf8))
        zip.addEntry(name: "META-INF/container.xml", data: Data(containerXML.utf8))
        zip.addEntry(name: "OEBPS/content.opf", data: Data(contentOPF(bookTitle: bookTitle, author: author, chapters: chapters).utf8))
        zip.addEntry(name: "OEBPS/toc.ncx", data: Data(tocNCX(bookTitle: bookTitle, chapters: chapters).utf8))
        for (index, chapter) in chapters.enumerated() {
            zip.addEntry(name: "OEBPS/chapter\(index + 1).xhtml", data: Data(chapterXHTML(title: chapter.title, text: chapter.text).utf8))
        }
        return zip.finalize()
    }

    private static let containerXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """

    private static func contentOPF(bookTitle: String, author: String?, chapters: [(title: String, text: String)]) -> String {
        let manifestItems = chapters.indices.map { index in
            "    <item id=\"chapter\(index + 1)\" href=\"chapter\(index + 1).xhtml\" media-type=\"application/xhtml+xml\"/>"
        }.joined(separator: "\n")
        let spineItems = chapters.indices.map { index in
            "    <itemref idref=\"chapter\(index + 1)\"/>"
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="BookId">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>\(bookTitle.xmlEscaped)</dc:title>
            <dc:creator>\((author ?? "佚名").xmlEscaped)</dc:creator>
            <dc:language>zh</dc:language>
            <dc:identifier id="BookId">urn:uuid:\(UUID().uuidString)</dc:identifier>
          </metadata>
          <manifest>
        \(manifestItems)
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
          </manifest>
          <spine toc="ncx">
        \(spineItems)
          </spine>
        </package>
        """
    }

    private static func tocNCX(bookTitle: String, chapters: [(title: String, text: String)]) -> String {
        let navPoints = chapters.indices.map { index in
            """
                <navPoint id="navPoint-\(index + 1)" playOrder="\(index + 1)">
                  <navLabel><text>\(chapters[index].title.xmlEscaped)</text></navLabel>
                  <content src="chapter\(index + 1).xhtml"/>
                </navPoint>
            """
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <head>
            <meta name="dtb:uid" content="urn:uuid:\(UUID().uuidString)"/>
          </head>
          <docTitle><text>\(bookTitle.xmlEscaped)</text></docTitle>
          <navMap>
        \(navPoints)
          </navMap>
        </ncx>
        """
    }

    private static func chapterXHTML(title: String, text: String) -> String {
        let paragraphs = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { "  <p>\($0.xmlEscaped)</p>" }
            .joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>\(title.xmlEscaped)</title></head>
        <body>
          <h1>\(title.xmlEscaped)</h1>
        \(paragraphs)
        </body>
        </html>
        """
    }
}

private extension String {
    /// The 5 characters XML requires escaping in text content/attribute values -- `&` first, so it
    /// doesn't double-escape the ampersands this same call just introduced for the other 4.
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
