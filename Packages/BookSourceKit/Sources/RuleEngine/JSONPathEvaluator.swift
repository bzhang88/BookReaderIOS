import Foundation

/// A minimal JSONPath subset: `$`-rooted (or bare) dot/bracket navigation, `[n]` array
/// indexing (negative-from-end supported), `[*]` wildcard expansion, and `..name` recursive
/// descent. Deliberately not a full JSONPath implementation (no filter expressions `[?(...)]`,
/// no functions, no slices) — real book sources overwhelmingly use only this subset; anything
/// fancier a source needs should route through `RuleEngineError` rather than silently return [].
public enum JSONPathEvaluator {
    enum Segment: Equatable {
        case key(String)
        case index(Int)
        case wildcard
        case recursiveKey(String)
    }

    public static func extractValues(_ path: String, from root: JSONValue) -> [JSONValue] {
        let segments = parseSegments(path.trimmingCharacters(in: .whitespaces))
        guard !segments.isEmpty else { return [root] }
        return apply(segments, to: root)
    }

    public static func extractStrings(_ path: String, from root: JSONValue) -> [String] {
        extractValues(path, from: root).compactMap { $0.stringValue }
    }

    // MARK: - Parsing

    static func parseSegments(_ path: String) -> [Segment] {
        let chars = Array(path)
        var i = 0
        if i < chars.count, chars[i] == "$" { i += 1 }

        var segments: [Segment] = []
        while i < chars.count {
            if chars[i] == "." {
                i += 1
                if i < chars.count, chars[i] == "." {
                    i += 1
                    let name = scanName(chars, &i)
                    if !name.isEmpty { segments.append(.recursiveKey(name)) }
                } else {
                    let name = scanName(chars, &i)
                    if !name.isEmpty { segments.append(.key(name)) }
                }
            } else if chars[i] == "[" {
                i += 1
                var inner = ""
                while i < chars.count, chars[i] != "]" { inner.append(chars[i]); i += 1 }
                if i < chars.count { i += 1 } // consume ']'
                segments.append(contentsOf: parseBracketContent(inner))
            } else {
                let name = scanName(chars, &i)
                if !name.isEmpty { segments.append(.key(name)) }
            }
        }
        return segments
    }

    private static func scanName(_ chars: [Character], _ i: inout Int) -> String {
        var name = ""
        while i < chars.count, chars[i] != ".", chars[i] != "[" {
            name.append(chars[i])
            i += 1
        }
        return name
    }

    private static func parseBracketContent(_ raw: String) -> [Segment] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed == "*" { return [.wildcard] }
        if let idx = Int(trimmed) { return [.index(idx)] }

        var key = trimmed
        if key.count >= 2,
           (key.hasPrefix("'") && key.hasSuffix("'")) || (key.hasPrefix("\"") && key.hasSuffix("\"")) {
            key = String(key.dropFirst().dropLast())
        }
        return key.isEmpty ? [] : [.key(key)]
    }

    // MARK: - Evaluation

    private static func apply(_ segments: [Segment], to root: JSONValue) -> [JSONValue] {
        var current: [JSONValue] = [root]
        for segment in segments {
            var next: [JSONValue] = []
            for value in current {
                switch segment {
                case .key(let name):
                    if let v = value[name] { next.append(v) }
                case .index(let idx):
                    if let v = value[idx] { next.append(v) }
                case .wildcard:
                    switch value {
                    case .array(let arr): next.append(contentsOf: arr)
                    case .object(let dict): next.append(contentsOf: dict.values)
                    default: break
                    }
                case .recursiveKey(let name):
                    next.append(contentsOf: recursiveSearch(value, key: name))
                }
            }
            current = next
        }
        return current
    }

    private static func recursiveSearch(_ value: JSONValue, key: String) -> [JSONValue] {
        var results: [JSONValue] = []
        switch value {
        case .object(let dict):
            if let match = dict[key] { results.append(match) }
            for child in dict.values { results.append(contentsOf: recursiveSearch(child, key: key)) }
        case .array(let arr):
            for child in arr { results.append(contentsOf: recursiveSearch(child, key: key)) }
        default:
            break
        }
        return results
    }
}
