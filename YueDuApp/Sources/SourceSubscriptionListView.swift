import SwiftUI
import BookSourceModel
import Persistence
import NetworkClient

/// Manages remembered book-source JSON URLs so they can be re-fetched later without retyping --
/// distinct from the one-off "从网址导入" flow, which fetches once and forgets the URL. No
/// automatic background refresh (see `BookSourceSubscription`'s doc comment for why); refreshing
/// is always a manual action here, either per-subscription or all at once.
struct SourceSubscriptionListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var subscriptions: [BookSourceSubscription] = []
    @State private var isShowingAddSheet = false
    @State private var isRefreshingAll = false
    @State private var refreshingIds: Set<String> = []
    @State private var resultMessage: String?

    var body: some View {
        List {
            if subscriptions.isEmpty {
                ContentUnavailableView(
                    "还没有订阅", systemImage: "arrow.triangle.2.circlepath.circle",
                    description: Text("订阅一个书源 JSON 网址，以后可以随时一键刷新重新导入")
                )
            }
            ForEach(subscriptions) { subscription in
                subscriptionRow(subscription)
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("书源订阅")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $isShowingAddSheet, onDismiss: { Task { await reload() } }) {
            AddSourceSubscriptionView()
        }
        .alert("刷新结果", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) {
            Button("好") { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
        .task { await reload() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isShowingAddSheet = true
            } label: {
                Label("新建", systemImage: "plus")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await refreshAll() }
            } label: {
                if isRefreshingAll {
                    ProgressView()
                } else {
                    Label("全部刷新", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isRefreshingAll || subscriptions.isEmpty)
        }
    }

    @ViewBuilder
    private func subscriptionRow(_ subscription: BookSourceSubscription) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.name).font(.headline)
                Text(subscription.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let lastUpdatedAt = subscription.lastUpdatedAt {
                    Text("上次刷新: \(lastUpdatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("还没有刷新过").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if refreshingIds.contains(subscription.id) {
                ProgressView()
            } else {
                Button {
                    Task { await refresh(subscription) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func reload() async {
        subscriptions = (try? await env.bookSourceSubscriptionStore.all()) ?? []
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { subscriptions[$0] }
        Task {
            for subscription in toDelete {
                try? await env.bookSourceSubscriptionStore.remove(id: subscription.id)
            }
            await reload()
        }
    }

    private func refreshAll() async {
        isRefreshingAll = true
        var totalInserted = 0
        var totalUpdated = 0
        var failures = 0
        for subscription in subscriptions {
            switch await performRefresh(subscription) {
            case .success(let inserted, let updated):
                totalInserted += inserted
                totalUpdated += updated
            case .failure:
                failures += 1
            }
        }
        isRefreshingAll = false
        await reload()
        resultMessage = "新增 \(totalInserted) 个，更新 \(totalUpdated) 个" + (failures > 0 ? "，\(failures) 个订阅刷新失败" : "")
    }

    private func refresh(_ subscription: BookSourceSubscription) async {
        refreshingIds.insert(subscription.id)
        let outcome = await performRefresh(subscription)
        refreshingIds.remove(subscription.id)
        await reload()
        switch outcome {
        case .success(let inserted, let updated):
            resultMessage = "新增 \(inserted) 个，更新 \(updated) 个"
        case .failure(let error):
            resultMessage = "刷新失败: \(error)"
        }
    }

    private enum RefreshOutcome {
        case success(inserted: Int, updated: Int)
        case failure(String)
    }

    private func performRefresh(_ subscription: BookSourceSubscription) async -> RefreshOutcome {
        do {
            let response = try await env.httpClient.fetch(HTTPRequest(url: subscription.url))
            guard let data = response.body.data(using: .utf8) else {
                return .failure("下载内容无法解析为文本")
            }
            let sources = try BookSourceImportDecoder.decode(from: data)
            let (inserted, updated) = try await env.bookSourceStore.importSources(sources)
            try? await env.bookSourceSubscriptionStore.setLastUpdatedAt(id: subscription.id, date: Date())
            return .success(inserted: inserted, updated: updated)
        } catch {
            return .failure("\(error)")
        }
    }
}

struct AddSourceSubscriptionView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var urlText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("订阅信息") {
                    TextField("名称", text: $name)
                    TextField("书源 JSON 网址", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("新建订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            let subscription = BookSourceSubscription(
                                name: trimmedName.isEmpty ? trimmedURL : trimmedName, url: trimmedURL
                            )
                            try? await env.bookSourceSubscriptionStore.add(subscription)
                            dismiss()
                        }
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
