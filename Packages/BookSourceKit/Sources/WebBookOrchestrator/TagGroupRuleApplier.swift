import Foundation
import BookSourceModel

public enum TagGroupRuleApplier {
    /// Returns the group name of the first enabled rule (in list order) whose pattern matches the
    /// book's name, author, or intro -- first-match-wins, same as Legado's tag-group rules, so rule
    /// order doubles as priority when a book could plausibly fall into more than one group.
    public static func matchGroup(_ rules: [TagGroupRule], name: String, author: String?, intro: String?) -> String? {
        let haystack = [name, author, intro].compactMap { $0 }.joined(separator: "\n")
        for rule in rules where rule.enabled {
            guard !rule.pattern.isEmpty, let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            let nsHaystack = haystack as NSString
            if regex.firstMatch(in: haystack, range: NSRange(location: 0, length: nsHaystack.length)) != nil {
                return rule.groupName
            }
        }
        return nil
    }
}
