import Foundation

private struct ContentRuleFields: Codable {
    var content: String?
    var subContent: String?
    var title: String?
    var nextContentUrl: String?
    var webJs: String?
    var sourceRegex: String?
    var replaceRegex: String?
    var imageStyle: String?
    var imageDecode: String?
    var payAction: String?
    var callBackJs: String?
}

/// Chapter-content extraction rule. JSON key: `ruleContent`.
public struct ContentRule: Codable, Equatable {
    public var content: String?
    public var subContent: String?
    public var title: String?
    public var nextContentUrl: String?
    public var webJs: String?
    public var sourceRegex: String?
    public var replaceRegex: String?
    public var imageStyle: String?
    public var imageDecode: String?
    public var payAction: String?
    public var callBackJs: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        switch try LenientRuleDecoding.decode(ContentRuleFields.self, from: decoder) {
        case .object(let fields):
            self.init(fields: fields)
        case .rawString(let raw):
            self.init()
            self.content = raw
        }
    }

    public func encode(to encoder: Encoder) throws {
        try ContentRuleFields(
            content: content, subContent: subContent, title: title,
            nextContentUrl: nextContentUrl, webJs: webJs, sourceRegex: sourceRegex,
            replaceRegex: replaceRegex, imageStyle: imageStyle, imageDecode: imageDecode,
            payAction: payAction, callBackJs: callBackJs
        ).encode(to: encoder)
    }

    private init(fields: ContentRuleFields) {
        content = fields.content
        subContent = fields.subContent
        title = fields.title
        nextContentUrl = fields.nextContentUrl
        webJs = fields.webJs
        sourceRegex = fields.sourceRegex
        replaceRegex = fields.replaceRegex
        imageStyle = fields.imageStyle
        imageDecode = fields.imageDecode
        payAction = fields.payAction
        callBackJs = fields.callBackJs
    }
}
