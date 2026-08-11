import SwiftUI
import BookSourceModel

/// Manages dictionary/word-lookup sources -- CRUD only, no reordering (unlike `TxtSplitRuleListView`,
/// a dict lookup queries one rule the user explicitly picks in `DictLookupView`, not a
/// try-in-order cascade, so list position doesn't mean anything here).
struct DictRuleListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var rules: [DictRule] = []
    @State private var editingRule: DictRule?
    @State private var isShowingNewRuleSheet = false

    var body: some View {
        List {
            if rules.isEmpty {
                ContentUnavailableView(
                    "还没有词典规则", systemImage: "character.book.closed",
                    description: Text("加一条词典规则后，阅读时可以长按查词入口手动查词")
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
                            Text(rule.urlRule)
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
        .navigationTitle("词典规则")
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
            DictRuleEditView(rule: nil)
        }
        .sheet(item: $editingRule, onDismiss: { Task { await reload() } }) { rule in
            DictRuleEditView(rule: rule)
        }
        .task { await reload() }
    }

    private func reload() async {
        rules = (try? await env.dictRuleStore.all()) ?? []
    }

    private func toggleEnabled(_ rule: DictRule, enabled: Bool) {
        Task {
            try? await env.dictRuleStore.setEnabled(id: rule.id, enabled: enabled)
            await reload()
        }
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { rules[$0] }
        Task {
            for rule in toDelete {
                try? await env.dictRuleStore.remove(id: rule.id)
            }
            await reload()
        }
    }
}

struct DictRuleEditView: View {
    let rule: DictRule?

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var urlRule: String
    @State private var showRule: String
    @State private var enabled: Bool

    init(rule: DictRule?) {
        self.rule = rule
        _name = State(initialValue: rule?.name ?? "")
        _urlRule = State(initialValue: rule?.urlRule ?? "")
        _showRule = State(initialValue: rule?.showRule ?? "")
        _enabled = State(initialValue: rule?.enabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("规则") {
                    TextField("名称", text: $name)
                    TextField("查询地址（{{key}} 代表查询词）", text: $urlRule)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("释义提取规则", text: $showRule)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Toggle("启用", isOn: $enabled)
                } footer: {
                    Text("提取规则跟书源规则是同一套语法，比如 @css:.definition@text")
                }
            }
            .navigationTitle(rule == nil ? "新建词典规则" : "编辑词典规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let saved = DictRule(
                            id: rule?.id ?? UUID().uuidString, name: name.isEmpty ? urlRule : name,
                            urlRule: urlRule, showRule: showRule, enabled: enabled
                        )
                        Task {
                            try? await env.dictRuleStore.add(saved)
                            dismiss()
                        }
                    }
                    .disabled(urlRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || showRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
