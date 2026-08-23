import Foundation
import BookSourceModel
import NetworkClient

/// How far into the search -> detail -> toc -> content pipeline a batch source check goes --
/// ordered so `depth >= stage` reads naturally as "this run was configured to reach at least this
/// far". Matches `SourceDebugView`'s existing single-source, four-step pipeline, just run across
/// many sources at once and stoppable early instead of always running all four steps.
///
/// `.domain`/`.explore` are independent side-checks, not more of that depth chain -- mirroring
/// Legado's own `CheckSourceService` (`CheckSource.checkDomain`/`checkDiscovery` are separate
/// boolean toggles, not additional depth levels): `.domain` always runs first regardless of `depth`
/// (a source whose base URL isn't even reachable makes the rest of the check moot), and `.explore`
/// always runs whenever the source has a non-blank `exploreUrl`, independent of how deep `depth`
/// goes into the search chain. `depthOptions` is what `SourceCheckView`'s depth picker actually
/// offers, keeping these two out of that picker.
public enum SourceValidationStage: Int, CaseIterable, Comparable, Sendable {
    case domain, search, detail, toc, content, explore

    public static func < (lhs: SourceValidationStage, rhs: SourceValidationStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .domain: return "域名可达性"
        case .search: return "搜索"
        case .detail: return "详情"
        case .toc: return "目录"
        case .content: return "正文"
        case .explore: return "发现页"
        }
    }

    public static var depthOptions: [SourceValidationStage] { [.search, .detail, .toc, .content] }
}

public struct SourceValidationStageResult: Equatable, Sendable {
    public var stage: SourceValidationStage
    public var success: Bool
    public var detail: String

    public init(stage: SourceValidationStage, success: Bool, detail: String) {
        self.stage = stage
        self.success = success
        self.detail = detail
    }
}

public struct SourceValidationOutcome: Equatable, Sendable {
    public var source: BookSource
    public var stageResults: [SourceValidationStageResult]
    /// How long this source's whole check took, wall-clock -- measured by `validate(sources:...)`
    /// around the call to `validateOne` (not threaded through its several early-return points),
    /// since that's simpler than touching every one of them. Feeds `SourceCheckView`'s write-back
    /// into `BookSource.respondTime`, matching Legado's own `CheckSourceService` timing its checks
    /// the same way and using the result to sort the source list by real-world speed.
    public var elapsedMilliseconds: Int

    public init(source: BookSource, stageResults: [SourceValidationStageResult], elapsedMilliseconds: Int = 0) {
        self.source = source
        self.stageResults = stageResults
        self.elapsedMilliseconds = elapsedMilliseconds
    }

    public var isFullyPassing: Bool { !stageResults.isEmpty && stageResults.allSatisfy(\.success) }
}

