import Foundation
import RuleEngine
import NetworkClient

/// Maps a fetch failure (book-source or WebDAV) to a short, non-technical Chinese message -- real
/// usage feedback: raw `"\(error)"` interpolation (e.g. `unsupportedFeature(putGetSyntax)`,
/// `nonTextResponse`) reads as "something broke" with no actionable information, especially for
/// `RuleEngineError` cases that specifically mean "this book source's rules use syntax this app
/// can't run yet" -- a real, common failure mode (a survey of one real user's 463-source
/// collection found ~30% of enabled text sources use `@js:`/`@put:`/`{{}}` syntax in their search
/// rule alone), not a transient network problem retrying would fix.
///
/// Lives in the package (not the app target) so both `MultiSourceSearchService`'s per-source
/// `SourceOutcome.errorDescription` and the app target's `BookDetailView`/`TocView`/
/// `BackupSettingsView` share the same mapping instead of copies drifting apart -- `public` so the
/// app target can call it too. `RuleEngineError`'s cases are inherently book-source-specific (that
/// error type can only originate from the rule engine), but every other branch is deliberately
/// worded to read correctly regardless of which of those callers hit it, since `WebDAVClientError`
/// and the underlying `HTTPClientError`/network cases are shared infrastructure, not unique to
/// fetching book sources.
public enum FriendlyError {
    public static func message(for error: Error) -> String {
        if let webdavError = error as? WebDAVClientError {
            switch webdavError {
            case .invalidBaseURL:
                return "WebDAV 地址格式不对，请检查服务器地址"
            case .unexpectedStatus(let code):
                switch code {
                case 401, 403: return "WebDAV 账号或密码不正确"
                case 404: return "WebDAV 路径不存在，请检查备份目录设置"
                case 507: return "WebDAV 空间不足"
                default: return "WebDAV 请求失败（状态码 \(code)）"
                }
            }
        }
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
                return "网址格式不对，请检查配置"
            case .nonTextResponse:
                return "返回的内容不是文本，可能被拦截了（比如需要登录或验证码）"
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "没有网络连接"
            case NSURLErrorTimedOut:
                return "请求超时，请稍后重试"
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                return "连接失败，请检查网络或服务器地址"
            default:
                return "网络请求失败，请稍后重试"
            }
        }
        return "操作失败，请稍后重试"
    }
}
