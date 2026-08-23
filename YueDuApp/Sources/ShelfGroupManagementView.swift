import SwiftUI
import Persistence

/// Direct group CRUD -- until now a group only ever came into existence as a side effect of
/// assigning it to a book (`ShelfGroupPickerView`'s "新建分组"), and vanished the instant no book
/// referenced it anymore. This is the real gap that surfaced doing so: no way to create an empty
/// group ahead of time, rename one (previously meant reassigning every book in it one at a time),
/// or delete one outright. Backed by `ShelfGroupStore` for the "can exist with zero books" part,
/// merged with whatever group names are still in live use on the shelf so this shows the complete
/// picture regardless of whether a name was ever explicitly registered.
struct ShelfGroupManagementView: View {
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
                            Text("\(entry.count) 本").foregroundStyle(.secondary)
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
        .navigationTitle("分组管理")
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
        let registered = (try? await env.shelfGroupStore.all()) ?? []
        let books = (try? await env.shelfStore.all()) ?? []
        var counts: [String: Int] = [:]
        for name in registered { counts[name] = 0 }
        for book in books {
            for group in book.groups {
                let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                counts[trimmed, default: 0] += 1
            }
        }
        groupCounts = counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func createGroup() async {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await env.shelfGroupStore.add(trimmed)
        newGroupName = ""
        await reload()
    }

    /// Renames the registry entry and every book currently filed under the old name in one batch --
    /// leaving books behind with a group name that no longer appears anywhere would strand them in
    /// an orphaned, invisible group. `renameGroupEverywhere` replaces just this one name within each
    /// book's `groups`, preserving any other groups that same book also belongs to.
    private func rename(_ oldName: String, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldName else { return }
        try? await env.shelfGroupStore.rename(oldName, to: trimmed)
        try? await env.shelfStore.renameGroupEverywhere(oldName, to: trimmed)
        await reload()
    }

    /// Deleting a group ungroups its books rather than removing them -- matches Legado's own
    /// behavior (a group is just a label, not a container the books live inside).
    /// `removeGroupEverywhere` removes just this one name from each book's `groups`, preserving any
    /// other groups that same book also belongs to.
    private func deleteGroup(_ name: String) async {
        try? await env.shelfGroupStore.remove(name)
        try? await env.shelfStore.removeGroupEverywhere(name)
        await reload()
    }
}
