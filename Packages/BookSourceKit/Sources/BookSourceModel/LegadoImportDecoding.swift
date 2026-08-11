import Foundation

/// Generalizes `BookSourceImportDecoder`'s "usually an array, tolerate a single bare object too"
/// leniency to every `legado://import/...` type -- same reasoning: try the common (array) shape
/// first and surface *that* error on failure, not the fallback's confusing "expected Dictionary but
/// found an array" when the input actually was an array and the real problem is inside one element.
public enum LegadoImportDecoding {
    public static func decodeArrayOrSingle<T: Decodable>(_ type: T.Type, from data: Data) throws -> [T] {
        do {
            return try JSONDecoder().decode([T].self, from: data)
        } catch let arrayDecodingError {
            if let single = try? JSONDecoder().decode(T.self, from: data) {
                return [single]
            }
            throw arrayDecodingError
        }
    }
}
