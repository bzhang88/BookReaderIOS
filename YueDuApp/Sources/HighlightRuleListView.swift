import SwiftUI
import BookSourceModel
import Persistence

struct HighlightRuleListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var rules: [HighlightRule] = []
    @State private var editingRule: HighlightRule?
    @State private var isShowingNewRuleSheet = false

    var body: some View {
        List {
            if rules.isEmpty {
                ContentUnavailableView(
                    "还没有高亮规则", systemImage: "highlighter",
                    description: Text("点右上角 + 新建一条规则，比如高亮某个角色名")
                )
            }
            ForEach(rules) { rule in
                Button {
                    editingRule = rule
                } label: {
                    HStack {
                        Circle()
                            .fill(Color(hex: rule.colorHex ?? "") ?? .orange)
                            .frame(width: 12, height: 12)
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
        .navigationTitle("高亮规则")
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
            HighlightRuleEditView(rule: nil)
        }
        .sheet(item: $editingRule, onDismiss: { Task { await reload() } }) { rule in
            HighlightRuleEditView(rule: rule)
        }
        .task { await reload() }
    }

    private func reload() async {
        rules = (try? await env.highlightRuleStore.all()) ?? []
    }

    private func toggleEnabled(_ rule: HighlightRule, enabled: Bool) {
        Task {
            try? await env.highlightRuleStore.setEnabled(id: rule.id, enabled: enabled)
            await reload()
        }
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { rules[$0] }
        Task {
            for rule in toDelete {
                try? await env.highlightRuleStore.remove(id: rule.id)
            }
            await reload()
        }
    }
}

struct HighlightRuleEditView: View {
    let rule: HighlightRule?

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var pattern: String
    @State private var enabled: Bool
    @State private var color: Color
    @State private var isBold: Bool
    @State private var isUnderlined: Bool

    init(rule: HighlightRule?) {
        self.rule = rule
        _name = State(initialValue: rule?.name ?? "")
        _pattern = State(initialValue: rule?.pattern ?? "")
        _enabled = State(initialValue: rule?.enabled ?? true)
        _color = State(initialValue: rule?.colorHex.flatMap { Color(hex: $0) } ?? .orange)
        _isBold = State(initialValue: rule?.resolvedIsBold ?? true)
        _isUnderlined = State(initialValue: rule?.resolvedIsUnderlined ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("规则") {
                    TextField("名称", text: $name)
                    TextField("匹配内容（正则表达式）", text: $pattern)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Toggle("启用", isOn: $enabled)
                }
                Section("样式") {
                    ColorPicker("颜色", selection: $color, supportsOpacity: false)
                    Toggle("加粗", isOn: $isBold)
                    Toggle("下划线", isOn: $isUnderlined)
                    Text("预览：").font(.caption).foregroundStyle(.secondary)
                        + Text(name.isEmpty ? "示例文字" : name)
                            .foregroundStyle(color)
                            .fontWeight(isBold ? .bold : .regular)
                            .underline(isUnderlined)
                }
            }
            .navigationTitle(rule == nil ? "新建高亮规则" : "编辑高亮规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let saved = HighlightRule(
                            id: rule?.id ?? UUID().uuidString, name: name.isEmpty ? pattern : name,
                            pattern: pattern, enabled: enabled, colorHex: color.toHex(),
                            isBold: isBold, isUnderlined: isUnderlined
                        )
                        Task {
                            try? await env.highlightRuleStore.add(saved)
                            dismiss()
                        }
                    }
                    .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
