import Foundation
import SwiftSoup

/// Evaluates jsoup-backed rule strings: the Default dot-chain mode (`class.foo@tag.a@text`) and
/// the `@css:` single-selector mode (`@css:.foo@text`). Both ultimately select `Elements` and
/// then, for string extraction, dispatch a keyword (`text`/`html`/`ownText`/... or an attribute
/// name) against the final selection.
public enum CSSChainEvaluator {
    /// Selects elements for a rule where *every* `@`-separated step is a selecting step — used
    /// for `bookList`/`chapterList`-style rules where the caller wants the matched container
    /// elements themselves, not an extracted string.
    public static func evaluateElements(_ selector: String, root: Elements) throws -> Elements {
        let steps = chainSteps(selector)
        var elements = root
        for step in steps {
            elements = try selectStep(step, from: elements)
        }
        return elements
    }

    /// Extracts strings for a Default-mode chain, where the *last* `@`-separated step is a
    /// keyword (`text`, `html`, an attribute name, ...) rather than a selecting step.
    public static func extractStrings(chain selector: String, root: Elements) throws -> [String] {
        var steps = chainSteps(selector)
        guard !steps.isEmpty else { return [] }
        let keywordStep = steps.removeLast()

        var elements = root
        for step in steps {
            elements = try selectStep(step, from: elements)
        }
        return try extractKeyword(keywordStep, from: elements)
    }

    /// Extracts strings for `@css:selector@keyword` mode: exactly one plain CSS selector (no
    /// multi-step chaining), split off the *last* `@` only.
    public static func extractStrings(cssSingle selector: String, root: Elements) throws -> [String] {
        guard let atIndex = selector.lastIndex(of: "@") else {
            let matched = try selectRawCSS(selector.trimmingCharacters(in: .whitespaces), from: root)
            return try extractKeyword("text", from: matched)
        }
        let selectorPart = String(selector[selector.startIndex..<atIndex]).trimmingCharacters(in: .whitespaces)
        let keywordPart = String(selector[selector.index(after: atIndex)...]).trimmingCharacters(in: .whitespaces)
        let matched = try selectRawCSS(selectorPart, from: root)
        return try extractKeyword(keywordPart, from: matched)
    }

    // MARK: - Chain splitting

    private static func chainSteps(_ selector: String) -> [String] {
        var trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("@") {
            trimmed = String(trimmed.dropFirst())
        }
        return BalancedScanner.split(trimmed, by: "@")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Step selection

    private static func selectStep(_ step: String, from elements: Elements) throws -> Elements {
        let (core, indexSelector) = IndexSelector.extract(from: step)
        let trimmedCore = core.trimmingCharacters(in: .whitespaces)
        var result: Elements

        if trimmedCore.isEmpty || trimmedCore.lowercased() == "children" {
            result = Elements()
            for el in elements.array() {
                for child in el.children().array() { result.add(child) }
            }
        } else if let name = suffix(after: "class.", in: trimmedCore) {
            result = Elements()
            for el in elements.array() {
                for match in try el.getElementsByClass(name).array() { result.add(match) }
            }
        } else if let name = suffix(after: "tag.", in: trimmedCore) {
            result = Elements()
            for el in elements.array() {
                for match in try el.getElementsByTag(name).array() { result.add(match) }
            }
        } else if let name = suffix(after: "id.", in: trimmedCore) {
            result = Elements()
            for el in elements.array() {
                if let match = try el.getElementById(name) { result.add(match) }
            }
        } else if let name = suffix(after: "text.", in: trimmedCore) {
            result = Elements()
            for el in elements.array() {
                for match in try el.getElementsContainingOwnText(name).array() { result.add(match) }
            }
        } else {
            result = try selectRawCSS(trimmedCore, from: elements)
        }

        guard let indexSelector else { return result }
        let all = result.array()
        let picked = indexSelector.apply(count: all.count).map { all[$0] }
        let selected = Elements()
        for el in picked { selected.add(el) }
        return selected
    }

    private static func selectRawCSS(_ cssSelector: String, from elements: Elements) throws -> Elements {
        let result = Elements()
        for el in elements.array() {
            for match in try el.select(cssSelector).array() { result.add(match) }
        }
        return result
    }

    private static func suffix(after prefix: String, in text: String) -> String? {
        guard text.lowercased().hasPrefix(prefix) else { return nil }
        return String(text.dropFirst(prefix.count))
    }

    // MARK: - Keyword extraction (last step of a chain)

    private static func extractKeyword(_ rawKeyword: String, from elements: Elements) throws -> [String] {
        let keyword = rawKeyword.trimmingCharacters(in: .whitespaces)
        switch keyword.lowercased() {
        case "text":
            return try elements.array().map { try $0.text() }
        case "textnodes":
            return elements.array().map { el in
                el.textNodes().map { $0.text() }.joined(separator: "\n")
            }
        case "owntext":
            return elements.array().map { $0.ownText() }
        case "html":
            return try elements.array().map { stripScriptAndStyle(try $0.outerHtml()) }
        case "all":
            return [try elements.outerHtml()]
        default:
            // Anything else is an HTML attribute name (href, src, data-*, ...).
            return try elements.array().compactMap { el in
                let value = try el.attr(keyword)
                return value.isEmpty ? nil : value
            }
        }
    }

    private static let scriptStylePattern = try! NSRegularExpression(
        pattern: #"<script[\s\S]*?</script>|<style[\s\S]*?</style>"#,
        options: [.caseInsensitive]
    )

    private static func stripScriptAndStyle(_ html: String) -> String {
        let ns = html as NSString
        return scriptStylePattern.stringByReplacingMatches(
            in: html, range: NSRange(location: 0, length: ns.length), withTemplate: ""
        )
    }
}
