import Foundation
import BookSourceModel

/// A static, parse-only compatibility report for a `BookSource` — every rule-string field gets
/// run through `RuleStringParser.parse` (no network, no evaluation) so the app can show "this
/// source uses N unsupported rule features" upfront, e.g. as a Source Library badge, instead of
/// the user discovering it mid-search. Matches the project plan's own architecture for this.
public struct SourceCapabilityReport: Equatable, Sendable {
    public struct Issue: Equatable, Sendable {
        public var field: String
        public var rule: String
        public var reason: String
    }

    public var sourceName: String
    public var sourceUrl: String
    public var issues: [Issue]

    public var isFullyCompatible: Bool { issues.isEmpty }
}

public enum CapabilityScanner {
    public static func scan(_ source: BookSource) -> SourceCapabilityReport {
        var issues: [SourceCapabilityReport.Issue] = []

        func check(_ rule: String?, field: String) {
            guard let rule, !rule.isEmpty else { return }
            let (stripped, _) = ListRulePrefix.strip(rule)
            do {
                _ = try RuleStringParser.parse(stripped)
            } catch let error as RuleEngineError {
                issues.append(.init(field: field, rule: rule, reason: describe(error)))
            } catch {
                issues.append(.init(field: field, rule: rule, reason: "\(error)"))
            }
        }

        func flagIfPresent(_ rule: String?, field: String, reason: String) {
            guard let rule, !rule.isEmpty else { return }
            issues.append(.init(field: field, rule: rule, reason: reason))
        }

        if !source.isTextSource {
            issues.append(.init(
                field: "bookSourceType", rule: "\(source.bookSourceType)",
                reason: "only text sources (type 0) are supported in v1"
            ))
        }

        if let s = source.ruleSearch {
            check(s.bookList, field: "ruleSearch.bookList")
            check(s.name, field: "ruleSearch.name")
            check(s.author, field: "ruleSearch.author")
            check(s.intro, field: "ruleSearch.intro")
            check(s.kind, field: "ruleSearch.kind")
            check(s.lastChapter, field: "ruleSearch.lastChapter")
            check(s.updateTime, field: "ruleSearch.updateTime")
            check(s.bookUrl, field: "ruleSearch.bookUrl")
            check(s.coverUrl, field: "ruleSearch.coverUrl")
            check(s.wordCount, field: "ruleSearch.wordCount")
        }

        if let e = source.ruleExplore {
            check(e.bookList, field: "ruleExplore.bookList")
            check(e.name, field: "ruleExplore.name")
            check(e.author, field: "ruleExplore.author")
            check(e.bookUrl, field: "ruleExplore.bookUrl")
            check(e.coverUrl, field: "ruleExplore.coverUrl")
        }

        if let b = source.ruleBookInfo {
            check(b.initRule, field: "ruleBookInfo.init")
            check(b.name, field: "ruleBookInfo.name")
            check(b.author, field: "ruleBookInfo.author")
            check(b.intro, field: "ruleBookInfo.intro")
            check(b.kind, field: "ruleBookInfo.kind")
            check(b.lastChapter, field: "ruleBookInfo.lastChapter")
            check(b.updateTime, field: "ruleBookInfo.updateTime")
            check(b.coverUrl, field: "ruleBookInfo.coverUrl")
            check(b.tocUrl, field: "ruleBookInfo.tocUrl")
            check(b.wordCount, field: "ruleBookInfo.wordCount")
        }

        if let t = source.ruleToc {
            check(t.chapterList, field: "ruleToc.chapterList")
            check(t.chapterName, field: "ruleToc.chapterName")
            check(t.chapterUrl, field: "ruleToc.chapterUrl")
            check(t.updateTime, field: "ruleToc.updateTime")
            check(t.isVolume, field: "ruleToc.isVolume")
            check(t.isVip, field: "ruleToc.isVip")
            check(t.isPay, field: "ruleToc.isPay")
            check(t.nextTocUrl, field: "ruleToc.nextTocUrl")
            flagIfPresent(t.preUpdateJs, field: "ruleToc.preUpdateJs", reason: "requires JS execution (not yet supported)")
        }

        if let c = source.ruleContent {
            check(c.content, field: "ruleContent.content")
            check(c.subContent, field: "ruleContent.subContent")
            check(c.title, field: "ruleContent.title")
            check(c.nextContentUrl, field: "ruleContent.nextContentUrl")
            flagIfPresent(c.webJs, field: "ruleContent.webJs", reason: "requires WebView JS execution (not yet supported)")
        }

        return SourceCapabilityReport(sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, issues: issues)
    }

    public static func scan(_ sources: [BookSource]) -> [SourceCapabilityReport] {
        sources.map(scan)
    }

    private static func describe(_ error: RuleEngineError) -> String {
        switch error {
        case .unsupportedFeature(let feature): return "unsupported: \(feature.rawValue)"
        case .notYetImplemented(let detail): return "not yet implemented: \(detail)"
        case .invalidRule(let detail): return "invalid rule: \(detail)"
        }
    }
}
