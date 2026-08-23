import SwiftUI
import BookSourceModel
import Persistence

struct HighlightRuleListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var rules: [HighlightRule] = []
    @State private var editingRule: HighlightRule?
    @State private var isShowingNewRuleSheet = false
    @State private var registeredGroupNames: [String] = []
    /// `nil` means "全部" (no filter) -- same convention as `ReplaceRuleListView.groupFilter`.
    @State private var groupFilter: String?

    private var existingGroupNames: [String] {
        var names = Set(rules.compactMap {
            let trimmed = $0.group?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed?.isEmpty ?? true) ? nil : trimmed
        })
        names.formUnion(registeredGroupNames)
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var displayedRules: [HighlightRule] {
        groupFilter.map { filter in rules.filter { $0.group == filter } } ?? rules
    }

    var body: some View {
        List {
            if rules.isEmpty {
                ContentUnavailableView(
                    "还没有高亮规则", systemImage: "highlighter",
                    description: Text("点右上角 + 新建一条规则，比如高亮某个角色名")
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
                    ruleRow(rule)
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("高亮规则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $isShowingNewRuleSheet, onDismiss: { Task { await reload() } }) {
            HighlightRuleEditView(rule: nil, existingGroups: existingGroupNames)
        }
        .sheet(item: $editingRule, onDismiss: { Task { await reload() } }) { rule in
            HighlightRuleEditView(rule: rule, existingGroups: existingGroupNames)
        }
        .task { await reload() }
    }

    /// Extracted out of `body` -- the badge row (name + optional group/scope capsules + pattern)
    /// pushed the enclosing `List`/`ForEach`/`Button` expression past the real `xcodebuild` (Release,
    /// whole-module optimization) type-checker's time budget ("unable to type-check this expression
    /// in reasonable time"), the same failure class `ReaderView.body`'s own doc comment already
    /// documents and works around by splitting into independently-inferred pieces. Windows
    /// `swift build` never catches this since it only ever compiles the cross-platform package.
    @ViewBuilder
    private func ruleRow(_ rule: HighlightRule) -> some View {
        HStack {
            Circle()
                .fill(Color(hex: rule.colorHex ?? "") ?? .orange)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                ruleBadges(rule)
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

    @ViewBuilder
    private func ruleBadges(_ rule: HighlightRule) -> some View {
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
            if rule.resolvedTargetScope != .all {
                Text(rule.resolvedTargetScope == .title ? "仅标题" : "仅正文")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
                    HighlightRuleGroupManagementView()
                } label: {
                    Text("分组管理")
                }
                if !existingGroupNames.isEmpty {
                    groupFilterMenu
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private var groupFilterMenu: some View {
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

    private func reload() async {
        rules = (try? await env.highlightRuleStore.all()) ?? []
        registeredGroupNames = (try? await env.highlightRuleGroupStore.all()) ?? []
    }

    private func toggleEnabled(_ rule: HighlightRule, enabled: Bool) {
        Task {
            try? await env.highlightRuleStore.setEnabled(id: rule.id, enabled: enabled)
            await reload()
        }
    }

    private func delete(at offsets: IndexSet) {
        // `offsets` are indices into `displayedRules` (whatever `ForEach` is actually iterating,
        // possibly group-filtered), not the full unfiltered `rules` array -- same bug shape fixed
        // elsewhere in this app (see `ReplaceRuleListView.delete`'s matching doc comment).
        let toDelete = offsets.map { displayedRules[$0] }
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
    var existingGroups: [String] = []

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var group: String
    @State private var pattern: String
    @State private var enabled: Bool
    @State private var color: Color
    @State private var isBold: Bool
    @State private var isUnderlined: Bool
    @State private var targetScope: HighlightTargetScope

    init(rule: HighlightRule?, existingGroups: [String] = []) {
        self.rule = rule
        self.existingGroups = existingGroups
        _name = State(initialValue: rule?.name ?? "")
        _group = State(initialValue: rule?.group ?? "")
        _pattern = State(initialValue: rule?.pattern ?? "")
        _enabled = State(initialValue: rule?.enabled ?? true)
        _color = State(initialValue: rule?.colorHex.flatMap { Color(hex: $0) } ?? .orange)
        _isBold = State(initialValue: rule?.resolvedIsBold ?? true)
        _isUnderlined = State(initialValue: rule?.resolvedIsUnderlined ?? false)
        _targetScope = State(initialValue: rule?.resolvedTargetScope ?? .all)
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
                    TextField("匹配内容（正则表达式）", text: $pattern)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Toggle("启用", isOn: $enabled)
                    Picker("作用范围", selection: $targetScope) {
                        Text("全部").tag(HighlightTargetScope.all)
                        Text("仅标题").tag(HighlightTargetScope.title)
                        Text("仅正文").tag(HighlightTargetScope.body)
                    }
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
                        let trimmedGroup = group.trimmingCharacters(in: .whitespacesAndNewlines)
                        let saved = HighlightRule(
                            id: rule?.id ?? UUID().uuidString, name: name.isEmpty ? pattern : name,
                            pattern: pattern, enabled: enabled, colorHex: color.toHex(),
                            isBold: isBold, isUnderlined: isUnderlined,
                            group: trimmedGroup.isEmpty ? nil : trimmedGroup, targetScope: targetScope
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
