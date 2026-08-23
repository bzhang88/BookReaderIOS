import SwiftUI
import BookSourceModel
import WebBookOrchestrator

/// Runs a source's search -> book info -> table of contents -> chapter content pipeline step by
/// step against a real test keyword, logging each step's output or the exact error it hit -- lets
/// you see exactly which stage a broken source fails at instead of guessing from a generic
/// "search found nothing" in the normal search UI.
///
/// Real gap found comparing against Legado's own `Debug.startDebug(scope:bookSource:key:)`: this
/// used to always start from search, with no way to isolate a later stage that's already known to
/// work -- debugging just the content-extraction rule meant re-running search+detail+toc every
/// single time even after those were confirmed fine. Mirrors Legado's exact input-syntax convention
/// (same prefixes, same meaning) so the single text field can jump straight into any stage:
/// `--<正文URL>` starts at 正文, `++<目录URL>` starts at 目录 (then continues into 正文),
/// `分类名::<发现URL>` starts at 发现 (then continues through 详情/目录/正文), a bare `http(s)://`
/// URL is treated as a 详情 page URL (then continues through 目录/正文), and anything else is a
/// plain search keyword -- the full four-stage pipeline, unchanged from before.
struct SourceDebugView: View {
    let source: BookSource

    @EnvironmentObject private var env: AppEnvironment
    @State private var keyword = "我"
    @State private var log: [DebugLogEntry] = []
    @State private var isRunning = false

    struct DebugLogEntry: Identifiable {
        let id = UUID()
        var step: String
        var detail: String
        var isError: Bool
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("测试关键词，或 --正文URL / ++目录URL / 分类名::发现URL / 详情URL", text: $keyword)
                        .disabled(isRunning)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("运行") { Task { await run() } }
                        .disabled(isRunning || keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if isRunning {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } footer: {
                Text("单阶段调试：以 -- 开头直接测正文，++ 开头直接测目录（会继续测正文），"
                    + "含 :: 时把 :: 后面当发现页地址测（会继续测详情/目录/正文），"
                    + "直接填 http(s):// 开头的详情页地址（会继续测目录/正文）。留空前缀就是普通关键词搜索。")
            }
            if !log.isEmpty {
                Section("日志") {
                    ForEach(log) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.step)
                                .font(.headline)
                                .foregroundStyle(entry.isError ? .red : .primary)
                            Text(entry.detail)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("调试: \(source.bookSourceName)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func append(_ step: String, _ detail: String, isError: Bool = false) {
        log.append(DebugLogEntry(step: step, detail: detail, isError: isError))
    }

    /// Dispatches on the input syntax to whichever stage should run first -- see this type's own
    /// doc comment for the exact prefix convention (mirrored from Legado's `Debug.startDebug`).
    /// Order matters: `--`/`++` are checked before the bare-URL case since a pasted URL could
    /// legitimately start with either after its own scheme, and `::` is checked before the bare-URL
    /// case too since an explore entry's category name could itself look like it starts with `http`.
    private func run() async {
        log = []
        isRunning = true
        defer { isRunning = false }

        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("--") {
            let url = String(trimmed.dropFirst(2))
            append("⇒直接调试正文页", url)
            await debugContent(BookChapter(index: 0, title: "调试", url: url))
        } else if trimmed.hasPrefix("++") {
            let url = String(trimmed.dropFirst(2))
            append("⇒直接调试目录页", url)
            await debugToc(tocUrl: url)
        } else if let separatorRange = trimmed.range(of: "::") {
            let url = String(trimmed[separatorRange.upperBound...])
            append("⇒直接调试发现页", url)
            await debugExplore(url: url)
        } else if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            append("⇒直接调试详情页", trimmed)
            await debugInfo(bookUrl: trimmed)
        } else {
            await debugSearch(keyword: trimmed)
        }
    }

    private func debugSearch(keyword: String) async {
        let results: [SearchResult]
        do {
            results = try await SearchService.search(source: source, keyword: keyword, httpClient: env.httpClient)
            let preview = results.first.map { "，第一个: \($0.name)" } ?? ""
            append("1. 搜索", "找到 \(results.count) 个结果\(preview)")
        } catch {
            append("1. 搜索失败", "\(error)", isError: true)
            return
        }
        guard let first = results.first else {
            append("停止", "没有搜索结果，无法继续后续步骤", isError: true)
            return
        }
        await debugInfo(bookUrl: first.bookUrl)
    }

    private func debugExplore(url: String) async {
        let results: [SearchResult]
        do {
            results = try await ExploreService.fetchExploreList(source: source, exploreURL: url, httpClient: env.httpClient)
            let preview = results.first.map { "，第一个: \($0.name)" } ?? ""
            append("发现页", "找到 \(results.count) 个结果\(preview)")
        } catch {
            append("发现页失败", "\(error)", isError: true)
            return
        }
        guard let first = results.first else {
            append("停止", "发现页没有结果，无法继续后续步骤", isError: true)
            return
        }
        await debugInfo(bookUrl: first.bookUrl)
    }

    private func debugInfo(bookUrl: String) async {
        let bookInfo: BookInfo
        do {
            bookInfo = try await BookInfoService.fetchBookInfo(source: source, bookURL: bookUrl, httpClient: env.httpClient)
            append("2. 详情", "书名: \(bookInfo.name ?? "?")，作者: \(bookInfo.author ?? "?")\n目录地址: \(bookInfo.tocUrl)")
        } catch {
            append("2. 详情失败", "\(error)", isError: true)
            return
        }
        await debugToc(tocUrl: bookInfo.tocUrl)
    }

    private func debugToc(tocUrl: String) async {
        let chapters: [BookChapter]
        do {
            chapters = try await TocService.fetchChapterList(source: source, tocURL: tocUrl, httpClient: env.httpClient)
            let preview = chapters.first.map { "，第一章: \($0.title)" } ?? ""
            append("3. 目录", "共 \(chapters.count) 章\(preview)")
        } catch {
            append("3. 目录失败", "\(error)", isError: true)
            return
        }
        guard let firstChapter = chapters.first else {
            append("停止", "目录是空的，无法继续测试正文", isError: true)
            return
        }
        await debugContent(firstChapter)
    }

    private func debugContent(_ chapter: BookChapter) async {
        do {
            let content = try await ContentService.fetchContent(source: source, chapter: chapter, httpClient: env.httpClient)
            let preview = String(content.text.prefix(200))
            append("4. 正文", "共 \(content.text.count) 字\n预览: \(preview)")
        } catch {
            append("4. 正文失败", "\(error)", isError: true)
        }
    }
}
