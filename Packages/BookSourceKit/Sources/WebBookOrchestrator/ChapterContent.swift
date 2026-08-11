import Foundation

public struct ChapterContent: Equatable, Sendable, Codable {
    public var text: String
    public var titleOverride: String?

    public init(text: String, titleOverride: String? = nil) {
        self.text = text
        self.titleOverride = titleOverride
    }
}
