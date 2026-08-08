import Foundation

public struct BookInfo: Equatable, Sendable {
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var coverUrl: String?
    public var tocUrl: String
    public var wordCount: String?

    public init(
        name: String? = nil, author: String? = nil, intro: String? = nil, kind: String? = nil,
        lastChapter: String? = nil, updateTime: String? = nil, coverUrl: String? = nil,
        tocUrl: String, wordCount: String? = nil
    ) {
        self.name = name
        self.author = author
        self.intro = intro
        self.kind = kind
        self.lastChapter = lastChapter
        self.updateTime = updateTime
        self.coverUrl = coverUrl
        self.tocUrl = tocUrl
        self.wordCount = wordCount
    }
}
