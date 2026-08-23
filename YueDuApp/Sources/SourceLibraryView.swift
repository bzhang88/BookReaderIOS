import SwiftUI
import UniformTypeIdentifiers
import BookSourceModel
import RuleEngine
import Persistence
import NetworkClient

struct SourceLibraryView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var sources: [BookSource] = []
    @State private var capabilityReports: [String: SourceCapabilityReport] = [:]
    @State private var isImporterPresented = false
    @State private var isShowingURLImport = false
    @State private var isShowingTrash = false
    @State private var isShowingSubscriptions = false
    @State private var importSummary: String?
    @State private var errorMessage: String?
    @State private var editingSource: BookSource?
    @State private var isCreatingSource = false
    @State private var debuggingSource: BookSource?
    @State private var loggingInSource: BookSource?
    @State private var verifyingSource: BookSource?
    @State private var loggedInSourceUrls: Set<String> = []
    @State private var groupPickerTarget: BookSource?
    @State private var registeredGroupNames: [String] = []
    /// `nil` means "全部" (no filter). Real usage feedback (from a Legado-comparison pass): with
    /// `bookSourceGroup` modeled but nothing in the UI to assign/filter by it, a user with a large
    /// source collection (real-world Legado collections routinely run 50-200+ sources) had no way
    /// to organize the list at all.
    @State private var groupFilter: String?
    /// Real gap found comparing against Legado: with the same large-collection reality as
    /// `groupFilter` above, there was no way to jump straight to a known source by name/url either --
    /// every search meant scrolling and eyeballing.
    @State private var searchKeyword = ""
    @State private var sortOption: SourceSortOption = .manual
    @State private var sortAscending = true

    /// Merges group names still in live use across `sources` with ones registered in
    /// `bookSourceGroupStore` but not currently assigned to any source -- same reasoning as
    /// `ShelfView.existingGroupNames`: otherwise a group created ahead of time via
    /// `SourceGroupManagementView` would never show up here as a pickable/filterable option.
    private var existingGroupNames: [String] {
        var names = Set(sources.compactMap {
            let trimmed = $0.bookSourceGroup?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed?.isEmpty ?? true) ? nil : trimmed
        })
        names.formUnion(registeredGroupNames)
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var displayedSources: [BookSource] {
        var result = sources
        if let groupFilter { result = result.filter { $0.bookSourceGroup == groupFilter } }
        let trimmedKeyword = searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeyword.isEmpty {
            result = result.filter {
                $0.bookSourceName.localizedCaseInsensitiveContains(trimmedKeyword)
                    || $0.bookSourceUrl.localizedCaseInsensitiveContains(trimmedKeyword)
            }
        }
        result = sortedAscending(result, by: sortOption)
        return sortAscending ? result : result.reversed()
    }

    /// Always returns the "natural ascending" order for `option` -- `displayedSources` is the only
    /// caller, and applies `sortAscending`'s direction uniformly afterward (a plain `.reversed()`),
    /// matching Legado's own `BookSourceActivity` architecture: `isSortAscending` is one independent
    /// toggle applied on top of whichever sort criterion is picked, not baked into each criterion
    /// separately. `.manual` mirrors Legado's `BookSourceSort.Default` (the store's own persisted
    /// order, i.e. `customOrder`); `.respondTime` treats a never-checked source (`respondTime == nil`)
    /// as the slowest rather than sorting it to an arbitrary end regardless of direction.
    private func sortedAscending(_ items: [BookSource], by option: SourceSortOption) -> [BookSource] {
        switch option {
        case .manual:
            return items
        case .name:
            return items.sorted { $0.bookSourceName.localizedStandardCompare($1.bookSourceName) == .orderedAscending }
        case .url:
            return items.sorted { $0.bookSourceUrl.localizedStandardCompare($1.bookSourceUrl) == .orderedAscending }
        case .updateTime:
            return items.sorted { ($0.lastUpdateTime ?? 0) < ($1.lastUpdateTime ?? 0) }
        case .respondTime:
            return items.sorted { ($0.respondTime ?? Int.max) < ($1.respondTime ?? Int.max) }
        case .enabled:
            return items.sorted { !$0.enabled && $1.enabled }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if sources.isEmpty {
                    ContentUnavailableView(
                        "还没有书源", systemImage: "tray",
                        description: Text("点右上角 + 导入一个书源 JSON 文件")
                    )
                } else if displayedSources.isEmpty {
                    // A group filter is active and matched nothing -- distinct from "没有书源"
                    // above, and from the plain empty list a silent zero-match would otherwise be.
                    ContentUnavailableView(
                        "这个分组下没有书源", systemImage: "folder",
                        description: Text("在“…”菜单里的“筛选分组”选“全部”可以清除筛选")
                    )
                } else {
                    Text("点一个书源可以启用/停用它——只有启用的书源才会参与搜索")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(displayedSources) { source in
                    sourceRow(source)
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("书源库")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("导入", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        SourceCheckView(sources: sources)
                    } label: {
                        Label("检测书源", systemImage: "checkmark.shield")
                    }
                    .disabled(sources.isEmpty)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        overflowMenuContent
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .searchable(text: $searchKeyword, prompt: "搜索书源名称或网址")
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.json]) { result in
                Task { await handleImport(result) }
            }
            .sheet(item: $editingSource, onDismiss: { Task { await reload() } }) { source in
                BookSourceEditView(source: source)
            }
            .sheet(item: $groupPickerTarget) { source in
                BookSourceGroupPickerView(existingGroups: existingGroupNames) { newGroup in
                    await setGroup(of: source, to: newGroup)
                }
            }
            .sheet(isPresented: $isCreatingSource, onDismiss: { Task { await reload() } }) {
                BookSourceEditView(source: nil)
            }
            .sheet(isPresented: $isShowingURLImport) {
                BookSourceURLImportView { urlString in
                    await handleURLImport(urlString)
                }
            }
            .sheet(isPresented: $isShowingTrash, onDismiss: { Task { await reload() } }) {
                NavigationStack {
                    SourceTrashView()
                }
            }
            .sheet(isPresented: $isShowingSubscriptions, onDismiss: { Task { await reload() } }) {
                NavigationStack {
                    SourceSubscriptionListView()
                }
            }
            .sheet(item: $loggingInSource, onDismiss: { Task { await reload() } }) { source in
                SourceLoginView(source: source)
            }
            .sheet(item: $verifyingSource, onDismiss: { Task { await reload() } }) { source in
                SourceLoginView(source: source, mode: .verify)
            }
            .navigationDestination(isPresented: Binding(
                get: { debuggingSource != nil },
                set: { if !$0 { debuggingSource = nil } }
            )) {
                if let debuggingSource {
                    SourceDebugView(source: debuggingSource)
                }
            }
            .alert("导入完成", isPresented: .constant(importSummary != nil)) {
                Button("好") { importSummary = nil }
            } message: {
                Text(importSummary ?? "")
            }
            .alert("导入失败", isPresented: .constant(errorMessage != nil)) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    // Broken out of `body`'s `ForEach` into its own `@ViewBuilder` -- same
    // "compiler unable to type-check this expression in reasonable time" CI failure class this
    // session has now hit three times today, this time in the row itself (several conditional
    // badges nested inside the Button/HStack/VStack the search/sort work added alongside) rather
    // than a toolbar Menu. `sourceRowLabel` is split out further for the same reason.
    @ViewBuilder
    private func sourceRow(_ source: BookSource) -> some View {
        Button {
            toggleEnabled(source)
        } label: {
            sourceRowLabel(source)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            Button {
                editingSource = source
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(.blue)
            Button {
                groupPickerTarget = source
            } label: {
                Label("分组", systemImage: "folder")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button {
                editingSource = source
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button {
                groupPickerTarget = source
            } label: {
                Label("设置分组", systemImage: "folder")
            }
            Button {
                debuggingSource = source
            } label: {
                Label("调试", systemImage: "ladybug")
            }
            if let loginUrl = source.loginUrl, !loginUrl.isEmpty {
                Button {
                    loggingInSource = source
                } label: {
                    Label(
                        loggedInSourceUrls.contains(source.bookSourceUrl) ? "已登录（重新登录）" : "登录",
                        systemImage: "person.crop.circle"
                    )
                }
            }
            Button {
                verifyingSource = source
            } label: {
                Label("手动验证（过验证码等）", systemImage: "checkmark.shield")
            }
            NavigationLink {
                SourceVariableAndCookieView(source: source)
            } label: {
                Label("变量与 Cookie", systemImage: "key")
            }
        }
    }

    @ViewBuilder
    private func sourceRowLabel(_ source: BookSource) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(source.bookSourceName)
                        .font(.headline)
                        .foregroundStyle(source.enabled ? .primary : .secondary)
                    if let report = capabilityReports[source.bookSourceUrl], !report.isFullyCompatible {
                        Text("\(report.issues.count) 项不支持")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    if loggedInSourceUrls.contains(source.bookSourceUrl) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.caption2)
                            .foregroundStyle(Color.green)
                    }
                }
                Text(source.bookSourceUrl)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                // Written by `SourceCheckView`'s own check results (respondTime for speed, a
                // failure annotation here) -- matches Legado's real source list, which keeps a
                // failing/slow source visibly flagged without needing to re-run a check to
                // remember why.
                if let comment = source.bookSourceComment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
                if let respondTime = source.respondTime {
                    Text("响应 \(respondTime) 毫秒")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: source.enabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(source.enabled ? .green : .secondary)
        }
    }

    // Broken out of the toolbar's `Menu` closure into its own `@ViewBuilder` -- the same
    // "compiler unable to type-check this expression in reasonable time" CI failure class this
    // session already hit twice today (`HighlightRuleListView`/its own doc comment,
    // `AudiobookPlayerView.toolbarContent`) for a `Menu` that grew past a handful of flat buttons
    // once a second conditional sub-`Menu` (`sortMenu`, alongside the pre-existing `groupFilterMenu`)
    // was added -- proactively split this time instead of waiting for CI to catch it.
    @ViewBuilder
    private var overflowMenuContent: some View {
        Button("新建书源") { isCreatingSource = true }
        Button("从网址导入") { isShowingURLImport = true }
        Button("订阅列表") { isShowingSubscriptions = true }
        Button("回收站") { isShowingTrash = true }
        Button("全部启用") { setAllEnabled(true) }.disabled(sources.isEmpty)
        Button("全部停用") { setAllEnabled(false) }.disabled(sources.isEmpty)
        NavigationLink {
            SourceGroupManagementView()
        } label: {
            Text("分组管理")
        }
        if !existingGroupNames.isEmpty {
            groupFilterMenu
        }
        sortMenu
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

    @ViewBuilder
    private var sortMenu: some View {
        Menu("排序: \(sortOption.displayName)") {
            Button {
                sortAscending.toggle()
            } label: {
                Label(sortAscending ? "升序" : "降序", systemImage: sortAscending ? "arrow.up" : "arrow.down")
            }
            ForEach(SourceSortOption.allCases) { option in
                Button {
                    sortOption = option
                } label: {
                    if sortOption == option {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }
        }
    }

    private func reload() async {
        let all = (try? await env.bookSourceStore.all()) ?? []
        sources = all
        capabilityReports = Dictionary(
            uniqueKeysWithValues: CapabilityScanner.scan(all).map { ($0.sourceUrl, $0) }
        )
        let savedCookies = (try? await env.loginCookieStore.allCookies()) ?? [:]
        loggedInSourceUrls = Set(savedCookies.keys)
        registeredGroupNames = (try? await env.bookSourceGroupStore.all()) ?? []
    }

    private func setGroup(of source: BookSource, to newGroup: String?) async {
        try? await env.bookSourceStore.setGroups([source.bookSourceUrl: newGroup])
        await reload()
    }

    private func toggleEnabled(_ source: BookSource) {
        Task {
            try? await env.bookSourceStore.setEnabled(bookSourceUrl: source.bookSourceUrl, enabled: !source.enabled)
            await reload()
        }
    }

    private func setAllEnabled(_ enabled: Bool) {
        Task {
            try? await env.bookSourceStore.setAllEnabled(enabled)
            await reload()
        }
    }

    /// Moves deleted sources to `bookSourceTrashStore` rather than removing them outright -- see
    /// `SourceTrashView`'s doc comment for why (fat-finger recovery in a long, similar-looking list).
    private func delete(at offsets: IndexSet) {
        // `offsets` are indices into whatever `ForEach` is actually iterating -- `displayedSources`
        // (possibly filtered by `groupFilter`), not the full unfiltered `sources` array. Indexing
        // into `sources` here instead would delete the wrong row whenever a group filter is active.
        let toDelete = offsets.map { displayedSources[$0] }
        Task {
            for source in toDelete {
                try? await env.bookSourceTrashStore.add(source)
                try? await env.bookSourceStore.remove(bookSourceUrl: source.bookSourceUrl)
            }
            await reload()
        }
    }

    private func handleImport(_ result: Result<URL, Error>) async {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let imported = try BookSourceImportDecoder.decode(from: data)
            let (inserted, updated) = try await env.bookSourceStore.importSources(imported)
            await reload()
            importSummary = "新增 \(inserted) 个，更新 \(updated) 个"
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Same import pipeline as `handleImport`, just sourcing the bytes from a URL instead of a
    /// local file -- reuses `BookSourceImportDecoder` so a malformed or unreachable URL surfaces the
    /// same kind of specific error rather than a separate, possibly worse-worded one.
    /// Returns whether the import actually succeeded -- `BookSourceURLImportView` only dismisses
    /// itself on `true`, so a failure's `errorMessage` stays visible with the input still on screen
    /// instead of surfacing behind an already-closed sheet.
    private func handleURLImport(_ urlString: String) async -> Bool {
        guard !urlString.isEmpty else { return false }
        do {
            let response = try await env.httpClient.fetch(HTTPRequest(url: urlString))
            guard let data = response.body.data(using: .utf8) else {
                errorMessage = "下载内容无法解析为文本"
                return false
            }
            let imported = try BookSourceImportDecoder.decode(from: data)
            let (inserted, updated) = try await env.bookSourceStore.importSources(imported)
            await reload()
            importSummary = "新增 \(inserted) 个，更新 \(updated) 个"
            return true
        } catch {
            errorMessage = "\(error)"
            return false
        }
    }
}

#Preview {
    SourceLibraryView()
        .environmentObject(AppEnvironment())
}

/// Single-select group picker for `BookSource.bookSourceGroup` (still a single optional `String`,
/// unlike `ShelfBook.groups` -- Legado's own book-source grouping was never a multi-membership
/// bitmask the way its shelf `Book.group` is, so this deliberately doesn't reuse the now-multi-select
/// `ShelfGroupPickerView`). Same plain single-select-button-list shape that view used before it
/// became a checklist.
private struct BookSourceGroupPickerView: View {
    let existingGroups: [String]
    let onSelect: (String?) async -> Void

    @State private var newGroupName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("无分组") {
                        select(nil)
                    }
                }
                if !existingGroups.isEmpty {
                    Section("已有分组") {
                        ForEach(existingGroups, id: \.self) { group in
                            Button(group) {
                                select(group)
                            }
                        }
                    }
                }
                Section("新建分组") {
                    TextField("分组名称", text: $newGroupName)
                    Button("创建并使用") {
                        select(newGroupName)
                    }
                    .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("设置分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func select(_ group: String?) {
        let trimmed = group?.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await onSelect(trimmed?.isEmpty == true ? nil : trimmed)
            dismiss()
        }
    }
}

/// Mirrors Legado's own `BookSourceSort` options (`BookSourceActivity`'s sort submenu) minus
/// `Weight`/"自动排序" -- that one sorts by `BookSource.weight`, a field this app decodes but never
/// computes or writes anywhere (Legado derives it from real usage/search-success heuristics this
/// port doesn't implement), so including it here would just be a no-op sort by a field that's always
/// `0`.
enum SourceSortOption: String, CaseIterable, Identifiable {
    case manual, name, url, updateTime, respondTime, enabled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: return "手动排序"
        case .name: return "名称"
        case .url: return "网址"
        case .updateTime: return "更新时间"
        case .respondTime: return "响应时间"
        case .enabled: return "启用状态"
        }
    }
}
