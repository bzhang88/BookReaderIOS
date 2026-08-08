import Foundation

public struct SearchResult: Equatable, Sendable, Identifiable {
    public var bookSourceUrl: String
    public var bookSourceName: String
    public var name: String
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var bookUrl: String
    public var coverUrl: String?
    public var wordCount: String?

    public var id: String { bookSourceUrl + "|" + bookUrl }

    public init(
        bookSourceUrl: String, bookSourceName: String, name: String, author: String? = nil,
        intro: String? = nil, kind: String? = nil, lastChapter: String? = nil,
        updateTime: String? = nil, bookUrl: String, coverUrl: String? = nil, wordCount: String? = nil
    ) {
        self.bookSourceUrl = bookSourceUrl
        self.bookSourceName = bookSourceName
        self.name = name
        self.author = author
        self.intro = intro
        self.kind = kind
        self.lastChapter = lastChapter
        self.updateTime = updateTime
        self.bookUrl = bookUrl
        self.coverUrl = coverUrl
        self.wordCount = wordCount
    }
}
