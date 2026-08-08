import Foundation

private struct TocRuleFields: Codable {
    var preUpdateJs: String?
    var chapterList: String?
    var chapterName: String?
    var chapterUrl: String?
    var formatJs: String?
    var isVolume: String?
    var isVip: String?
    var isPay: String?
    var updateTime: String?
    var nextTocUrl: String?
}

/// Table-of-contents extraction rule. JSON key: `ruleToc`.
public struct TocRule: Codable, Equatable {
    public var preUpdateJs: String?
    public var chapterList: String?
    public var chapterName: String?
    public var chapterUrl: String?
    public var formatJs: String?
    public var isVolume: String?
    public var isVip: String?
    public var isPay: String?
    public var updateTime: String?
    public var nextTocUrl: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        switch try LenientRuleDecoding.decode(TocRuleFields.self, from: decoder) {
        case .object(let fields):
            self.init(fields: fields)
        case .rawString(let raw):
            self.init()
            self.chapterList = raw
        }
    }

    public func encode(to encoder: Encoder) throws {
        try TocRuleFields(
            preUpdateJs: preUpdateJs, chapterList: chapterList, chapterName: chapterName,
            chapterUrl: chapterUrl, formatJs: formatJs, isVolume: isVolume, isVip: isVip,
            isPay: isPay, updateTime: updateTime, nextTocUrl: nextTocUrl
        ).encode(to: encoder)
    }

    private init(fields: TocRuleFields) {
        preUpdateJs = fields.preUpdateJs
        chapterList = fields.chapterList
        chapterName = fields.chapterName
        chapterUrl = fields.chapterUrl
        formatJs = fields.formatJs
        isVolume = fields.isVolume
        isVip = fields.isVip
        isPay = fields.isPay
        updateTime = fields.updateTime
        nextTocUrl = fields.nextTocUrl
    }
}
