import SwiftUI
import BookSourceModel
import Persistence

struct RssListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var sources: [RssSource] = []
    @State private var isShowingAddSheet = false

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
            }
            .sheet(isPresented: $isShowingAddSheet, onDismiss: { Task { await reload() } }) {
                RssSourceAddView()
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

struct RssSourceAddView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $name)
                TextField("订阅地址（RSS/Atom URL）", text: $url)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
            .navigationTitle("添加订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            try? await env.rssSourceStore.add(RssSource(
                                sourceUrl: trimmedURL, sourceName: trimmedName.isEmpty ? trimmedURL : trimmedName
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
