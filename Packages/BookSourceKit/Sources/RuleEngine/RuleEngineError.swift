import Foundation

/// A rule DSL feature this v1 engine deliberately doesn't implement. Surfaced distinctly from
/// other failures so the app can show "this book source uses an unsupported rule feature"
/// instead of a generic error or, worse, a silently wrong empty result.
public enum UnsupportedRuleFeature: String, Equatable, Sendable {
    case webJs
    case putGetSyntax
    case interleaveCombinator
    case javaAjaxOrConnect
}

public enum RuleEngineError: Error, Equatable {
    case unsupportedFeature(UnsupportedRuleFeature)
    /// A real DSL feature that's simply not built yet (tracked against the phased plan),
    /// as opposed to one that's permanently out of scope.
    case notYetImplemented(String)
    case invalidRule(String)
}
