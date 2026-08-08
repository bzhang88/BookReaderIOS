import Foundation

/// Legado's book-source rule sub-objects (`ruleSearch`, `ruleToc`, ...) may appear in real-world
/// source files as a JSON object, OR as a JSON string containing an escaped JSON object, OR as a
/// bare string that should populate the sub-object's single "primary" rule field. This mirrors
/// that three-layer leniency so real exported source files decode instead of failing outright.
enum LenientRuleDecoding {
    enum Result<Fields> {
        case object(Fields)
        case rawString(String)
    }

    static func decode<Fields: Decodable>(
        _ fieldsType: Fields.Type,
        from decoder: Decoder
    ) throws -> Result<Fields> {
        if let fields = try? Fields(from: decoder) {
            return .object(fields)
        }

        let container = try decoder.singleValueContainer()
        guard let raw = try? container.decode(String.self) else {
            throw DecodingError.typeMismatch(
                Fields.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a rule object or a string for \(Fields.self)"
                )
            )
        }

        if let data = raw.data(using: .utf8),
           let reparsed = try? JSONDecoder().decode(Fields.self, from: data) {
            return .object(reparsed)
        }

        return .rawString(raw)
    }
}
