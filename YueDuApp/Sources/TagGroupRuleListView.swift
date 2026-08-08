import SwiftUI
import BookSourceModel
import Persistence

struct TagGroupRuleListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var rules: [TagGroupRule] = []
    @State private var editingRule: TagGroupRule?
    @State private var isShowingNewRuleSheet = false

    var body: some View {
        List {
            if rules.isEmpty {
                ContentUnavailableView(
                    "还没有分组规则", systemImage: "tag",
                    description: Text("点右上角 + 新建一条规则，比如把书名或简介里含\"网游\"的书自动归到\"游戏\"分组")
                )
            }
            ForEach(rules) { rule in
                Button {
                    editingRule = rule
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.groupName)
                                .font(.headline)
                                .foregroundStyle(rule.enabled ? .primary : .secondary)
                            Text(rule.pattern)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { rule.enabled },
                            set: { toggleEnabled(rule, enabled: $0) }
                        ))
                        .labelsHidden()
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("分组规则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingNewRuleSheet = true
                } label: {
                    Label("新建", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingNewRuleSheet, onDismiss: { Task { await reload() } }) {
            TagGroupRuleEditView(rule: nil)
        }
        .sheet(item: $editingRule, onDismiss: { Task { await reload() } }) { rule in
            TagGroupRuleEditView(rule: rule)
        }
        .task { await reload() }
    }

    private func reload() async {
        rules = (try? await env.tagGroupRuleStore.all()) ?? []
    }

    private func toggleEnabled(_ rule: TagGroupRule, enabled: Bool) {
        Task {
            try? await env.tagGroupRuleStore.setEnabled(id: rule.id, enabled: enabled)
            await reload()
        }
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { rules[$0] }
        Task {
            for rule in toDelete {
                try? await env.tagGroupRuleStore.remove(id: rule.id)
            }
            await reload()
        }
    }
}

struct TagGroupRuleEditView: View {
    let rule: TagGroupRule?

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var groupName: String
    @State private var pattern: String
    @State private var enabled: Bool

    init(rule: TagGroupRule?) {
        self.rule = rule
        _groupName = State(initialValue: rule?.groupName ?? "")
        _pattern = State(initialValue: rule?.pattern ?? "")
        _enabled = State(initialValue: rule?.enabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("规则") {
                    TextField("分组名称", text: $groupName)
                    TextField("匹配书名/作者/简介（正则表达式）", text: $pattern)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Toggle("启用", isOn: $enabled)
                } footer: {
                    Text("在书架点\"自动分组\"时，会按规则顺序取第一条匹配的分组。")
                }
            }
            .navigationTitle(rule == nil ? "新建分组规则" : "编辑分组规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let saved = TagGroupRule(
                            id: rule?.id ?? UUID().uuidString,
                            groupName: groupName.isEmpty ? pattern : groupName,
                            pattern: pattern, enabled: enabled
                        )
                        Task {
                            try? await env.tagGroupRuleStore.add(saved)
                            dismiss()
                        }
                    }
                    .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
