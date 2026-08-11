import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct WebDAVItem: Equatable, Sendable, Identifiable {
    public var name: String
    public var href: String
    public var isDirectory: Bool

    public var id: String { href }

    public init(name: String, href: String, isDirectory: Bool) {
        self.name = name
        self.href = href
        self.isDirectory = isDirectory
    }
}

public enum WebDAVPropfindParserError: Error, Equatable {
    case malformedXML
}

/// Parses a WebDAV PROPFIND response's `<multistatus>` body into a flat list of items -- matches
/// element names by their local name only (the part after any namespace prefix like "d:"/"D:"),
/// since different WebDAV server implementations (Nextcloud, generic Apache mod_dav, etc.) use
/// different, inconsistent prefixes for the same "DAV:" namespace elements, and a couple even omit
/// a prefix. Uses `XMLParser`/`FoundationXML` -- the same proven-on-both-Windows-and-macOS-CI
/// mechanism `RssFeedParser` already uses, not a new XML approach.
public final class WebDAVPropfindParser: NSObject {
    public static func parse(_ data: Data) throws -> [WebDAVItem] {
        let delegate = WebDAVPropfindParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = delegate
        let success = xmlParser.parse()
        // Same defensive double-check as RssFeedParser: `parse()`'s return value alone isn't
        // reliable for a truncated/malformed document.
        guard success, xmlParser.parserError == nil else {
            throw WebDAVPropfindParserError.malformedXML
        }
        return delegate.items
    }

    private var items: [WebDAVItem] = []
    private var currentHref = ""
    private var currentDisplayName = ""
    private var isInsideResponse = false
    private var isInsideResourceType = false
    private var isCollection = false
    private var isInsideHref = false
    private var isInsideDisplayName = false

    private static func localName(_ elementName: String) -> String {
        guard let colonIndex = elementName.lastIndex(of: ":") else { return elementName }
        return String(elementName[elementName.index(after: colonIndex)...])
    }
}

extension WebDAVPropfindParser: XMLParserDelegate {
    public func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        switch Self.localName(elementName).lowercased() {
        case "response":
            isInsideResponse = true
            currentHref = ""
            currentDisplayName = ""
            isCollection = false
        case "href":
            isInsideHref = true
        case "displayname":
            isInsideDisplayName = true
        case "resourcetype":
            isInsideResourceType = true
        case "collection":
            if isInsideResourceType { isCollection = true }
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideResponse else { return }
        if isInsideHref { currentHref += string }
        if isInsideDisplayName { currentDisplayName += string }
    }

    public func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?
    ) {
        switch Self.localName(elementName).lowercased() {
        case "href":
            isInsideHref = false
        case "displayname":
            isInsideDisplayName = false
        case "resourcetype":
            isInsideResourceType = false
        case "response":
            let href = currentHref.trimmingCharacters(in: .whitespacesAndNewlines)
            if !href.isEmpty {
                let trimmedPath = href.hasSuffix("/") ? String(href.dropLast()) : href
                let decodedLastSegment = trimmedPath.split(separator: "/").last
                    .map { ($0.removingPercentEncoding ?? String($0)) } ?? href
                let displayName = currentDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                items.append(WebDAVItem(
                    name: displayName.isEmpty ? decodedLastSegment : displayName,
                    href: href, isDirectory: isCollection
                ))
            }
            isInsideResponse = false
        default:
            break
        }
    }
}
