import Foundation

/// Which selector language a (mode-prefix-stripped) rule string should be evaluated as.
public enum RuleMode: Equatable {
    /// Plain jsoup dot-chain (no prefix, or `@@` escape into it explicitly).
    case defaultChain
    /// `@css:selector@keyword` — one selector, not a multi-step chain.
    case cssSingle
    /// `@Json:`/`$.`/`$[` prefix. Evaluator lands in Phase 2.
    case json
    /// `@XPath:` prefix or leading `/`. Detected but permanently unsupported in this engine.
    case xpath
}

/// Tokenizes a single rule-string field (e.g. one `SearchRule.bookList` value) into its mode and
/// bare selector, with the mode prefix and trailing `##` regex suffix stripped off.
///
/// Deliberately out of scope for v1 (see the project plan): AllInOne `:`-prefixed regex mode,
/// `{{ }}` embedded JS, and `<js>`/`@js:`/`@webjs:` pipeline segments. Rules using any of these
/// throw rather than silently mis-parsing, so the app can report "unsupported" instead of
/// producing a confidently wrong result.
public enum RuleStringParser {
    public struct ParsedRule: Equatable {
        public var mode: RuleMode
        public var selector: String
        public var regexSuffix: RegexSuffix?
    }

    /// - Parameter contentIsJSON: whether the current page's fetched body was sniffed as JSON
    ///   (see `JSONContentSniffer`). Per Legado's real behavior this is page-level and sticky: an
    ///   otherwise-unprefixed rule falls back to JSON mode instead of the Default jsoup chain
    ///   when true, even if the rule text looks like a CSS selector.
    public static func parse(_ rule: String, contentIsJSON: Bool = false) throws -> ParsedRule {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.range(of: "@webjs:", options: [.caseInsensitive]) != nil {
            throw RuleEngineError.unsupportedFeature(.webJs)
        }
        if trimmed.contains("<js>") || trimmed.range(of: "@js:", options: [.caseInsensitive]) != nil {
            throw RuleEngineError.notYetImplemented("<js>/@js: pipeline segments (planned for Phase 2)")
        }
        if trimmed.contains("{{") {
            throw RuleEngineError.notYetImplemented("Embedded {{ }} JS (planned for Phase 2)")
        }
        if trimmed.contains("{$.") || trimmed.contains("{$[") {
            throw RuleEngineError.notYetImplemented(
                "Embedded {$.path} JSONPath substitution (planned alongside Phase 2 JS work)"
            )
        }
        if trimmed.hasPrefix(":") {
            throw RuleEngineError.unsupportedFeature(.allInOne)
        }

        let (withoutSuffix, suffix) = RegexSuffixParser.extract(from: trimmed)
        let (mode, selector) = detectMode(withoutSuffix, contentIsJSON: contentIsJSON)
        return ParsedRule(mode: mode, selector: selector, regexSuffix: suffix)
    }

    private static func detectMode(_ rule: String, contentIsJSON: Bool) -> (RuleMode, String) {
        if let range = prefixRange(rule, prefix: "@css:") {
            return (.cssSingle, String(rule[range.upperBound...]))
        }
        if rule.hasPrefix("@@") {
            return (.defaultChain, String(rule.dropFirst(2)))
        }
        if let range = prefixRange(rule, prefix: "@xpath:") {
            return (.xpath, String(rule[range.upperBound...]))
        }
        if let range = prefixRange(rule, prefix: "@json:") {
            return (.json, String(rule[range.upperBound...]))
        }
        if rule.hasPrefix("$.") || rule.hasPrefix("$[") {
            return (.json, rule)
        }
        if rule.hasPrefix("/") {
            return (.xpath, rule)
        }
        return (contentIsJSON ? .json : .defaultChain, rule)
    }

    private static func prefixRange(_ rule: String, prefix: String) -> Range<String.Index>? {
        guard let range = rule.range(of: prefix, options: [.caseInsensitive]),
              range.lowerBound == rule.startIndex else { return nil }
        return range
    }
}
