import Foundation

private struct SearchRuleFields: Codable {
    var checkKeyWord: String?
    var bookList: String?
    var name: String?
    var author: String?
    var intro: String?
    var kind: String?
    var lastChapter: String?
    var updateTime: String?
    var bookUrl: String?
    var coverUrl: String?
    var wordCount: String?
}

/// Search-results-page extraction rule. JSON key: `ruleSearch`.
public struct SearchRule: Codable, Equatable {
    public var checkKeyWord: String?
    public var bookList: String?
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var bookUrl: String?
    public var coverUrl: String?
    public var wordCount: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        switch try LenientRuleDecoding.decode(SearchRuleFields.self, from: decoder) {
        case .object(let fields):
            self.init(fields: fields)
        case .rawString(let raw):
            self.init()
            self.bookList = raw
        }
    }

    public func encode(to encoder: Encoder) throws {
        try SearchRuleFields(
            checkKeyWord: checkKeyWord, bookList: bookList, name: name, author: author,
            intro: intro, kind: kind, lastChapter: lastChapter, updateTime: updateTime,
            bookUrl: bookUrl, coverUrl: coverUrl, wordCount: wordCount
        ).encode(to: encoder)
    }

    private init(fields: SearchRuleFields) {
        checkKeyWord = fields.checkKeyWord
        bookList = fields.bookList
        name = fields.name
        author = fields.author
        intro = fields.intro
        kind = fields.kind
        lastChapter = fields.lastChapter
        updateTime = fields.updateTime
        bookUrl = fields.bookUrl
        coverUrl = fields.coverUrl
        wordCount = fields.wordCount
    }
}
