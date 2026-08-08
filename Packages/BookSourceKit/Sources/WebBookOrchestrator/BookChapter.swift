import Foundation

public struct BookChapter: Equatable, Identifiable, Sendable {
    public var index: Int
    public var title: String
    public var url: String
    public var isVolume: Bool
    public var isVip: Bool
    public var isPay: Bool
    public var tag: String?

    public var id: String { url }

    public init(
        index: Int, title: String, url: String,
        isVolume: Bool = false, isVip: Bool = false, isPay: Bool = false, tag: String? = nil
    ) {
        self.index = index
        self.title = title
        self.url = url
        self.isVolume = isVolume
        self.isVip = isVip
        self.isPay = isPay
        self.tag = tag
    }

    func reindexed(_ newIndex: Int) -> BookChapter {
        BookChapter(index: newIndex, title: title, url: url, isVolume: isVolume, isVip: isVip, isPay: isPay, tag: tag)
    }
}
