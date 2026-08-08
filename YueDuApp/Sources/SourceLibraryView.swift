import SwiftUI
import UniformTypeIdentifiers
import BookSourceModel
import RuleEngine
import Persistence

struct SourceLibraryView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var sources: [BookSource] = []
    @State private var capabilityReports: [String: SourceCapabilityReport] = [:]
    @State private var isImporterPresented = false
    @State private var importSummary: String?
    @State private var errorMessage: String?
    @State private var editingSource: BookSource?
    @State private var isCreatingSource = false
    @State private var debuggingSource: BookSource?

    var body: some View {
        NavigationStack {
            List {
                if sources.isEmpty {
                    ContentUnavailableView(
                        "还没有书源", systemImage: "tray",
                        description: Text("点右上角 + 导入一个书源 JSON 文件")
                    )
                } else {
                    Text("点一个书源可以启用/停用它——只有启用的书源才会参与搜索")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(sources) { source in
                    Button {
                        toggleEnabled(source)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(source.bookSourceName)
                                        .font(.headline)
                                        .foregroundStyle(source.enabled ? .primary : .secondary)
                                    if let report = capabilityReports[source.bookSourceUrl], !report.isFullyCompatible {
                                        Text("\(report.issues.count) 项不支持")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.orange.opacity(0.2), in: Capsule())
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Text(source.bookSourceUrl)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: source.enabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(source.enabled ? .green : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading) {
                        Button {
                            editingSource = source
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            editingSource = source
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        Button {
                            debuggingSource = source
                        } label: {
                            Label("调试", systemImage: "ladybug")
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("书源库")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("导入", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        SourceCheckView(sources: sources)
                    } label: {
                        Label("检测书源", systemImage: "checkmark.shield")
                    }
                    .disabled(sources.isEmpty)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("新建书源") { isCreatingSource = true }
                        Button("全部启用") { setAllEnabled(true) }.disabled(sources.isEmpty)
                        Button("全部停用") { setAllEnabled(false) }.disabled(sources.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.json]) { result in
                Task { await handleImport(result) }
            }
            .sheet(item: $editingSource, onDismiss: { Task { await reload() } }) { source in
                BookSourceEditView(source: source)
            }
            .sheet(isPresented: $isCreatingSource, onDismiss: { Task { await reload() } }) {
                BookSourceEditView(source: nil)
            }
            .navigationDestination(isPresented: Binding(
                get: { debuggingSource != nil },
                set: { if !$0 { debuggingSource = nil } }
            )) {
                if let debuggingSource {
                    SourceDebugView(source: debuggingSource)
                }
            }
            .alert("导入完成", isPresented: .constant(importSummary != nil)) {
                Button("好") { importSummary = nil }
            } message: {
                Text(importSummary ?? "")
            }
            .alert("导入失败", isPresented: .constant(errorMessage != nil)) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    private func reload() async {
        let all = (try? await env.bookSourceStore.all()) ?? []
        sources = all
        capabilityReports = Dictionary(
            uniqueKeysWithValues: CapabilityScanner.scan(all).map { ($0.sourceUrl, $0) }
        )
    }

    private func toggleEnabled(_ source: BookSource) {
        Task {
            try? await env.bookSourceStore.setEnabled(bookSourceUrl: source.bookSourceUrl, enabled: !source.enabled)
            await reload()
        }
    }

    private func setAllEnabled(_ enabled: Bool) {
        Task {
            try? await env.bookSourceStore.setAllEnabled(enabled)
            await reload()
        }
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { sources[$0] }
        Task {
            for source in toDelete {
                try? await env.bookSourceStore.remove(bookSourceUrl: source.bookSourceUrl)
            }
            await reload()
        }
    }

    private func handleImport(_ result: Result<URL, Error>) async {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let imported = try decodeSources(from: data)
            let (inserted, updated) = try await env.bookSourceStore.importSources(imported)
            await reload()
            importSummary = "新增 \(inserted) 个，更新 \(updated) 个"
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Real book-source files are almost always a top-level array of many sources, but tolerate a
    /// single bare source object too. Tries the (expected, common) array shape first and surfaces
    /// *that* error on failure -- not the fallback's, which is always a confusing
    /// "expected Dictionary but found an array" when the file is an array (the common case) and
    /// the real problem is actually somewhere inside one of its elements.
    private func decodeSources(from data: Data) throws -> [BookSource] {
        do {
            return try JSONDecoder().decode([BookSource].self, from: data)
        } catch let arrayDecodingError {
            if let single = try? JSONDecoder().decode(BookSource.self, from: data) {
                return [single]
            }
            throw arrayDecodingError
        }
    }
}

#Preview {
    SourceLibraryView()
        .environmentObject(AppEnvironment())
}
