import SwiftUI
import UniformTypeIdentifiers
import BookSourceModel

struct SourceLibraryView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var sources: [BookSource] = []
    @State private var isImporterPresented = false
    @State private var importSummary: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if sources.isEmpty {
                    ContentUnavailableView(
                        "还没有书源", systemImage: "tray",
                        description: Text("点右上角 + 导入一个书源 JSON 文件")
                    )
                }
                ForEach(sources) { source in
                    NavigationLink {
                        SearchView(source: source)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.bookSourceName).font(.headline)
                            Text(source.bookSourceUrl)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
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
            }
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.json]) { result in
                Task { await handleImport(result) }
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
        sources = (try? await env.bookSourceStore.all()) ?? []
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
    /// single bare source object too.
    private func decodeSources(from data: Data) throws -> [BookSource] {
        if let array = try? JSONDecoder().decode([BookSource].self, from: data) {
            return array
        }
        return [try JSONDecoder().decode(BookSource.self, from: data)]
    }
}

#Preview {
    SourceLibraryView()
        .environmentObject(AppEnvironment())
}
