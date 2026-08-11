import SwiftUI
import BookSourceModel
import WebBookOrchestrator

/// Batch-tests every given source against a fixed keyword, showing live pass/fail as results
/// stream in. How far each source is tested is configurable (search only, all the way through to
/// actually fetching a chapter's text) -- real-world testing this session found sources that pass
/// search but fail at detail/toc/content, so a search-only check alone can miss real problems; but
/// always testing all four stages makes a big batch run noticeably slower, so the depth is a
/// user choice rather than fixed.
struct SourceCheckView: View {
    let sources: [BookSource]

    @EnvironmentObject private var env: AppEnvironment
    @State private var keyword = "我"
    @State private var depth: SourceValidationStage = .search
    @State private var outcomes: [SourceValidationOutcome] = []
    @State private var isChecking = false
    @State private var completedCount = 0
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        List {
            controlsSection
            if !outcomes.isEmpty {
                resultsSection
            }
        }
        .navigationTitle("书源检测")
        .navigationBarTitleDisplayMode(.inline)
    }

    // Broken out of `body` (rather than inlined) because the combined expression -- controls +
    // results list with per-source, per-stage nested `ForEach`s -- was too much for the type
    // checker to infer in one pass ("unable to type-check this expression in reasonable time"),
    // a real build break this session's CI actually hit. Splitting into separate `@ViewBuilder`
    // properties gives each piece its own, much smaller expression to infer.
    @ViewBuilder
    private var controlsSection: some View {
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
            Picker("检测深度", selection: $depth) {
                ForEach(SourceValidationStage.allCases, id: \.self) { stage in
                    Text("测到\(stage.displayName)").tag(stage)
                }
            }
            .disabled(isChecking)
            if isChecking {
                ProgressView(value: Double(completedCount), total: Double(max(sources.count, 1)))
                Text("\(completedCount)/\(sources.count) 已完成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        Section("结果（\(passCount) 完全通过 / \(outcomes.count) 已测）") {
            ForEach(outcomes, id: \.source.bookSourceUrl) { outcome in
                resultRow(outcome)
            }
        }
    }

    @ViewBuilder
    private func resultRow(_ outcome: SourceValidationOutcome) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: outcome.isFullyPassing ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(outcome.isFullyPassing ? .green : .red)
                Text(outcome.source.bookSourceName)
            }
            ForEach(outcome.stageResults, id: \.stage) { stageResult in
                Text("\(stageResult.stage.displayName): \(stageResult.detail)")
                    .font(.caption2)
                    .foregroundStyle(stageResult.success ? .secondary : .red)
                    .lineLimit(2)
            }
        }
    }

    private var passCount: Int { outcomes.filter(\.isFullyPassing).count }

    private func startChecking() {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sources.isEmpty else { return }

        checkTask?.cancel()
        outcomes = []
        completedCount = 0
        isChecking = true

        checkTask = Task {
            let stream = SourceValidationService.validate(sources: sources, keyword: trimmed, depth: depth, httpClient: env.httpClient)
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
