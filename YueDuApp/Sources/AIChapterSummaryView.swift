import SwiftUI
import BookSourceModel
import AIService
import NetworkClient

/// The first (and so far only) AI feature in this app that actually calls out to a real API --
/// `AIProviderListView` only ever configured providers before this. Picks an enabled provider,
/// reads its API key from Keychain, and asks it to summarize the chapter currently on screen.
struct AIChapterSummaryView: View {
    let chapterTitle: String
    let chapterText: String

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var providers: [AIProvider] = []
    @State private var selectedProviderID: String?
    @State private var isLoading = false
    @State private var summary: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if providers.isEmpty {
                    ContentUnavailableView(
                        "还没有可用的 AI 服务商", systemImage: "sparkles",
                        description: Text("先在“我的”里添加并启用一个 AI 服务商配置")
                    )
                } else {
                    Section("服务商") {
                        Picker("服务商", selection: $selectedProviderID) {
                            ForEach(providers) { provider in
                                Text(provider.name).tag(Optional(provider.id))
                            }
                        }
                    }
                    Section("摘要") {
                        if isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else if let summary {
                            Text(summary)
                        } else if let errorMessage {
                            Text(errorMessage).foregroundStyle(Color.red)
                        } else {
                            Text("点下方按钮生成本章摘要").foregroundStyle(.secondary)
                        }
                        Button(summary == nil ? "生成本章摘要" : "重新生成") {
                            Task { await generate() }
                        }
                        .disabled(isLoading || selectedProviderID == nil)
                    }
                }
            }
            .navigationTitle("AI 章节摘要")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await loadProviders() }
        }
        .presentationDetents([.medium, .large])
    }

    private func loadProviders() async {
        let all = (try? await env.aiProviderStore.all()) ?? []
        providers = all.filter(\.enabled)
        selectedProviderID = providers.first?.id
    }

    /// Chapters can run long enough that sending the whole thing would blow past a typical model's
    /// context window (and cost real money per token) -- capped rather than chunked-and-combined,
    /// since a chunked-summary-of-summaries is a materially bigger feature than this increment's
    /// worth and a truncated-but-honest summary is still useful for a "what happened in this
    /// chapter" glance.
    private func generate() async {
        guard let provider = providers.first(where: { $0.id == selectedProviderID }) else { return }
        let apiKey = KeychainStore.get("ai.apiKey.\(provider.id)") ?? ""
        guard !apiKey.isEmpty else {
            errorMessage = "这个服务商还没有配置 API Key，请先在“我的”里补上"
            return
        }
        isLoading = true
        errorMessage = nil
        summary = nil
        let truncated = String(chapterText.prefix(6000))
        let prompt = "请用中文简要总结以下小说章节《\(chapterTitle)》的内容，200字以内：\n\n\(truncated)"
        do {
            summary = try await AIChatService.complete(
                provider: provider, apiKey: apiKey, prompt: prompt, httpClient: env.httpClient
            )
        } catch {
            errorMessage = "生成失败: \(error)"
        }
        isLoading = false
    }
}
