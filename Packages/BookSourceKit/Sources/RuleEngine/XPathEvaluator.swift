import Foundation
import SwiftSoup

/// A minimal XPath subset evaluator against a SwiftSoup DOM: `/`/`//` axes plus the explicit
/// `following-sibling::` axis (confirmed real-world usage, not a guess — found in multiple real
/// book sources' `chapterList` rules), tag/`*`/`text()`/`@attr` node tests, and the predicate
/// forms real book sources actually use (`[N]`, `[last()]`, `[position()>N]`, `[position()<N]`,
/// `[@attr]`, `[@attr="v"]`, `[text()="v"]`). Not a general XPath 1.0 implementation — no other
/// axes, no functions beyond `position()`/`last()`, no boolean operators in predicates.
/// Unsupported syntax throws `.notYetImplemented` rather than silently mis-selecting, matching
/// the rest of this engine's philosophy.
public enum XPathEvaluator {
    enum Axis {
        case child
        case descendantOrSelf
        case followingSibling
    }

    enum NodeTest: Equatable {
        case tag(String)
        case wildcard
        case text
        case attribute(String)
    }

    enum PredicateKind {
        case index(Int)
        case last
        case positionGreaterThan(Int)
        case positionLessThan(Int)
        case attributeEquals(name: String, value: String)
        case attributeExists(String)
        case textEquals(String)
    }

    struct Step {
        var axis: Axis
        var nodeTest: NodeTest
        var predicates: [PredicateKind]
    }

    public static func extractElements(_ path: String, root: Elements) throws -> Elements {
        let steps = try parse(path)
        var current = root.array()
        for step in steps {
            switch step.nodeTest {
            case .attribute, .text:
                throw RuleEngineError.notYetImplemented("XPath: @attr/text() must be the final step")
            case .tag, .wildcard:
                current = try selectElements(step, from: current)
            }
        }
        let result = Elements()
        for el in current { result.add(el) }
        return result
    }

    public static func extractStrings(_ path: String, root: Elements) throws -> [String] {
        let steps = try parse(path)
        guard !steps.isEmpty else { return [] }

        var current = root.array()
        for (index, step) in steps.enumerated() {
            let isLast = index == steps.count - 1
            switch step.nodeTest {
            case .attribute(let name):
                guard isLast else { throw RuleEngineError.notYetImplemented("XPath: @attr must be the final step") }
                return try current.compactMap { el -> String? in
                    let value = try el.attr(name)
                    return value.isEmpty ? nil : value
                }
            case .text:
                guard isLast else { throw RuleEngineError.notYetImplemented("XPath: text() must be the final step") }
                return try current.map { try $0.text() }
            case .tag, .wildcard:
                current = try selectElements(step, from: current)
            }
        }
        // Chain ended on a tag/wildcard step with no explicit extraction -- default to text(),
        // mirroring how the Default/CSS chain evaluator treats a bare trailing selector.
        return try current.map { try $0.text() }
    }

    // MARK: - Element selection

    private static func selectElements(_ step: Step, from elements: [Element]) throws -> [Element] {
        var candidates: [Element] = []
        for el in elements {
            switch step.axis {
            case .child:
                candidates.append(contentsOf: matchingChildren(step.nodeTest, of: el))
            case .descendantOrSelf:
                candidates.append(contentsOf: try matchingDescendants(step.nodeTest, of: el))
            case .followingSibling:
                candidates.append(contentsOf: matchingFollowingSiblings(step.nodeTest, of: el))
            }
        }
        return try applyPredicates(step.predicates, to: candidates)
    }

    private static func matchingChildren(_ nodeTest: NodeTest, of element: Element) -> [Element] {
        switch nodeTest {
        case .tag(let name):
            return element.children().array().filter { $0.tagName().lowercased() == name.lowercased() }
        case .wildcard:
            return element.children().array()
        case .text, .attribute:
            return []
        }
    }

    private static func matchingDescendants(_ nodeTest: NodeTest, of element: Element) throws -> [Element] {
        switch nodeTest {
        case .tag(let name):
            return try element.getElementsByTag(name).array()
        case .wildcard:
            return try element.select("*").array()
        case .text, .attribute:
            return []
        }
    }

    /// XPath's `following-sibling::` axis: all siblings (same parent) that appear *after* the
    /// current element in document order — not just the immediate next one.
    private static func matchingFollowingSiblings(_ nodeTest: NodeTest, of element: Element) -> [Element] {
        guard let parent = element.parent() else { return [] }
        let siblings = parent.children().array()
        guard let selfIndex = siblings.firstIndex(where: { $0 === element }) else { return [] }
        let following = siblings[(selfIndex + 1)...]
        switch nodeTest {
        case .tag(let name):
            return following.filter { $0.tagName().lowercased() == name.lowercased() }
        case .wildcard:
            return Array(following)
        case .text, .attribute:
            return []
        }
    }

    private static func applyPredicates(_ predicates: [PredicateKind], to elements: [Element]) throws -> [Element] {
        var current = elements
        for predicate in predicates {
            switch predicate {
            case .index(let n):
                // XPath predicate indices are 1-based.
                let i = n - 1
                current = (i >= 0 && i < current.count) ? [current[i]] : []
            case .last:
                current = current.isEmpty ? [] : [current[current.count - 1]]
            case .positionGreaterThan(let n):
                current = current.enumerated().filter { $0.offset + 1 > n }.map(\.element)
            case .positionLessThan(let n):
                current = current.enumerated().filter { $0.offset + 1 < n }.map(\.element)
            case .attributeEquals(let name, let value):
                current = try current.filter { try $0.attr(name) == value }
            case .attributeExists(let name):
                current = current.filter { $0.hasAttr(name) }
            case .textEquals(let value):
                current = try current.filter { try $0.text() == value }
            }
        }
        return current
    }