/// Batch version of `SourceDebugView`'s single-source pipeline walk -- every source runs the same
/// steps concurrently (matching `MultiSourceSearchService`'s existing unbounded-per-source
/// concurrency model), streaming each source's outcome back as it finishes.
public enum SourceValidationService {
    public static func validate(
        sources: [BookSource], keyword: String, depth: SourceValidationStage, httpClient: HTTPClient
    ) -> AsyncStream<SourceValidationOutcome> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: SourceValidationOutcome.self) { group in
                    for source in sources {
                        group.addTask {
                            let start = Date()
                            var outcome = await validateOne(source: source, keyword: keyword, depth: depth, httpClient: httpClient)
                            outcome.elapsedMilliseconds = Int(Date().timeIntervalSince(start) * 1000)
                            return outcome
                        }
                    }
                    for await outcome in group {
                        continuation.yield(outcome)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Domain check runs first and aborts everything else on failure (matching Legado's own
    /// `doCheckSource`, which throws immediately if `isDomainReachable` fails) -- there's no point
    /// running the rest of the pipeline against a source whose base URL doesn't even respond. The
    /// search->detail->toc->content chain and the explore check both then run independently of each
    /// other: a failure partway through the depth chain doesn't skip the explore check, matching how
    /// Legado's `checkDiscovery` is its own independent step, not gated on the search chain
    /// succeeding.
    private static func validateOne(
        source: BookSource, keyword: String, depth: SourceValidationStage, httpClient: HTTPClient
    ) async -> SourceValidationOutcome {
        var results: [SourceValidationStageResult] = []

        let domainResult = await checkDomainReachable(source: source, httpClient: httpClient)
        results.append(domainResult)
        guard domainResult.success else {
            return SourceValidationOutcome(source: source, stageResults: results)
        }

        await runSearchChain(source: source, keyword: keyword, depth: depth, httpClient: httpClient, into: &results)

        if let exploreResult = await checkExplore(source: source, httpClient: httpClient) {
            results.append(exploreResult)
        }

        return SourceValidationOutcome(source: source, stageResults: results)
    }

    /// Any non-throwing response (regardless of status code) counts as "reachable" -- even a
    /// 404/403 on the bare base URL still proves DNS resolution, TCP connect, and TLS handshake all
    /// succeeded, which is what "domain reachable" actually means here, distinct from "this exact
    /// page returned valid content."
    private static func checkDomainReachable(source: BookSource, httpClient: HTTPClient) async -> SourceValidationStageResult {
        do {
            _ = try await httpClient.fetch(HTTPRequest(url: source.bookSourceUrl))
            return SourceValidationStageResult(stage: .domain, success: true, detail: "可访问")
        } catch {
            return SourceValidationStageResult(stage: .domain, success: false, detail: "\(error)")
        }
    }

    /// `nil` (not a failing result) when the source has no `exploreUrl` at all -- that's "doesn't
    /// offer 发现," not "发现 is broken," the same distinction `ExploreView.reloadSources` already
    /// draws when deciding which sources even show up there.
    private static func checkExplore(source: BookSource, httpClient: HTTPClient) async -> SourceValidationStageResult? {
        let exploreUrl = source.exploreUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !exploreUrl.isEmpty else { return nil }
        guard let kind = ExploreKindParser.parse(exploreUrl).first(where: {
            !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return SourceValidationStageResult(stage: .explore, success: false, detail: "没有可用的发现分类")
        }
        do {
            let exploreResults = try await ExploreService.fetchExploreList(source: source, exploreURL: kind.url, httpClient: httpClient)
            return SourceValidationStageResult(
                stage: .explore, success: !exploreResults.isEmpty, detail: "\(kind.name): \(exploreResults.count) 个结果"
            )
        } catch {
            return SourceValidationStageResult(stage: .explore, success: false, detail: "\(kind.name): \(error)")
        }
    }

    private static func runSearchChain(
        source: BookSource, keyword: String, depth: SourceValidationStage, httpClient: HTTPClient,
        into results: inout [SourceValidationStageResult]
    ) async {
        let searchResults: [SearchResult]
        do {
            searchResults = try await SearchService.search(source: source, keyword: keyword, httpClient: httpClient)
            results.append(SourceValidationStageResult(stage: .search, success: !searchResults.isEmpty, detail: "\(searchResults.count) 个结果"))
        } catch {
            results.append(SourceValidationStageResult(stage: .search, success: false, detail: "\(error)"))
            return
        }
        guard depth >= .detail, let firstResult = searchResults.first else { return }

        let bookInfo: BookInfo
        do {
            bookInfo = try await BookInfoService.fetchBookInfo(source: source, bookURL: firstResult.bookUrl, httpClient: httpClient)
            results.append(SourceValidationStageResult(stage: .detail, success: true, detail: bookInfo.name ?? "?"))
        } catch {
            results.append(SourceValidationStageResult(stage: .detail, success: false, detail: "\(error)"))
            return
        }
        guard depth >= .toc else { return }

        let chapters: [BookChapter]
        do {
            chapters = try await TocService.fetchChapterList(source: source, tocURL: bookInfo.tocUrl, httpClient: httpClient)
            results.append(SourceValidationStageResult(stage: .toc, success: !chapters.isEmpty, detail: "\(chapters.count) 章"))
        } catch {
            results.append(SourceValidationStageResult(stage: .toc, success: false, detail: "\(error)"))
            return
        }
        guard depth >= .content, let firstChapter = chapters.first else { return }

        do {
            let content = try await ContentService.fetchContent(source: source, chapter: firstChapter, httpClient: httpClient)
            results.append(SourceValidationStageResult(stage: .content, success: !content.text.isEmpty, detail: "\(content.text.count) 字"))
        } catch {
            results.append(SourceValidationStageResult(stage: .content, success: false, detail: "\(error)"))
        }
    }
}
