import SwiftUI
import BookSourceModel
import Persistence

/// Manages the named TXT chapter-heading patterns tried (in list order) when importing a local
/// .txt file -- an empty library isn't a broken state, `TxtChapterSplitter.splitTryingRules` falls
/// back to its own built-in default pattern, so this screen is purely for adding alternatives.
struct TxtSplitRuleListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var rules: [TxtSplitRule] = []
    @State private var editingRule: TxtSplitRule?
    @State private var isShowingNewRuleSheet = false

    var body: some View {
        List {
            if rules.isEmpty {
                ContentUnavailableView(
                    "还没有自定义分章规则", systemImage: "text.badge.plus",
                    description: Text("默认规则可以识别\u{201C}第X章\u{201D}这类标题；如果你的 txt 文件用别的格式，可以在这里加一条")
                )
            } else {
                Text("导入 txt 时按顺序依次尝试，用第一条能分出多章的规则")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            .onMove(perform: move)
        }
        .navigationTitle("TXT 分章规则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingNewRuleSheet = true
                } label: {
                    Label("新建", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
        }
        .sheet(isPresented: $isShowingNewRuleSheet, onDismiss: { Task { await reload() } }) {
            TxtSplitRuleEditView(rule: nil)
        }
        .sheet(item: $editingRule, onDismiss: { Task { await reload() } }) { rule in
            TxtSplitRuleEditView(rule: rule)
        }
        .task { await reload() }
    }

    private func reload() async {
        rules = (try? await env.txtSplitRuleStore.all()) ?? []
    }

    private func toggleEnabled(_ rule: TxtSplitRule, enabled: Bool) {
        Task {
            try? await env.txtSplitRuleStore.setEnabled(id: rule.id, enabled: enabled)
            await reload()
        }
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { rules[$0] }
        Task {
            for rule in toDelete {
                try? await env.txtSplitRuleStore.remove(id: rule.id)
            }
            await reload()
        }
    }

    /// Reordering matters here (unlike most of this app's other rule lists) -- rule order *is*
    /// priority order for `splitTryingRules`, so this writes the whole reordered list back rather
    /// than just toggling a field.
    private func move(from source: IndexSet, to destination: Int) {
        var reordered = rules
        reordered.move(fromOffsets: source, toOffset: destination)
        rules = reordered
        Task {
            try? await env.txtSplitRuleStore.setAll(reordered)
        }
    }
}

struct TxtSplitRuleEditView: View {
    let rule: TxtSplitRule?

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var pattern: String
    @State private var enabled: Bool

    init(rule: TxtSplitRule?) {
        self.rule = rule
        _name = State(initialValue: rule?.name ?? "")
        _pattern = State(initialValue: rule?.pattern ?? "")
        _enabled = State(initialValue: rule?.enabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("规则") {
                    TextField("名称", text: $name)
                    TextField("章节标题匹配（正则表达式）", text: $pattern)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Toggle("启用", isOn: $enabled)
                } footer: {
                    Text("正则按行匹配，匹配到的整行会成为这一章的标题")
                }
            }
            .navigationTitle(rule == nil ? "新建分章规则" : "编辑分章规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let saved = TxtSplitRule(
                            id: rule?.id ?? UUID().uuidString, name: name.isEmpty ? pattern : name,
                            pattern: pattern, enabled: enabled
                        )
                        Task {
                            try? await env.txtSplitRuleStore.add(saved)
                            dismiss()
                        }
                    }
                    .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