    // MARK: - Parsing

    static func parse(_ path: String) throws -> [Step] {
        try splitSteps(path.trimmingCharacters(in: .whitespacesAndNewlines)).map { axis, text in
            // An explicit axis like "following-sibling::" appears *within* a step's text (after
            // the "/"-based split above), not as a step separator -- it overrides whatever axis
            // the leading "/"/"//" implied.
            var effectiveAxis = axis
            var stepText = text
            if stepText.hasPrefix("following-sibling::") {
                effectiveAxis = .followingSibling
                stepText = String(stepText.dropFirst("following-sibling::".count))
            }

            let (base, predicateTexts) = extractBracketGroups(stepText)
            let nodeTest = try parseNodeTest(base)
            let predicates = try predicateTexts.map(parsePredicate)
            return Step(axis: effectiveAxis, nodeTest: nodeTest, predicates: predicates)
        }
    }

    /// Splits a path into `(axis, stepText)` pairs. `//` marks the *following* step as
    /// descendant-or-self; a lone `/` marks it as child. Bracket/quote depth is tracked so a
    /// `/` inside a predicate (e.g. `[@href="a/b"]`) isn't mistaken for a step separator.
    private static func splitSteps(_ path: String) -> [(axis: Axis, text: String)] {
        var result: [(Axis, String)] = []
        let chars = Array(path)
        var i = 0

        while i < chars.count {
            var axis: Axis = .child
            if chars[i] == "/" {
                i += 1
                if i < chars.count, chars[i] == "/" {
                    axis = .descendantOrSelf
                    i += 1
                }
            }

            var text = ""
            var depth = 0
            var quote: Character?
            while i < chars.count {
                let c = chars[i]
                if let q = quote {
                    text.append(c)
                    if c == q { quote = nil }
                    i += 1
                    continue
                }
                if c == "'" || c == "\"" { quote = c; text.append(c); i += 1; continue }
                if c == "[" { depth += 1; text.append(c); i += 1; continue }
                if c == "]" { depth -= 1; text.append(c); i += 1; continue }
                if c == "/" && depth == 0 { break }
                text.append(c)
                i += 1
            }

            if !text.isEmpty {
                result.append((axis, text))
            }
        }
        return result
    }

    /// Splits `stepText` into its bare node-test text and an ordered list of `[...]` predicate
    /// group contents (brackets stripped, quotes preserved for later unquoting).
    private static func extractBracketGroups(_ stepText: String) -> (base: String, groups: [String]) {
        var base = ""
        var groups: [String] = []
        let chars = Array(stepText)
        var i = 0
        while i < chars.count {
            if chars[i] == "[" {
                var depth = 1
                var group = ""
                i += 1
                var quote: Character?
                while i < chars.count && depth > 0 {
                    let c = chars[i]
                    if let q = quote {
                        if c == q { quote = nil }
                        group.append(c)
                        i += 1
                        continue
                    }
                    if c == "'" || c == "\"" { quote = c; group.append(c); i += 1; continue }
                    if c == "[" { depth += 1; group.append(c); i += 1; continue }
                    if c == "]" {
                        depth -= 1
                        if depth == 0 { i += 1; break }
                        group.append(c); i += 1; continue
                    }
                    group.append(c)
                    i += 1
                }
                groups.append(group)
            } else {
                base.append(chars[i])
                i += 1
            }
        }
        return (base, groups)
    }

    private static func parseNodeTest(_ base: String) throws -> NodeTest {
        let trimmed = base.trimmingCharacters(in: .whitespaces)
        if trimmed == "*" { return .wildcard }
        if trimmed == "text()" { return .text }
        if trimmed.hasPrefix("@") { return .attribute(String(trimmed.dropFirst())) }
        guard !trimmed.isEmpty,
              trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            throw RuleEngineError.notYetImplemented(
                "XPath node test '\(trimmed)' (supported: tag names, *, text(), @attr)"
            )
        }
        return .tag(trimmed)
    }

    private static func parsePredicate(_ group: String) throws -> PredicateKind {
        let trimmed = group.trimmingCharacters(in: .whitespaces)

        if let n = Int(trimmed) { return .index(n) }
        if trimmed == "last()" { return .last }
        if trimmed.hasPrefix("position()>"), let n = Int(trimmed.dropFirst("position()>".count)) {
            return .positionGreaterThan(n)
        }
        if trimmed.hasPrefix("position()<"), let n = Int(trimmed.dropFirst("position()<".count)) {
            return .positionLessThan(n)
        }
        if trimmed.hasPrefix("text()=") {
            return .textEquals(unquote(String(trimmed.dropFirst("text()=".count))))
        }
        if trimmed.hasPrefix("@") {
            if let eqIndex = trimmed.firstIndex(of: "=") {
                let name = String(trimmed[trimmed.index(after: trimmed.startIndex)..<eqIndex])
                    .trimmingCharacters(in: .whitespaces)
                let value = unquote(String(trimmed[trimmed.index(after: eqIndex)...]))
                return .attributeEquals(name: name, value: value)
            }
            return .attributeExists(String(trimmed.dropFirst()))
        }

        throw RuleEngineError.notYetImplemented(
            "XPath predicate '[\(trimmed)]' (supported: [N], [last()], [position()>N], " +
            "[position()<N], [@attr], [@attr=\"v\"], [text()=\"v\"])"
        )
    }

    private static func unquote(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return trimmed }
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }
}
