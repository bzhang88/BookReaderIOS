import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct RssArticle: Equatable, Sendable, Identifiable {
    public var title: String
    public var link: String
    public var pubDate: String?
    public var summary: String?

    public var id: String { link }

    public init(title: String, link: String, pubDate: String? = nil, summary: String? = nil) {
        self.title = title
        self.link = link
        self.pubDate = pubDate
        self.summary = summary
    }
}

public enum RssFeedParserError: Error, Equatable {
    case malformedXML
}

/// Parses standard RSS 2.0 (`<item>`) and Atom (`<entry>`) feeds directly via `XMLParser` --
/// deliberately doesn't support Legado's separate HTML-scraping RSS rule DSL (its own whole rule
/// surface). Real RSS/Atom feeds are standard, self-describing XML, so a real XML parser handles
/// them without per-source scraping rules at all, and unlike JavaScriptCore/CoreFoundation-gated
/// code elsewhere in this project, `XMLParser`/`FoundationXML` is fully available and testable on
/// Windows -- confirmed empirically, not assumed.
public final class RssFeedParser: NSObject {
    public static func parse(_ data: Data) throws -> [RssArticle] {
        let delegate = RssFeedParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = delegate
        let success = xmlParser.parse()
        // `parse()`'s return value alone isn't reliable -- confirmed empirically that it can
        // return true for a truncated/unclosed-tag document while still setting `parserError`, so
        // both are checked.
        guard success, xmlParser.parserError == nil else {
            throw RssFeedParserError.malformedXML
        }
        return delegate.articles
    }

    private var articles: [RssArticle] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentPubDate = ""
    private var currentSummary = ""
    private var isInsideItem = false
    private var isAtomEntry = false

    private func appendText(_ string: String) {
        guard isInsideItem else { return }
        switch currentElement {
        case "title": currentTitle += string
        case "link" where !isAtomEntry: currentLink += string
        case "pubDate", "published", "updated": currentPubDate += string
        case "description", "summary": currentSummary += string
        default: break
        }
    }
}

extension RssFeedParser: XMLParserDelegate {
    public func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        if elementName == "item" || elementName == "entry" {
            isInsideItem = true
            isAtomEntry = (elementName == "entry")
            currentTitle = ""
            currentLink = ""
            currentPubDate = ""
            currentSummary = ""
        }
        // Atom's <link href="..."/> is a self-closing element carrying its URL as an attribute,
        // not as text content the way RSS 2.0's <link>text</link> is.
        if isInsideItem, isAtomEntry, elementName == "link", let href = attributeDict["href"] {
            currentLink = href
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        appendText(string)
    }

    /// Many real-world feeds wrap title/description in `<![CDATA[...]]>` (to safely embed HTML or
    /// special characters) -- XMLParser reports that via this separate delegate method, not
    /// `foundCharacters`, so skipping this would silently produce empty titles for such feeds.
    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else { return }
        appendText(string)
    }

    public func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?
    ) {
        if elementName == "item" || elementName == "entry" {
            let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, !link.isEmpty {
                let pubDate = currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines)
                let summary = currentSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                articles.append(RssArticle(
                    title: title, link: link,
                    pubDate: pubDate.isEmpty ? nil : pubDate,
                    summary: summary.isEmpty ? nil : summary
                ))
            }
            isInsideItem = false
        }
        currentElement = ""
    }
}
