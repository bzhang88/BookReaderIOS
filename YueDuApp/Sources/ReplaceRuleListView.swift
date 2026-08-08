import SwiftUI
import BookSourceModel
import Persistence

struct ReplaceRuleListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var rules: [ReplaceRule] = []
    @State private var editingRule: ReplaceRule?
    @State private var isShowingNewRuleSheet = false

    var body: some View {
        List {
            if rules.isEmpty {
                ContentUnavailableView(
                    "还没有净化规则", systemImage: "wand.and.stars",
                    description: Text("点右上角 + 新建一条规则，比如去除正文里的广告文字")
                )
            }
            ForEach(rules) { rule in
                Button {
                    editingRule = rule
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.name)
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
        .navigationTitle("净化规则")
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
        .sheet(isPresented: $isShowingNewRuleSheet) {
            ReplaceRuleEditView(rule: nil) { newRule in
                Task {
                    try? await env.replaceRuleStore.add(newRule)
                    await reload()
                }
            }
        }
        .sheet(item: $editingRule) { rule in
            ReplaceRuleEditView(rule: rule) { updatedRule in
                Task {
                    try? await env.replaceRuleStore.update(updatedRule)
                    await reload()
                }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        rules = (try? await env.replaceRuleStore.all()) ?? []
    }

    private func toggleEnabled(_ rule: ReplaceRule, enabled: Bool) {
        Task {
            try? await env.replaceRuleStore.setEnabled(id: rule.id, enabled: enabled)
            await reload()
        }
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { rules[$0] }
        Task {
            for rule in toDelete {
                try? await env.replaceRuleStore.remove(id: rule.id)
            }
            await reload()
        }
    }
}

struct ReplaceRuleEditView: View {
    let rule: ReplaceRule?
    let onSave: (ReplaceRule) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var pattern: String
    @State private var replacement: String
    @State private var isRegex: Bool
    @State private var enabled: Bool

    init(rule: ReplaceRule?, onSave: @escaping (ReplaceRule) -> Void) {
        self.rule = rule
        self.onSave = onSave
        _name = State(initialValue: rule?.name ?? "")
        _pattern = State(initialValue: rule?.pattern ?? "")
        _replacement = State(initialValue: rule?.replacement ?? "")
        _isRegex = State(initialValue: rule?.isRegex ?? true)
        _enabled = State(initialValue: rule?.enabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("规则") {
                    TextField("名称", text: $name)
                    TextField("匹配内容（正则或纯文本）", text: $pattern)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("替换为（留空即删除）", text: $replacement)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Toggle("按正则表达式匹配", isOn: $isRegex)
                    Toggle("启用", isOn: $enabled)
                }
            }
            .navigationTitle(rule == nil ? "新建规则" : "编辑规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let saved = ReplaceRule(
                            id: rule?.id ?? UUID().uuidString, name: name.isEmpty ? pattern : name,
                            pattern: pattern, replacement: replacement, isRegex: isRegex,
                            scopeSourceUrl: rule?.scopeSourceUrl, enabled: enabled
                        )
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
