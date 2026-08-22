import SwiftUI
import BookSourceModel
import Persistence

struct ReplaceRuleListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var rules: [ReplaceRule] = []
    @State private var editingRule: ReplaceRule?
    @State private var isShowingNewRuleSheet = false
    @State private var registeredGroupNames: [String] = []
    /// `nil` means "全部" (no filter). Same real-usage-feedback reasoning as `SourceLibraryView`'s
    /// matching filter: without this, a large rule collection had no way to organize at all.
    @State private var groupFilter: String?

    private var existingGroupNames: [String] {
        var names = Set(rules.compactMap {
            let trimmed = $0.group?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed?.isEmpty ?? true) ? nil : trimmed
        })
        names.formUnion(registeredGroupNames)
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Sorted by `order` -- the same sequence `ReplaceRuleApplier` actually runs rules in, so this
    /// list reads as "the order that matters," not just whatever order they happen to be stored in.
    private var displayedRules: [ReplaceRule] {
        let base = groupFilter.map { filter in rules.filter { $0.group == filter } } ?? rules
        return base.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            if rules.isEmpty {
                ContentUnavailableView(
                    "还没有净化规则", systemImage: "wand.and.stars",
                    description: Text("点右上角 + 新建一条规则，比如去除正文里的广告文字")
                )
            } else if displayedRules.isEmpty {
                ContentUnavailableView(
                    "这个分组下没有规则", systemImage: "folder",
                    description: Text("在右上角菜单的“筛选分组”选“全部”可以清除筛选")
                )
            }
            ForEach(displayedRules) { rule in
                Button {
                    editingRule = rule
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(rule.name)
                                    .font(.headline)
                                    .foregroundStyle(rule.enabled ? .primary : .secondary)
                                if let group = rule.group, !group.isEmpty {
                                    Text(group)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.12), in: Capsule())
                                        .foregroundStyle(.secondary)
                                }
                            }
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
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    NavigationLink {
                        ReplaceRuleGroupManagementView()
                    } label: {
                        Text("分组管理")
                    }
                    if !existingGroupNames.isEmpty {
                        Menu("筛选分组\(groupFilter.map { "（\($0)）" } ?? "")") {
                            Button {
                                groupFilter = nil
                            } label: {
                                if groupFilter == nil {
                                    Label("全部", systemImage: "checkmark")
                                } else {
                                    Text("全部")
                                }
                            }
                            ForEach(existingGroupNames, id: \.self) { name in
                                Button {
                                    groupFilter = name
                                } label: {
                                    if groupFilter == name {
                                        Label(name, systemImage: "checkmark")
                                    } else {
                                        Text(name)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isShowingNewRuleSheet) {
            ReplaceRuleEditView(rule: nil, existingGroups: existingGroupNames) { newRule in
                Task {
                    try? await env.replaceRuleStore.add(newRule)
                    await reload()
                }
            }
        }
        .sheet(item: $editingRule) { rule in
            ReplaceRuleEditView(rule: rule, existingGroups: existingGroupNames) { updatedRule in
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
        registeredGroupNames = (try? await env.replaceRuleGroupStore.all()) ?? []
    }

    private func toggleEnabled(_ rule: ReplaceRule, enabled: Bool) {
        Task {
            try? await env.replaceRuleStore.setEnabled(id: rule.id, enabled: enabled)
            await reload()
        }
    }

    private func delete(at offsets: IndexSet) {
        // See `SourceLibraryView.delete`'s matching doc comment -- `offsets` are indices into
        // `displayedRules` (whatever `ForEach` is actually iterating, possibly group-filtered), not
        // the full unfiltered `rules` array.
        let toDelete = offsets.map { displayedRules[$0] }
        Task {
            for rule in toDelete {
                try? await env.replaceRuleStore.remove(id: rule.id)
            }
            await reload()
        }
    }
}

/// Matches Legado's real "新增规则" form (confirmed against a real-device reference screenshot):
/// name/group, the match pattern with a regex toggle, replacement, which text kinds it applies to
/// (标题/内容), and the scope/exclude-scope substring fields -- not just name+pattern+replacement
/// the way this form used to be. `existingGroups` powers a plain text field with autocomplete-by-
/// example rather than a strict picker, since typing a *new* group name here is just as valid as
/// picking an existing one (group management itself lives in `ReplaceRuleGroupManagementView`).
struct ReplaceRuleEditView: View {
    let rule: ReplaceRule?
    var existingGroups: [String] = []
    let onSave: (ReplaceRule) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var group: String
    @State private var pattern: String
    @State private var replacement: String
    @State private var isRegex: Bool
    @State private var scope: String
    @State private var excludeScope: String
    @State private var scopeTitle: Bool
    @State private var scopeContent: Bool
    @State private var enabled: Bool

    init(rule: ReplaceRule?, existingGroups: [String] = [], onSave: @escaping (ReplaceRule) -> Void) {
        self.rule = rule
        self.existingGroups = existingGroups
        self.onSave = onSave
        _name = State(initialValue: rule?.name ?? "")
        _group = State(initialValue: rule?.group ?? "")
        _pattern = State(initialValue: rule?.pattern ?? "")
        _replacement = State(initialValue: rule?.replacement ?? "")
        _isRegex = State(initialValue: rule?.isRegex ?? true)
        _scope = State(initialValue: rule?.scope ?? "")
        _excludeScope = State(initialValue: rule?.excludeScope ?? "")
        _scopeTitle = State(initialValue: rule?.scopeTitle ?? false)
        _scopeContent = State(initialValue: rule?.scopeContent ?? true)
        _enabled = State(initialValue: rule?.enabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("规则") {
                    TextField("名称", text: $name)
                    if !existingGroups.isEmpty {
                        Picker("分组", selection: $group) {
                            Text("无分组").tag("")
                            ForEach(existingGroups, id: \.self) { Text($0).tag($0) }
                        }
                    } else {
                        TextField("分组（可留空）", text: $group)
                    }
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
                    NavigationLink {
                        RegexTesterView(initialPattern: pattern)
                    } label: {
                        Label("正则测试", systemImage: "testtube.2")
                    }
                } footer: {
                    Text("正则表达式不支持前瞻/后顾等高级语法(?ixsmd)")
                }
                Section {
                    Toggle("作用于标题", isOn: $scopeTitle)
                    Toggle("作用于内容", isOn: $scopeContent)
                } footer: {
                    Text("目前只有\u{201C}作用于内容\u{201D}真正生效——净化章节标题是一个更大的改动（目录、书签、阅读进度里显示的标题都要跟着变），这次还没有做。")
                }
                Section {
                    TextField("适用范围（书名或书源网址，留空则全部适用）", text: $scope)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("排除范围（留空则不排除）", text: $excludeScope)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("适用范围")
                } footer: {
                    Text("填书名或书源网址的一部分即可，比如\u{201C}斗破苍穹\u{201D}或\u{201C}example.com\u{201D}，多个用逗号隔开。")
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
                        let trimmedGroup = group.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedScope = scope.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedExcludeScope = excludeScope.trimmingCharacters(in: .whitespacesAndNewlines)
                        let saved = ReplaceRule(
                            id: rule?.id ?? UUID().uuidString, name: name.isEmpty ? pattern : name,
                            group: trimmedGroup.isEmpty ? nil : trimmedGroup,
                            pattern: pattern, replacement: replacement, isRegex: isRegex,
                            scope: trimmedScope.isEmpty ? nil : trimmedScope,
                            excludeScope: trimmedExcludeScope.isEmpty ? nil : trimmedExcludeScope,
                            scopeTitle: scopeTitle, scopeContent: scopeContent,
                            order: rule?.order ?? 0, enabled: enabled
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
