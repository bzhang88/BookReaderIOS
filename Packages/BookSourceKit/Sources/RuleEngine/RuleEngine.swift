import Foundation
import SwiftSoup

/// Top-level façade: mode-detect (JSON-content-aware) → combinator-split → per-branch evaluate →
/// combine → apply trailing regex suffix. XPath is detected but throws; `<js>`/`@js:`/`{{ }}` are
/// detected in `RuleStringParser` and throw `.notYetImplemented` until Phase 2's JS work lands
/// (blocked on JavaScriptCore, which only exists on Apple platforms — see `JSRuntime`).
public enum RuleEngine {
    /// Extracts a list of strings from `content` for a single rule field.
    public static func extractStringList(_ rule: String, from content: RuleContent) throws -> [String] {
        let parsed = try RuleStringParser.parse(rule, contentIsJSON: content.isJSON)
        let (combinator, parts) = CombinatorSplitter.split(parsed.selector)

        let branches: [[String]] = try parts.map { part in
            try evaluateBranch(mode: parsed.mode, selector: part, content: content)
        }
        let combined = combine(branches, combinator: combinator)

        guard let suffix = parsed.regexSuffix else { return combined }
        return combined.map { RegexSuffixParser.apply(suffix, to: $0) }
    }

    /// Convenience for fields that only ever want a single value: the first extracted string.
    public static func extractString(_ rule: String, from content: RuleContent) throws -> String? {
        try extractStringList(rule, from: content).first
    }

    /// Extracts a list of *items* for a `bookList`/`chapterList`-style rule, preserving each
    /// item's content type (HTML element or JSON value) so per-item sub-field rules can be
    /// evaluated against it in turn without re-sniffing.
    public static func extractItems(_ rule: String, from content: RuleContent) throws -> [RuleContent] {
        let parsed = try RuleStringParser.parse(rule, contentIsJSON: content.isJSON)

        switch parsed.mode {
        case .defaultChain, .cssSingle:
            guard case .html(let root) = content else {
                throw RuleEngineError.invalidRule("Default/CSS rule applied to non-HTML content")
            }
            let (combinator, parts) = CombinatorSplitter.split(parsed.selector)
            var branches: [Elements] = []
            for part in parts {
                let selectorText = elementsSelector(for: parsed.mode, rawPart: part)
                let matched = try CSSChainEvaluator.evaluateElements(selectorText, root: root)
                branches.append(matched)
                if combinator == .firstNonEmpty && !matched.array().isEmpty { break }
            }
            return mergeElements(branches, combinator: combinator).array().map { RuleContent.html(rootElement: $0) }

        case .json:
            guard case .json(let root) = content else {
                throw RuleEngineError.invalidRule("JSON rule applied to non-JSON content")
            }
            let values = JSONPathEvaluator.extractValues(parsed.selector, from: root)
            return values.map { RuleContent.json($0) }

        case .xpath:
            throw RuleEngineError.unsupportedFeature(.xpath)
        }
    }

    // MARK: - Branch evaluation

    private static func evaluateBranch(mode: RuleMode, selector: String, content: RuleContent) throws -> [String] {
        switch mode {
        case .defaultChain, .cssSingle:
            guard case .html(let root) = content else {
                throw RuleEngineError.invalidRule("Default/CSS rule applied to non-HTML content")
            }
            return mode == .cssSingle
                ? try CSSChainEvaluator.extractStrings(cssSingle: selector, root: root)
                : try CSSChainEvaluator.extractStrings(chain: selector, root: root)
        case .json:
            guard case .json(let root) = content else {
                throw RuleEngineError.invalidRule("JSON rule applied to non-JSON content")
            }
            return JSONPathEvaluator.extractStrings(selector, from: root)
        case .xpath:
            throw RuleEngineError.unsupportedFeature(.xpath)
        }
    }

    /// `@css:` mode's elements-selection ignores a trailing `@keyword`, if present — rare for
    /// `bookList`-style rules, but harmless to tolerate.
    private static func elementsSelector(for mode: RuleMode, rawPart: String) -> String {
        let trimmed = rawPart.trimmingCharacters(in: .whitespaces)
        guard mode == .cssSingle, let atIndex = trimmed.lastIndex(of: "@") else { return trimmed }
        return String(trimmed[trimmed.startIndex..<atIndex])
    }

    // MARK: - Combining

    private static func combine(_ branches: [[String]], combinator: Combinator?) -> [String] {
        guard let combinator else { return branches.first ?? [] }
        switch combinator {
        case .concat:
            return branches.flatMap { $0 }.filter { !$0.isEmpty }
        case .firstNonEmpty:
            for branch in branches {
                let nonEmpty = branch.filter { !$0.isEmpty }
                if !nonEmpty.isEmpty { return nonEmpty }
            }
            return []
        case .zip:
            let count = branches.map(\.count).min() ?? 0
            var zipped: [String] = []
            for i in 0..<count {
                for branch in branches { zipped.append(branch[i]) }
            }
            return zipped
        }
    }

    private static func mergeElements(_ branches: [Elements], combinator: Combinator?) -> Elements {
        guard let combinator else { return branches.first ?? Elements() }
        let result = Elements()
        switch combinator {
        case .firstNonEmpty:
            for branch in branches where !branch.array().isEmpty {
                for el in branch.array() { result.add(el) }
                break
            }
        case .concat, .zip:
            // Zip has no well-defined meaning for raw element/value lists in real-world sources;
            // v1 treats it the same as concat rather than guessing.
            for branch in branches {
                for el in branch.array() { result.add(el) }
            }
        }
        return result
    }
}
