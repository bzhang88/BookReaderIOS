import Foundation

/// Shared decode logic for every "import book sources from raw JSON bytes" entry point (file
/// picker, paste-a-URL, and the `legado://import/bookSource` URL scheme) -- pulled out to one place
/// so all three surface the same behavior instead of subtly drifting apart.
public enum BookSourceImportDecoder {
    /// Real book-source files are almost always a top-level array of many sources, but tolerate a
    /// single bare source object too. Tries the (expected, common) array shape first and surfaces
    /// *that* error on failure -- not the fallback's, which is always a confusing "expected
    /// Dictionary but found an array" when the file is an array (the common case) and the real
    /// problem is actually somewhere inside one of its elements.
    public static func decode(from data: Data) throws -> [BookSource] {
        do {
            return try JSONDecoder().decode([BookSource].self, from: data)
        } catch let arrayDecodingError {
            if let single = try? JSONDecoder().decode(BookSource.self, from: data) {
                return [single]
            }
            throw arrayDecodingError
        }
    }
}
