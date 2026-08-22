import Foundation
import BookSourceModel
import NetworkClient

/// How far into the search -> detail -> toc -> content pipeline a batch source check goes --
/// ordered so `depth >= stage` reads naturally as "this run was configured to reach at least this
/// far". Matches `SourceDebugView`'s existing single-source, four-step pipeline, just run across
/// many sources at once and stoppable early instead of always running all four steps.
public enum SourceValidationStage: Int, CaseIterable, Comparable, Sendable {
    case search, detail, toc, content

    public static func < (lhs: SourceValidationStage, rhs: SourceValidationStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .search: return "搜索"
        case .detail: return "详情"
        case .toc: return "目录"
        case .content: return "正文"
        }
    }
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

    private static func validateOne(
        source: BookSource, keyword: String, depth: SourceValidationStage, httpClient: HTTPClient
    ) async -> SourceValidationOutcome {
        var results: [SourceValidationStageResult] = []

        let searchResults: [SearchResult]
        do {
            searchResults = try await SearchService.search(source: source, keyword: keyword, httpClient: httpClient)
            results.append(SourceValidationStageResult(stage: .search, success: !searchResults.isEmpty, detail: "\(searchResults.count) 个结果"))
        } catch {
            results.append(SourceValidationStageResult(stage: .search, success: false, detail: "\(error)"))
            return SourceValidationOutcome(source: source, stageResults: results)
        }
        guard depth >= .detail, let firstResult = searchResults.first else {
            return SourceValidationOutcome(source: source, stageResults: results)
        }

        let bookInfo: BookInfo
        do {
            bookInfo = try await BookInfoService.fetchBookInfo(source: source, bookURL: firstResult.bookUrl, httpClient: httpClient)
            results.append(SourceValidationStageResult(stage: .detail, success: true, detail: bookInfo.name ?? "?"))
        } catch {
            results.append(SourceValidationStageResult(stage: .detail, success: false, detail: "\(error)"))
            return SourceValidationOutcome(source: source, stageResults: results)
        }
        guard depth >= .toc else {
            return SourceValidationOutcome(source: source, stageResults: results)
        }

        let chapters: [BookChapter]
        do {
            chapters = try await TocService.fetchChapterList(source: source, tocURL: bookInfo.tocUrl, httpClient: httpClient)
            results.append(SourceValidationStageResult(stage: .toc, success: !chapters.isEmpty, detail: "\(chapters.count) 章"))
        } catch {
            results.append(SourceValidationStageResult(stage: .toc, success: false, detail: "\(error)"))
            return SourceValidationOutcome(source: source, stageResults: results)
        }
        guard depth >= .content, let firstChapter = chapters.first else {
            return SourceValidationOutcome(source: source, stageResults: results)
        }

        do {
            let content = try await ContentService.fetchContent(source: source, chapter: firstChapter, httpClient: httpClient)
            results.append(SourceValidationStageResult(stage: .content, success: !content.text.isEmpty, detail: "\(content.text.count) 字"))
        } catch {
            results.append(SourceValidationStageResult(stage: .content, success: false, detail: "\(error)"))
        }
        return SourceValidationOutcome(source: source, stageResults: results)
    }
}
