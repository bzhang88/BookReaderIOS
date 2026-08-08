import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif

/// Detects and decodes a response body's real character encoding. Real-world Chinese novel
/// sites are frequently GBK/GB2312/GB18030 (confirmed against real book-source data, not
/// theoretical — see the project plan's progress log), not UTF-8, and decoding a GBK page as
/// UTF-8 silently produces garbage text rather than an error, which is worse than failing loudly.
public enum CharsetDetector {
    /// Detection order matches how browsers actually resolve this: the HTTP `Content-Type`
    /// header first, then a `<meta charset>`/`<meta http-equiv=Content-Type>` tag sniffed from
    /// the raw bytes. The meta-tag scan reads the bytes as ISO-Latin-1 (byte-for-byte, no
    /// interpretation) rather than the page's real encoding — safe because HTML tag structure is
    /// always plain ASCII regardless of the body's actual charset, so this doesn't need to know
    /// the encoding to find the encoding.
    public static func detect(contentTypeHeader: String?, rawBytes: Data) -> String? {
        if let header = contentTypeHeader, let charset = charset(fromContentType: header) {
            return charset
        }
        return charset(fromMetaTag: rawBytes)
    }

    public static func decode(_ data: Data, charset: String?) -> String {
        let normalized = charset?.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")

        switch normalized {
        case "gbk", "gb2312", "gb18030":
            return decodeGB18030(data) ?? decodeUTF8Lossy(data)
        case "big5":
            return decodeBig5(data) ?? decodeUTF8Lossy(data)
        default:
            // Includes "utf8"/nil/anything unrecognized -- UTF-8 is both the modern default and
            // the safe fallback when detection found nothing.
            return decodeUTF8Lossy(data)
        }
    }

    private static func decodeUTF8Lossy(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    // MARK: - GB/Big5 decoding (Apple platforms only)

    // CoreFoundation's CFStringEncodings enum (GB_18030_2000, big5, ...) only exists on Apple
    // platforms -- there is no portable pure-Swift GB18030/Big5 decoder available here, and
    // writing a full table-based one is out of scope for v1. On non-Apple platforms (i.e. this
    // Windows dev machine) this degrades to a lossy UTF-8 decode, which is a *local test
    // environment* limitation, not a real-product one: the actual iOS target has CoreFoundation
    // and decodes these correctly.
    #if canImport(CoreFoundation)
    private static func decodeGB18030(_ data: Data) -> String? {
        let cfEncoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: cfEncoding))
    }

    private static func decodeBig5(_ data: Data) -> String? {
        let cfEncoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: cfEncoding))
    }
    #else
    private static func decodeGB18030(_ data: Data) -> String? { nil }
    private static func decodeBig5(_ data: Data) -> String? { nil }
    #endif

    // MARK: - Detection helpers

    private static func charset(fromContentType header: String) -> String? {
        guard let range = header.range(of: "charset=", options: .caseInsensitive) else { return nil }
        var value = header[range.upperBound...]
        if let semicolon = value.firstIndex(of: ";") { value = value[..<semicolon] }
        let trimmed = value.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func charset(fromMetaTag rawBytes: Data) -> String? {
        let head = rawBytes.prefix(4096)
        guard let ascii = String(data: head, encoding: .isoLatin1) else { return nil }
        return firstMatch(#"<meta[^>]+charset\s*=\s*["']?([a-zA-Z0-9_-]+)"#, in: ascii)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
}
