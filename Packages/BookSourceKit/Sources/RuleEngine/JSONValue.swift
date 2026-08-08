import Foundation

/// A minimal, portable JSON tree built on `JSONSerialization` (not `Decodable`, since a
/// book-source API response's shape is only known at rule-evaluation time, not compile time).
public enum JSONValue: Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public static func parse(_ data: Data) throws -> JSONValue {
        let raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return JSONValue(any: raw)
    }

    public static func parse(_ text: String) throws -> JSONValue {
        try parse(Data(text.utf8))
    }

    init(any: Any) {
        switch any {
        case let dict as [String: Any]:
            self = .object(dict.mapValues { JSONValue(any: $0) })
        case let arr as [Any]:
            self = .array(arr.map { JSONValue(any: $0) })
        case let str as String:
            self = .string(str)
        case let num as NSNumber:
            // JSONSerialization boxes both real numbers and true/false as NSNumber; the ObjC
            // type encoding "c" (char) reliably distinguishes CFBoolean-backed bool values from
            // real numeric ones (verified empirically against this platform's JSONSerialization,
            // and is the standard workaround for this well-known NSNumber/Bool ambiguity).
            if String(cString: num.objCType) == "c" {
                self = .bool(num.boolValue)
            } else {
                self = .number(num.doubleValue)
            }
        default:
            self = .null
        }
    }

    /// The rule engine's string coercion for a JSON value.
    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n):
            if n.truncatingRemainder(dividingBy: 1) == 0 && abs(n) < 1e15 {
                return String(format: "%.0f", n)
            }
            return String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null, .object, .array: return nil
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    public subscript(index: Int) -> JSONValue? {
        guard case .array(let arr) = self else { return nil }
        let resolved = index < 0 ? index + arr.count : index
        guard resolved >= 0 && resolved < arr.count else { return nil }
        return arr[resolved]
    }
}
