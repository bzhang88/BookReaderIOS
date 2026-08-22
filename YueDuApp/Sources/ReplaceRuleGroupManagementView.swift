import SwiftUI
import Persistence

/// Direct 净化规则分组 CRUD -- same gap `ShelfGroupManagementView`/`SourceGroupManagementView`
/// already fixed for shelf/book-source groups, just for replace rules: until now a group only ever
/// came into existence as a side effect of typing a name into a rule's own edit form, and vanished
/// the instant no rule referenced it anymore. Backed by `replaceRuleGroupStore` for the "can exist
/// with zero rules" part, merged with whatever group names are still in live use across
/// `replaceRuleStore` so this shows the complete picture regardless of whether a name was ever
/// explicitly registered.
struct ReplaceRuleGroupManagementView: View {
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
                            Text("\(entry.count) 条规则").foregroundStyle(.secondary)
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
        .navigationTitle("净化规则分组管理")
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
        let registered = (try? await env.replaceRuleGroupStore.all()) ?? []
        let rules = (try? await env.replaceRuleStore.all()) ?? []
        var counts: [String: Int] = [:]
        for name in registered { counts[name] = 0 }
        for rule in rules {
            let trimmed = rule.group?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
        try? await env.replaceRuleGroupStore.add(trimmed)
        newGroupName = ""
        await reload()
    }

    private func rename(_ oldName: String, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldName else { return }
        try? await env.replaceRuleGroupStore.rename(oldName, to: trimmed)
        let rules = (try? await env.replaceRuleStore.all()) ?? []
        let updates = rules.filter { $0.group == oldName }.reduce(into: [String: String?]()) { result, rule in
            result[rule.id] = trimmed
        }
        if !updates.isEmpty {
            try? await env.replaceRuleStore.setGroups(updates)
        }
        await reload()
    }

    /// Deleting a group ungroups its rules rather than removing them -- matches Legado's own
    /// behavior (a group is just a label, not a container the rules live inside).
    private func deleteGroup(_ name: String) async {
        try? await env.replaceRuleGroupStore.remove(name)
        let rules = (try? await env.replaceRuleStore.all()) ?? []
        let clearedGroup: String? = nil
        let updates = rules.filter { $0.group == name }.reduce(into: [String: String?]()) { result, rule in
            result[rule.id] = clearedGroup
        }
        if !updates.isEmpty {
            try? await env.replaceRuleStore.setGroups(updates)
        }
        await reload()
    }
}
