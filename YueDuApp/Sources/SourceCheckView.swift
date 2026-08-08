import SwiftUI
import BookSourceModel
import WebBookOrchestrator

/// Batch-tests every given source's search against a fixed keyword, showing live pass/fail as
/// results stream in -- reuses `MultiSourceSearchService` exactly as `GlobalSearchView` does, just
/// pointed at a diagnostic keyword instead of the user's actual search. This is the fast way to
/// find out which of a large imported source collection is currently alive, which matters a lot in
/// practice: real-world testing this session found most sources in an old public collection dead.
struct SourceCheckView: View {
    let sources: [BookSource]

    @EnvironmentObject private var env: AppEnvironment
    @State private var keyword = "我"
    @State private var outcomes: [MultiSourceSearchService.SourceOutcome] = []
    @State private var isChecking = false
    @State private var completedCount = 0
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("测试关键词", text: $keyword)
                        .disabled(isChecking)
                    if isChecking {
                        Button("停止", role: .destructive) { stopChecking() }
                    } else {
                        Button("开始检测") { startChecking() }
                            .disabled(keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sources.isEmpty)
                    }
                }
                if isChecking {
                    ProgressView(value: Double(completedCount), total: Double(max(sources.count, 1)))
                    Text("\(completedCount)/\(sources.count) 已完成")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !outcomes.isEmpty {
                Section("结果（\(passCount) 成功 / \(outcomes.count) 已测）") {
                    ForEach(outcomes, id: \.source.bookSourceUrl) { outcome in
                        HStack(alignment: .top) {
                            Image(systemName: outcome.errorDescription == nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(outcome.errorDescription == nil ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(outcome.source.bookSourceName)
                                if let error = outcome.errorDescription {
                                    Text(error)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                } else {
                                    Text("\(outcome.results.count) 个结果")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("书源检测")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var passCount: Int { outcomes.filter { $0.errorDescription == nil }.count }

    private func startChecking() {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sources.isEmpty else { return }

        checkTask?.cancel()
        outcomes = []
        completedCount = 0
        isChecking = true

        checkTask = Task {
            let stream = MultiSourceSearchService.search(sources: sources, keyword: trimmed, httpClient: env.httpClient)
            for await outcome in stream {
                if Task.isCancelled { break }
                outcomes.append(outcome)
                completedCount += 1
            }
            isChecking = false
        }
    }

    private func stopChecking() {
        checkTask?.cancel()
        isChecking = false
    }
}
