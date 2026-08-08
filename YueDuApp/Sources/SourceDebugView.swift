import SwiftUI
import BookSourceModel
import WebBookOrchestrator

/// Runs a source's search -> book info -> table of contents -> chapter content pipeline step by
/// step against a real test keyword, logging each step's output or the exact error it hit -- lets
/// you see exactly which stage a broken source fails at instead of guessing from a generic
/// "search found nothing" in the normal search UI.
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
                    TextField("测试关键词", text: $keyword)
                        .disabled(isRunning)
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

    private func run() async {
        log = []
        isRunning = true

        let results: [SearchResult]
        do {
            results = try await SearchService.search(source: source, keyword: keyword, httpClient: env.httpClient)
            let preview = results.first.map { "，第一个: \($0.name)" } ?? ""
            append("1. 搜索", "找到 \(results.count) 个结果\(preview)")
        } catch {
            append("1. 搜索失败", "\(error)", isError: true)
            isRunning = false
            return
        }

        guard let first = results.first else {
            append("停止", "没有搜索结果，无法继续后续步骤", isError: true)
            isRunning = false
            return
        }

        let bookInfo: BookInfo
        do {
            bookInfo = try await BookInfoService.fetchBookInfo(source: source, bookURL: first.bookUrl, httpClient: env.httpClient)
            append("2. 详情", "书名: \(bookInfo.name ?? "?")，作者: \(bookInfo.author ?? "?")\n目录地址: \(bookInfo.tocUrl)")
        } catch {
            append("2. 详情失败", "\(error)", isError: true)
            isRunning = false
            return
        }

        let chapters: [BookChapter]
        do {
            chapters = try await TocService.fetchChapterList(source: source, tocURL: bookInfo.tocUrl, httpClient: env.httpClient)
            let preview = chapters.first.map { "，第一章: \($0.title)" } ?? ""
            append("3. 目录", "共 \(chapters.count) 章\(preview)")
        } catch {
            append("3. 目录失败", "\(error)", isError: true)
            isRunning = false
            return
        }

        guard let firstChapter = chapters.first else {
            append("停止", "目录是空的，无法继续测试正文", isError: true)
            isRunning = false
            return
        }

        do {
            let content = try await ContentService.fetchContent(source: source, chapter: firstChapter, httpClient: env.httpClient)
            let preview = String(content.text.prefix(200))
            append("4. 正文", "共 \(content.text.count) 字\n预览: \(preview)")
        } catch {
            append("4. 正文失败", "\(error)", isError: true)
        }

        isRunning = false
    }
}
