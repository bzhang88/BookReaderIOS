import SwiftUI
import BookSourceModel
import Persistence

/// AI provider/model configuration -- plumbing only. No feature in the app actually calls an AI
/// API yet (chat assistant, chapter summary, etc. are separate, larger increments involving real
/// paid network calls); this just lets the user register a provider and store its key safely so
/// those features have something to consume later, without spending anything or making any
/// outbound request itself.
struct AIProviderListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var providers: [AIProvider] = []
    @State private var editingProvider: AIProvider?
    @State private var isShowingNewSheet = false

    var body: some View {
        List {
            if providers.isEmpty {
                ContentUnavailableView(
                    "还没有配置 AI 服务商", systemImage: "sparkles",
                    description: Text("点右上角 + 添加一个，需要自己准备第三方 API Key")
                )
            }
            ForEach(providers) { provider in
                Button {
                    editingProvider = provider
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.name)
                            .font(.headline)
                            .foregroundStyle(provider.enabled ? .primary : .secondary)
                        Text(provider.modelName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("AI 服务商")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingNewSheet = true
                } label: {
                    Label("添加", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingNewSheet, onDismiss: { Task { await reload() } }) {
            AIProviderEditView(provider: nil)
        }
        .sheet(item: $editingProvider, onDismiss: { Task { await reload() } }) { provider in
            AIProviderEditView(provider: provider)
        }
        .task { await reload() }
    }

    private func reload() async {
        providers = (try? await env.aiProviderStore.all()) ?? []
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { providers[$0] }
        Task {
            for provider in toDelete {
                try? await env.aiProviderStore.remove(id: provider.id)
                KeychainStore.delete("ai.apiKey.\(provider.id)")
            }
            await reload()
        }
    }
}

struct AIProviderEditView: View {
    let provider: AIProvider?

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var baseURL: String
    @State private var modelName: String
    @State private var apiKey: String
    @State private var enabled: Bool

    private let providerID: String

    init(provider: AIProvider?) {
        self.provider = provider
        let resolvedID = provider?.id ?? UUID().uuidString
        self.providerID = resolvedID
        _name = State(initialValue: provider?.name ?? "")
        _baseURL = State(initialValue: provider?.baseURL ?? "https://api.openai.com/v1")
        _modelName = State(initialValue: provider?.modelName ?? "")
        _apiKey = State(initialValue: KeychainStore.get("ai.apiKey.\(resolvedID)") ?? "")
        _enabled = State(initialValue: provider?.enabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("服务商") {
                    TextField("名称", text: $name)
                    TextField("Base URL（OpenAI 兼容接口）", text: $baseURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("模型名称", text: $modelName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("API Key", text: $apiKey)
                }
                Section {
                    Toggle("启用", isOn: $enabled)
                } footer: {
                    Text("API Key 只存在系统 Keychain 里，不会跟其他设置一起备份/导出。")
                }
            }
            .navigationTitle(provider == nil ? "新建 AI 服务商" : "编辑 AI 服务商")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        KeychainStore.set(apiKey, forKey: "ai.apiKey.\(providerID)")
        let saved = AIProvider(id: providerID, name: name, baseURL: baseURL, modelName: modelName, enabled: enabled)
        Task {
            try? await env.aiProviderStore.add(saved)
            dismiss()
        }
    }
}
