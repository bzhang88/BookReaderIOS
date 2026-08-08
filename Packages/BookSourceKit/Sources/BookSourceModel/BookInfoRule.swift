import Foundation

private struct BookInfoRuleFields: Codable {
    var initRule: String?
    var name: String?
    var author: String?
    var intro: String?
    var kind: String?
    var lastChapter: String?
    var updateTime: String?
    var coverUrl: String?
    var tocUrl: String?
    var wordCount: String?
    var canReName: String?
    var downloadUrls: String?
    var relatedBooks: String?

    enum CodingKeys: String, CodingKey {
        case initRule = "init"
        case name, author, intro, kind, lastChapter, updateTime, coverUrl, tocUrl
        case wordCount, canReName, downloadUrls, relatedBooks
    }
}

/// Book-detail-page extraction rule. JSON key: `ruleBookInfo`.
///
/// Note the JSON key for the pre-processing rule is `init` (not `bookInfoInit` as some
/// third-party docs claim) — verified against Legado's `BookInfoRule.kt`.
public struct BookInfoRule: Codable, Equatable {
    public var initRule: String?
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var coverUrl: String?
    public var tocUrl: String?
    public var wordCount: String?
    public var canReName: String?
    public var downloadUrls: String?
    public var relatedBooks: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        switch try LenientRuleDecoding.decode(BookInfoRuleFields.self, from: decoder) {
        case .object(let fields):
            self.init(fields: fields)
        case .rawString(let raw):
            // Matches Legado's real (slightly odd) fallback: a bare-string ruleBookInfo
            // populates `name`, not `init`.
            self.init()
            self.name = raw
        }
    }

    public func encode(to encoder: Encoder) throws {
        try BookInfoRuleFields(
            initRule: initRule, name: name, author: author, intro: intro, kind: kind,
            lastChapter: lastChapter, updateTime: updateTime, coverUrl: coverUrl, tocUrl: tocUrl,
            wordCount: wordCount, canReName: canReName, downloadUrls: downloadUrls,
            relatedBooks: relatedBooks
        ).encode(to: encoder)
    }

    private init(fields: BookInfoRuleFields) {
        initRule = fields.initRule
        name = fields.name
        author = fields.author
        intro = fields.intro
        kind = fields.kind
        lastChapter = fields.lastChapter
        updateTime = fields.updateTime
        coverUrl = fields.coverUrl
        tocUrl = fields.tocUrl
        wordCount = fields.wordCount
        canReName = fields.canReName
        downloadUrls = fields.downloadUrls
        relatedBooks = fields.relatedBooks
    }
}
