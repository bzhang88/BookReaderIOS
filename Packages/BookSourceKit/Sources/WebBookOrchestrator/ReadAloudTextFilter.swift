import Foundation

/// Whether a paragraph is worth speaking aloud at all -- matches Legado's own
/// `AppPattern.notReadAloudRegex` (`^(\s|\p{C}|\p{P}|\p{Z}|\p{S})+$`): a paragraph that's entirely
/// whitespace, punctuation, symbols, or control characters (e.g. a lone "——" scene-break marker)
/// produces an odd blip if handed straight to a speech synthesizer instead of being cleanly skipped.
/// Shared by both `ReadAloudController` (on-device `AVSpeechSynthesizer`) and
/// `HttpReadAloudController` (cloud TTS) rather than duplicated in each -- pure Foundation string
/// logic, no reason for two copies to drift.
public enum ReadAloudTextFilter {
    public static func isSpeakable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.unicodeScalars.contains { !nonSpokenCharacterSet.contains($0) }
    }

    private static let nonSpokenCharacterSet: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.formUnion(.punctuationCharacters)
        set.formUnion(.symbols)
        set.formUnion(.controlCharacters)
        return set
    }()
}
