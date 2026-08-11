import SwiftUI
import BookSourceModel

struct HttpTTSEngineListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var engines: [HttpTTSEngine] = []
    @State private var isShowingNewEngineSheet = false
    @State private var editingEngine: HttpTTSEngine?
    @State private var cacheSizeBytes: Int64 = 0

    var body: some View {
        List {
            Section {
                if engines.isEmpty {
                    ContentUnavailableView(
                        "还没有自定义朗读引擎", systemImage: "waveform",
                        description: Text("加一条后可以在阅读设置里选用它替代系统朗读")
                    )
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
            Section {
                HStack {
                    Text("音频缓存占用")
                    Spacer()
                    Text(formattedSize(cacheSizeBytes)).foregroundStyle(.secondary)
                }
                Button("清空音频缓存", role: .destructive) {
                    Task { await clearCache() }
                }
                .disabled(cacheSizeBytes == 0)
            }
        }
        .navigationTitle("自定义朗读引擎")
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
            HttpTTSEngineEditView(engine: nil)
        }
        .sheet(item: $editingEngine, onDismiss: { Task { await reload() } }) { engine in
            HttpTTSEngineEditView(engine: engine)
        }
        .task { await reload() }
    }

    private func reload() async {
        engines = (try? await env.httpTTSEngineStore.all()) ?? []
        cacheSizeBytes = await env.httpTTSCache.totalSizeBytes()
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { engines[$0] }
        Task {
            for engine in toDelete {
                try? await env.httpTTSEngineStore.remove(id: engine.id)
            }
            await reload()
        }
    }

    private func clearCache() async {
        try? await env.httpTTSCache.removeAll()
        cacheSizeBytes = await env.httpTTSCache.totalSizeBytes()
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct HttpTTSEngineEditView: View {
    let engine: HttpTTSEngine?

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var urlTemplate: String

    init(engine: HttpTTSEngine?) {
        self.engine = engine
        _name = State(initialValue: engine?.name ?? "")
        _urlTemplate = State(initialValue: engine?.urlTemplate ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $name)
                    TextField("朗读地址（{{text}} 代表要朗读的文字）", text: $urlTemplate)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("引擎")
                } footer: {
                    Text("请求这个地址应该直接返回音频数据")
                }
            }
            .navigationTitle(engine == nil ? "新建朗读引擎" : "编辑朗读引擎")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let saved = HttpTTSEngine(id: engine?.id ?? UUID().uuidString, name: name.isEmpty ? urlTemplate : name, urlTemplate: urlTemplate)
                        Task {
                            try? await env.httpTTSEngineStore.add(saved)
                            dismiss()
                        }
                    }
                    .disabled(!urlTemplate.contains("{{text}}"))
                }
            }
        }
    }
}
