import UIKit

/// Splits chapter text into real, screen-measured pages -- SwiftUI has no "how much text fits in
/// this frame" API of its own, so this uses the standard TextKit pagination recipe: attach one
/// shared `NSLayoutManager`/`NSTextStorage` pair, then repeatedly hand it a fresh `NSTextContainer`
/// sized to one page and ask how many characters it laid out before running out of room. Each
/// container "picks up" exactly where the previous one's layout left off, so walking through
/// containers this way naturally produces page breaks using the *actual* font metrics that will
/// render on screen, not an approximate character-count guess.
///
/// This is UIKit (`NSLayoutManager`/`NSTextContainer` come from UIKit on iOS, not from a
/// cross-platform Foundation type), so unlike the rest of this reader's rendering it can only be
/// exercised by the iOS-targeting CI steps (Build Unsigned IPA / UI Screenshot) -- `swift test`
/// runs on bare macOS, which doesn't have UIKit either, so there's no way to unit-test this file's
/// actual behavior from this project's usual Windows+`swift test` loop. Actual on-screen rendering
/// still goes through SwiftUI `Text` (for consistency with the rest of the reader, and because a
/// hand-rolled `UITextView`/`NSTextContainer` swap-per-page view would be a much larger, riskier
/// surface); the two engines can in principle disagree by a line at a page boundary in rare cases
/// (different ligature/line-breaking edge cases) -- an accepted approximation for this first pass,
/// not a bug.
enum ChapterPaginator {
    /// Character ranges (into `text`, as `NSString` indices) for each page, in order.
    static func paginate(
        text: String, font: UIFont, lineSpacing: CGFloat, paragraphSpacing: CGFloat, pageSize: CGSize
    ) -> [NSRange] {
        let fullLength = (text as NSString).length
        guard pageSize.width > 0, pageSize.height > 0, fullLength > 0 else {
            return [NSRange(location: 0, length: fullLength)]
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = paragraphSpacing
        let textStorage = NSTextStorage(
            string: text, attributes: [.font: font, .paragraphStyle: paragraphStyle]
        )
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        var pages: [NSRange] = []
        var consumedLength = 0
        // A run of the same size that produces literally zero progress would loop forever; this is
        // a defensive backstop, not an expected outcome (an empty container size is already caught
        // above, and a container the size of a whole screen should always fit at least one glyph).
        var guardCounter = 0
        while consumedLength < fullLength, guardCounter < fullLength + 1 {
            guardCounter += 1
            let container = NSTextContainer(size: pageSize)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            let glyphRange = layoutManager.glyphRange(for: container)
            guard glyphRange.length > 0 else { break }
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            pages.append(charRange)
            consumedLength = charRange.location + charRange.length
        }
        return pages.isEmpty ? [NSRange(location: 0, length: fullLength)] : pages
    }
}
