import SwiftUI
import BookSourceModel

/// Manages user-added search engines only -- the built-in Bing/Baidu (`WebSearchEngine.defaults`)
/// aren't editable or deletable here, matching Legado's own "built-in + custom" split.
struct WebSearchEngineListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var engines: [WebSearchEngine] = []
    @State private var isShowingNewEngineSheet = false
    @State private var editingEngine: WebSearchEngine?

    var body: some View {
        List {
            Section("内置") {
                ForEach(WebSearchEngine.defaults) { engine in
                    Text(engine.name)
                }
            }
            Section("自定义") {
                if engines.isEmpty {
                    Text("还没有自定义搜索引擎").foregroundStyle(.secondary)
                }
                ForEach(engines) { engine in
                    Button {
                        editingEngine = engine
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(engine.name).font(.headline)
                            Text(engine.urlTemplate).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("搜索引擎")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingNewEngineSheet = true
                } label: {
                    Label("新建", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingNewEngineSheet, onDismiss: { Task { await reload() } }) {
            WebSearchEngineEditView(engine: nil)
        }
        .sheet(item: $editingEngine, onDismiss: { Task { await reload() } }) { engine in
            WebSearchEngineEditView(engine: engine)
        }
        .task { await reload() }
    }

    private func reload() async {
        engines = (try? await env.webSearchEngineStore.all()) ?? []
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { engines[$0] }
        Task {
            for engine in toDelete {
                try? await env.webSearchEngineStore.remove(id: engine.id)
            }
            await reload()
        }
    }
}

struct WebSearchEngineEditView: View {
    let engine: WebSearchEngine?

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var urlTemplate: String

    init(engine: WebSearchEngine?) {
        self.engine = engine
        _name = State(initialValue: engine?.name ?? "")
        _urlTemplate = State(initialValue: engine?.urlTemplate ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("引擎") {
                    TextField("名称", text: $name)
                    TextField("搜索地址（{{query}} 代表搜索词）", text: $urlTemplate)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle(engine == nil ? "新建搜索引擎" : "编辑搜索引擎")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let saved = WebSearchEngine(id: engine?.id ?? UUID().uuidString, name: name.isEmpty ? urlTemplate : name, urlTemplate: urlTemplate)
                        Task {
                            try? await env.webSearchEngineStore.add(saved)
                            dismiss()
                        }
                    }
                    .disabled(!urlTemplate.contains("{{query}}"))
                }
            }
        }
    }
}
