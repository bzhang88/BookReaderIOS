import Foundation

/// Parses and applies the two index/range-selection suffixes a jsoup-mode selector step can
/// carry: the legacy `tag.div.-1:10:2` / `tag.div!0:3` dot/bang suffix (a flat list of single
/// indices), and the bracket `tag.div[-1, 3:-2:-10, 2]` / `tag.div[!0:2]` suffix (a comma list of
/// single indices and/or `start:end:step` ranges, optionally excluding).
public struct IndexSelector: Equatable {
    public enum Spec: Equatable {
        case single(Int)
        case range(start: Int?, end: Int?, step: Int)
    }

    public var specs: [Spec]
    public var exclude: Bool

    public init(specs: [Spec], exclude: Bool) {
        self.specs = specs
        self.exclude = exclude
    }

    /// Resolves this selector against a list of `count` elements, returning the selected
    /// original indices in the order they should be emitted (not necessarily sorted, unless
    /// `exclude` is set, in which case the remaining indices are returned in ascending order).
    public func apply(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var included: [Int] = []
        for spec in specs {
            switch spec {
            case .single(let i):
                if let resolved = Self.resolve(i, count: count) {
                    included.append(resolved)
                }
            case .range(let start, let end, let step):
                included.append(contentsOf: Self.expandRange(start: start, end: end, step: step, count: count))
            }
        }
        if exclude {
            let excluded = Set(included)
            return (0..<count).filter { !excluded.contains($0) }
        }
        return included
    }

    private static func resolve(_ index: Int, count: Int) -> Int? {
        let resolved = index < 0 ? index + count : index
        return (resolved >= 0 && resolved < count) ? resolved : nil
    }

    private static func expandRange(start: Int?, end: Int?, step: Int, count: Int) -> [Int] {
        let s = start ?? 0
        let e = end ?? (count - 1)
        let resolvedStart = s < 0 ? s + count : s
        let resolvedEnd = e < 0 ? e + count : e
        let strideMagnitude = max(abs(step), 1)

        var result: [Int] = []
        if resolvedEnd >= resolvedStart {
            var i = resolvedStart
            while i <= resolvedEnd {
                if i >= 0 && i < count { result.append(i) }
                i += strideMagnitude
            }
        } else {
            var i = resolvedStart
            while i >= resolvedEnd {
                if i >= 0 && i < count { result.append(i) }
                i -= strideMagnitude
            }
        }
        return result
    }

    // MARK: - Parsing

    private static let legacySuffixPattern = try! NSRegularExpression(
        pattern: #"(\.|!)(-?\d+(?::-?\d+)*)$"#
    )

    /// A bracket suffix `[...]` is only treated as an index selector if its contents look like
    /// an index/range list. Otherwise the brackets are left alone — they're presumably part of a
    /// raw CSS attribute selector like `[property=og:image]`.
    private static let bracketContentPattern = try! NSRegularExpression(
        pattern: #"^\s*!?\s*-?\d+(\s*:\s*-?\d+){0,2}(\s*,\s*-?\d+(\s*:\s*-?\d+){0,2})*\s*$"#
    )

    /// Strips a trailing index-selection suffix from `step`, if present.
    /// Returns the remaining selector text and the parsed `IndexSelector` (nil if none found).
    public static func extract(from step: String) -> (remainder: String, selector: IndexSelector?) {
        if step.hasSuffix("]"), let bracketResult = extractBracket(step) {
            return bracketResult
        }
        return extractLegacy(step)
    }

    private static func extractBracket(_ step: String) -> (remainder: String, selector: IndexSelector?)? {
        guard let openIndex = step.lastIndex(of: "[") else { return nil }
        let closeIndex = step.index(before: step.endIndex)
        guard openIndex < closeIndex else { return nil }

        let inner = String(step[step.index(after: openIndex)..<closeIndex])
        let nsInner = inner as NSString
        guard bracketContentPattern.firstMatch(in: inner, range: NSRange(location: 0, length: nsInner.length)) != nil else {
            return nil
        }

        var content = inner
        var exclude = false
        if content.hasPrefix("!") {
            exclude = true
            content = String(content.dropFirst())
        }

        let specs: [Spec] = content
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap(parseListItem)

        guard !specs.isEmpty else { return nil }
        let remainder = String(step[step.startIndex..<openIndex])
        return (remainder, IndexSelector(specs: specs, exclude: exclude))
    }

    private static func extractLegacy(_ step: String) -> (remainder: String, selector: IndexSelector?) {
        let nsStep = step as NSString
        guard let match = legacySuffixPattern.firstMatch(
            in: step, range: NSRange(location: 0, length: nsStep.length)
        ) else {
            return (step, nil)
        }

        let separator = nsStep.substring(with: match.range(at: 1))
        let indicesText = nsStep.substring(with: match.range(at: 2))
        let specs: [Spec] = indicesText
            .split(separator: ":")
            .compactMap { Int($0) }
            .map { .single($0) }

        guard !specs.isEmpty else { return (step, nil) }
        let remainder = nsStep.substring(to: match.range.location)
        return (remainder, IndexSelector(specs: specs, exclude: separator == "!"))
    }

    private static func parseListItem(_ item: String) -> Spec? {
        let parts = item.split(separator: ":", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 1 {
            guard let value = Int(parts[0]) else { return nil }
            return .single(value)
        }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let start = parts[0].isEmpty ? nil : Int(parts[0])
        let end = parts[1].isEmpty ? nil : Int(parts[1])
        if (!parts[0].isEmpty && start == nil) || (!parts[1].isEmpty && end == nil) { return nil }
        var step = 1
        if parts.count == 3 {
            guard let parsedStep = Int(parts[2]) else { return nil }
            step = parsedStep
        }
        return .range(start: start, end: end, step: step)
    }
}
