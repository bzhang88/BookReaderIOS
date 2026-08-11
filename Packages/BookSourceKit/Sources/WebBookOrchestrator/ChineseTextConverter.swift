import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif

/// Converts between Simplified and Traditional Chinese -- some real book sources (especially ones
/// aimed at Traditional-reading regions) publish text in the "other" script from what a given
/// reader wants. Uses the OS's own bundled ICU transliterator via `CFStringTransform` rather than
/// shipping and maintaining a multi-thousand-character mapping table -- `"Simplified-Traditional"`
/// / `"Traditional-Simplified"` are standard ICU transform identifiers, the same conversion tables
/// macOS/iOS already use system-wide (e.g. the keyboard's own input conversion).
public enum ChineseTextConverter {
    public enum Direction {
        case simplifiedToTraditional
        case traditionalToSimplified
    }

    public static func convert(_ text: String, direction: Direction) -> String {
        #if canImport(CoreFoundation)
        let mutable = NSMutableString(string: text) as CFMutableString
        let transformID = (direction == .simplifiedToTraditional ? "Simplified-Traditional" : "Traditional-Simplified") as CFString
        CFStringTransform(mutable, nil, transformID, false)
        return mutable as String
        #else
        // No CoreFoundation on this platform (e.g. local Windows dev/test) -- there's no portable
        // pure-Swift simplified/traditional conversion table available here, so this returns the
        // text unchanged rather than guessing. The real iOS/macOS target has CoreFoundation and
        // converts correctly; this is a local-test-environment limitation only, same as
        // `CharsetDetector`'s GB18030/Big5 fallback.
        return text
        #endif
    }
}
