import SwiftUI
import BookSourceModel
import Persistence

struct RssListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var sources: [RssSource] = []
    @State private var isShowingAddSheet = false
    @State private var editingSource: RssSource?

    var body: some View {
        NavigationStack {
            List {
                if sources.isEmpty {
                    ContentUnavailableView(
                        "还没有订阅", systemImage: "dot.radiowaves.up.forward",
                        description: Text("点右上角 + 添加一个 RSS 订阅")
                    )
                }
                ForEach(sources) { source in
                    NavigationLink {
                        RssArticleListView(source: source)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.sourceName).font(.headline)
                            Text(source.sourceUrl).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            editingSource = source
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("订阅")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingAddSheet = true
                    } label: {
                        Label("添加", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        RssFavoritesView()
                    } label: {
                        Label("收藏", systemImage: "star")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddSheet, onDismiss: { Task { await reload() } }) {
                RssSourceEditView(source: nil)
            }
            .sheet(item: $editingSource, onDismiss: { Task { await reload() } }) { source in
                RssSourceEditView(source: source)
            }
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    private func reload() async {
        sources = (try? await env.rssSourceStore.all()) ?? []
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { sources[$0] }
        Task {
            for source in toDelete {
                try? await env.rssSourceStore.remove(sourceUrl: source.sourceUrl)
            }
            await reload()
        }
    }
}

/// `source: nil` for add, non-nil for edit -- `RssSourceStore.add` already upserts by `sourceUrl`,
/// so both cases share the same save call. Same optional-source-for-edit-vs-add convention
/// `BookSourceEditView`/`HighlightRuleEditView` already use.
struct RssSourceEditView: View {
    let source: RssSource?

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var url: String
    @State private var sortUrl: String
    @State private var loginUrl: String

    init(source: RssSource?) {
        self.source = source
        _name = State(initialValue: source?.sourceName ?? "")
        _url = State(initialValue: source?.sourceUrl ?? "")
        _sortUrl = State(initialValue: source?.sortUrl ?? "")
        _loginUrl = State(initialValue: source?.loginUrl ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $name)
                    TextField("订阅地址（RSS/Atom URL）", text: $url)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                Section {
                    TextField("分类地址（可留空，一行一个）", text: $sortUrl, axis: .vertical)
                        .lineLimit(3...6)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("分类")
                } footer: {
                    Text("同一订阅有多个分类源时，一行一个，格式\u{201C}分类名::地址\u{201D}，不写分类名就只写地址。")
                }
                Section {
                    TextField("登录页地址（可留空）", text: $loginUrl)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                } header: {
                    Text("登录")
                } footer: {
                    Text("部分订阅内容需要登录才能看到，填了登录页地址后可以在文章列表页用网页登录、抓取 Cookie。")
                }
            }
            .navigationTitle(source == nil ? "添加订阅" : "编辑订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedSortUrl = sortUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedLoginUrl = loginUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            // Same rename-produces-duplicate fix already applied to
                            // `BookSourceEditView` -- `RssSourceStore.add` upserts by matching
                            // `sourceUrl`, so changing the URL while editing needs the old entry
                            // removed explicitly first, or it's left behind as an orphaned duplicate.
                            if let source, source.sourceUrl != trimmedURL {
                                try? await env.rssSourceStore.remove(sourceUrl: source.sourceUrl)
                            }
                            try? await env.rssSourceStore.add(RssSource(
                                sourceUrl: trimmedURL, sourceName: trimmedName.isEmpty ? trimmedURL : trimmedName,
                                sourceGroup: source?.sourceGroup, enabled: source?.enabled ?? true,
                                sortUrl: trimmedSortUrl.isEmpty ? nil : trimmedSortUrl,
                                loginUrl: trimmedLoginUrl.isEmpty ? nil : trimmedLoginUrl
                            ))
                            dismiss()
                        }
                    }
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
