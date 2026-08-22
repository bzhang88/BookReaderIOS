import SwiftUI
import Persistence

/// Direct 书源分组 CRUD -- the exact same gap `ShelfGroupManagementView` fixed for shelf groups,
/// just for book sources: until now `bookSourceGroup` only ever came into existence as a side
/// effect of typing a name into a source's own edit form, and a group vanished the instant no
/// source referenced it anymore -- no way to create an empty group ahead of time, rename one
/// (previously meant reassigning every source in it one at a time), or delete one outright. Backed
/// by `bookSourceGroupStore` for the "can exist with zero sources" part, merged with whatever group
/// names are still in live use across `bookSourceStore` so this shows the complete picture
/// regardless of whether a name was ever explicitly registered.
struct SourceGroupManagementView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var groupCounts: [(name: String, count: Int)] = []
    @State private var newGroupName = ""
    @State private var renamingGroup: String?
    @State private var renameText = ""

    var body: some View {
        Form {
            Section("新建分组") {
                HStack {
                    TextField("分组名称", text: $newGroupName)
                    Button("创建") { Task { await createGroup() } }
                        .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Section("已有分组") {
                if groupCounts.isEmpty {
                    Text("还没有分组").foregroundStyle(.secondary)
                } else {
                    ForEach(groupCounts, id: \.name) { entry in
                        HStack {
                            Text(entry.name)
                            Spacer()
                            Text("\(entry.count) 个书源").foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await deleteGroup(entry.name) }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                renamingGroup = entry.name
                                renameText = entry.name
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("书源分组管理")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .alert("重命名分组", isPresented: Binding(
            get: { renamingGroup != nil },
            set: { if !$0 { renamingGroup = nil } }
        )) {
            TextField("分组名称", text: $renameText)
            Button("取消", role: .cancel) { renamingGroup = nil }
            Button("确定") {
                if let renamingGroup {
                    Task { await rename(renamingGroup, to: renameText) }
                }
            }
        }
    }

    private func reload() async {
        let registered = (try? await env.bookSourceGroupStore.all()) ?? []
        let sources = (try? await env.bookSourceStore.all()) ?? []
        var counts: [String: Int] = [:]
        for name in registered { counts[name] = 0 }
        for source in sources {
            let trimmed = source.bookSourceGroup?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { continue }
            counts[trimmed, default: 0] += 1
        }
        groupCounts = counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func createGroup() async {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await env.bookSourceGroupStore.add(trimmed)
        newGroupName = ""
        await reload()
    }

    /// Renames the registry entry and every source currently filed under the old name in one batch
    /// -- leaving sources behind with a group name that no longer appears anywhere would strand them
    /// in an orphaned, invisible group.
    private func rename(_ oldName: String, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldName else { return }
        try? await env.bookSourceGroupStore.rename(oldName, to: trimmed)
        let sources = (try? await env.bookSourceStore.all()) ?? []
        let updates = sources.filter { $0.bookSourceGroup == oldName }.reduce(into: [String: String?]()) { result, source in
            result[source.bookSourceUrl] = trimmed
        }
        if !updates.isEmpty {
            try? await env.bookSourceStore.setGroups(updates)
        }
        await reload()
    }

    /// Deleting a group ungroups its sources rather than removing them -- matches Legado's own
    /// behavior (a group is just a label, not a container the sources live inside).
    private func deleteGroup(_ name: String) async {
        try? await env.bookSourceGroupStore.remove(name)
        let sources = (try? await env.bookSourceStore.all()) ?? []
        let clearedGroup: String? = nil
        let updates = sources.filter { $0.bookSourceGroup == name }.reduce(into: [String: String?]()) { result, source in
            result[source.bookSourceUrl] = clearedGroup
        }
        if !updates.isEmpty {
            try? await env.bookSourceStore.setGroups(updates)
        }
        await reload()
    }
}
