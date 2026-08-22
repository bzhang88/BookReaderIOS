import Foundation
import RuleEngine
import NetworkClient

/// Maps a book-source fetch failure to a short, non-technical Chinese message -- real usage
/// feedback: raw `"\(error)"` interpolation (e.g. `unsupportedFeature(putGetSyntax)`,
/// `nonTextResponse`) reads as "something broke" with no actionable information, especially for
/// `RuleEngineError` cases that specifically mean "this book source's rules use syntax this app
/// can't run yet" -- a real, common failure mode (a survey of one real user's 463-source
/// collection found ~30% of enabled text sources use `@js:`/`@put:`/`{{}}` syntax in their search
/// rule alone), not a transient network problem retrying would fix.
///
/// Lives in the package (not the app target) so both `MultiSourceSearchService`'s per-source
/// `SourceOutcome.errorDescription` and the app target's `BookDetailView`/`TocView` share the same
/// mapping instead of two copies drifting apart -- `public` so the app target can call it too.
/// The same raw `"\(error)"` pattern still exists in a few other app-target screens (`ExploreView`,
/// `ShelfView`, `ReaderView`'s 换源, `SourceLibraryView`, ...); rolling this out there too is a
/// reasonable follow-up, deliberately not done in this pass to keep it scoped to reported bugs.
public enum FriendlyError {
    public static func message(for error: Error) -> String {
        if let ruleError = error as? RuleEngineError {
            switch ruleError {
            case .unsupportedFeature:
                return "这个书源用到了暂不支持的规则写法（比如 JS 脚本），可以换一个书源试试"
            case .notYetImplemented:
                return "这个书源用到了还没做完的规则功能，可以换一个书源试试"
            case .invalidRule:
                return "这个书源的规则写法有问题，可能是书源本身配置有误"
            }
        }
        if let httpError = error as? HTTPClientError {
            switch httpError {
            case .invalidURL:
                return "书源里的网址格式不对，可能是书源配置有误"
            case .nonTextResponse:
                return "书源返回的内容不是文本，可能被拦截了（比如需要登录或验证码）"
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "没有网络连接"
            case NSURLErrorTimedOut:
                return "请求超时，这个书源可能已经失效"
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                return "连不上这个书源的服务器，可能已经失效"
            default:
                return "网络请求失败，这个书源可能暂时无法访问"
            }
        }
        return "获取失败，这个书源可能暂时有问题，可以换一个试试"
    }
}
