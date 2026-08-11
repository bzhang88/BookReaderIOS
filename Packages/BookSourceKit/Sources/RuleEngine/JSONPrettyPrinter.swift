import Foundation

/// Pretty-prints arbitrary JSON text for the developer toolbox -- useful when eyeballing a raw
/// response body before writing a JSONPath rule against it. Deliberately not built on this
/// package's own `JSONValue`/`JSONPathEvaluator` (those exist to evaluate paths, not to preserve
/// and re-emit exact JSON structure); `JSONSerialization` already round-trips arbitrary JSON and is
/// available on every platform this package targets, including Windows.
public enum JSONPrettyPrinter {
    public enum FormatError: Error, Equatable {
        case invalidJSON
    }

    public static func format(_ raw: String) -> Result<String, FormatError> {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let prettyData = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
              ),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return .failure(.invalidJSON)
        }
        return .success(prettyString)
    }
}
