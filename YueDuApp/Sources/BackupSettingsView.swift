import SwiftUI
import UniformTypeIdentifiers
import BookSourceModel
import Persistence
import NetworkClient

/// Full backup/restore of selected data categories to/from a WebDAV server. Deliberately not a
/// continuous background sync -- explicit "备份"/"恢复" buttons the user triggers, which is easier
/// to reason about and test than trying to get automatic conflict resolution right in a first
/// version. Which categories get included is user-selectable (see `BackupCategory`) rather than
/// always being "everything" -- some data is large (local books' full text) and some just isn't
/// everyone's concern to sync (RSS subscriptions, AI provider list).
///
/// Restoring downloads everything for the selected categories first, computes what it would
/// change (`RestorePreviewCalculator`, per-category new/update/skip counts against what's already
/// on this device) and shows that as a confirmation sheet -- nothing is written until the user
/// taps "确认恢复". Previously "从云端恢复" applied every category immediately with no way to see
/// what was about to be overwritten.
struct BackupSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @AppStorage("webdav.baseURL") private var baseURL: String = ""
    @AppStorage("webdav.username") private var username: String = ""
    @AppStorage("backup.enabledCategories") private var enabledCategoriesRaw: String = BackupCategory.allCases
        .filter(\.defaultEnabled).map(\.rawValue).joined(separator: ",")
    @State private var password: String = KeychainStore.get("webdav.password") ?? ""
    @State private var statusMessage: String?
    @State private var isWorking = false
    @State private var pendingRestore: RestorePlan?
    // Real usage feedback (from a Legado-comparison pass): this screen only ever backed up to
    // WebDAV -- someone with no WebDAV account/server had no backup option at all. A single combined
    // JSON file (not a `.zip` the way Legado's local backup is -- there's no binary/asset data here,
    // every category is already plain JSON) reuses `ShareSheet`/`.fileImporter`, both already used
    // elsewhere in this app, and feeds into the exact same `RestorePreviewCalculator`/confirmation-
    // sheet flow the WebDAV path already has -- only *where the bytes come from* differs.
    @State private var isShowingLocalExportSheet = false
    @State private var localExportURL: URL?
    @State private var isShowingLocalImporter = false

    private var enabledCategories: Set<BackupCategory> {
        Set(enabledCategoriesRaw.split(separator: ",").compactMap { BackupCategory(rawValue: String($0)) })
    }

    var body: some View {
        Form {
            Section("WebDAV 服务器") {
                TextField("服务器地址", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("用户名", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("密码", text: $password)
                    .onChange(of: password) { _, newValue in
                        KeychainStore.set(newValue, forKey: "webdav.password")
                    }
            }

            Section("备份内容") {
                ForEach(BackupCategory.allCases) { category in
                    Toggle(category.displayName, isOn: Binding(
                        get: { enabledCategories.contains(category) },
                        set: { setCategory(category, enabled: $0) }
                    ))
                }
            }

            Section {
                Button("立即备份") { Task { await backup() } }
                    .disabled(isWorking || baseURL.isEmpty || enabledCategories.isEmpty)
                Button("从云端恢复") { Task { await downloadAndPreviewRestore() } }
                    .disabled(isWorking || baseURL.isEmpty || enabledCategories.isEmpty)
            } footer: {
                Text("恢复前会先显示每一类将新增/更新/跳过多少项，确认后才会真正写入。")
            }

            Section {
                Button("导出到文件") { Task { await exportToLocalFile() } }
                    .disabled(isWorking || enabledCategories.isEmpty)
                Button("从文件恢复") { isShowingLocalImporter = true }
                    .disabled(isWorking || enabledCategories.isEmpty)
            } header: {
                Text("本地文件备份")
            } footer: {
                Text("不需要 WebDAV 账号：导出成一个 JSON 文件，可以存到\u{201C}文件\u{201D} App、发送给自己，或者用其他方式转移到新设备上再导入。同样先预览再确认写入。")
            }

            if isWorking {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("备份与同步")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pendingRestore) { plan in
            NavigationStack {
                RestorePreviewSheet(
                    plan: plan,
                    onConfirm: {
                        pendingRestore = nil
                        Task { await applyRestore(plan) }
                    },
                    onCancel: { pendingRestore = nil }
                )
            }
        }
        .sheet(isPresented: $isShowingLocalExportSheet) {
            if let localExportURL {
                ShareSheet(items: [localExportURL])
            }
        }
        .fileImporter(isPresented: $isShowingLocalImporter, allowedContentTypes: [.json]) { result in
            Task { await importFromLocalFile(result) }
        }
    }

    private func setCategory(_ category: BackupCategory, enabled: Bool) {
        var set = enabledCategories
        if enabled { set.insert(category) } else { set.remove(category) }
        enabledCategoriesRaw = set.map(\.rawValue).joined(separator: ",")
    }

    private func makeClient() -> WebDAVClient {
        WebDAVClient(
            httpClient: env.httpClient,
            config: WebDAVConfig(baseURL: baseURL, username: username, password: password)
        )
    }

    private func jsonString<T: Encodable>(_ value: T, _ encoder: JSONEncoder) throws -> String {
        String(data: try encoder.encode(value), encoding: .utf8) ?? "[]"
    }

    private func backup() async {
        isWorking = true
        statusMessage = nil
        var summary: [String] = []
        do {
            let client = makeClient()
            try await client.makeDirectoryIfNeeded(path: "")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let categories = enabledCategories

            if categories.contains(.bookSources) {
                let items = try await env.bookSourceStore.all()
                try await client.upload(path: BackupCategory.bookSources.fileName, content: try jsonString(items, encoder))
                summary.append("书源 \(items.count)")
            }
            if categories.contains(.shelf) {
                let items = try await env.shelfStore.all()
                try await client.upload(path: BackupCategory.shelf.fileName, content: try jsonString(items, encoder))
                summary.append("书架 \(items.count)")
            }
            if categories.contains(.replaceRules) {
                let items = try await env.replaceRuleStore.all()
                try await client.upload(path: BackupCategory.replaceRules.fileName, content: try jsonString(items, encoder))
                summary.append("净化规则 \(items.count)")
            }
            if categories.contains(.highlightRules) {
                let items = try await env.highlightRuleStore.all()
                try await client.upload(path: BackupCategory.highlightRules.fileName, content: try jsonString(items, encoder))
                summary.append("高亮规则 \(items.count)")
            }
            if categories.contains(.tagGroupRules) {
                let items = try await env.tagGroupRuleStore.all()
                try await client.upload(path: BackupCategory.tagGroupRules.fileName, content: try jsonString(items, encoder))
                summary.append("分组规则 \(items.count)")
            }
            if categories.contains(.txtSplitRules) {
                let items = try await env.txtSplitRuleStore.all()
                try await client.upload(path: BackupCategory.txtSplitRules.fileName, content: try jsonString(items, encoder))
                summary.append("TXT 分章规则 \(items.count)")
            }
            if categories.contains(.rssSources) {
                let items = try await env.rssSourceStore.all()
                try await client.upload(path: BackupCategory.rssSources.fileName, content: try jsonString(items, encoder))
                summary.append("RSS 订阅源 \(items.count)")
            }
            if categories.contains(.bookmarks) {
                let items = try await env.bookmarkStore.all()
                try await client.upload(path: BackupCategory.bookmarks.fileName, content: try jsonString(items, encoder))
                summary.append("书签 \(items.count)")
            }
            if categories.contains(.localBooks) {
                let items = try await env.localBookStore.all()
                try await client.upload(path: BackupCategory.localBooks.fileName, content: try jsonString(items, encoder))
                summary.append("本地书籍 \(items.count)")
            }
            if categories.contains(.aiProviders) {
                let items = try await env.aiProviderStore.all()
                try await client.upload(path: BackupCategory.aiProviders.fileName, content: try jsonString(items, encoder))
                summary.append("AI 服务商 \(items.count)")
            }

            statusMessage = "备份完成：" + summary.joined(separator: "，")
        } catch {
            statusMessage = "备份失败: \(error)"
        }
        isWorking = false
    }

    /// Downloads and decodes every selected category (without writing anything yet), diffs each
    /// against what's already on this device, and hands the result to a confirmation sheet.
    private func downloadAndPreviewRestore() async {
        isWorking = true
        statusMessage = nil
        do {
            let client = makeClient()
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let categories = enabledCategories
            var plan = RestorePlan()
            var previews: [RestoreCategoryPreview] = []

            if categories.contains(.bookSources) {
                let items = try decoder.decode(
                    [BookSource].self, from: Data(try await client.download(path: BackupCategory.bookSources.fileName).utf8)
                )
                plan.bookSources = items
                let localIds = Set(try await env.bookSourceStore.all().map(\.bookSourceUrl))
                previews.append(RestoreCategoryPreview(
                    category: .bookSources, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.bookSourceUrl), localIds: localIds, style: .upsert)
                ))
            }
            if categories.contains(.shelf) {
                let items = try decoder.decode(
                    [ShelfBook].self, from: Data(try await client.download(path: BackupCategory.shelf.fileName).utf8)
                )
                plan.shelf = items
                let localIds = Set(try await env.shelfStore.all().map(\.bookUrl))
                previews.append(RestoreCategoryPreview(
                    category: .shelf, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.bookUrl), localIds: localIds, style: .upsert)
                ))
            }
            if categories.contains(.replaceRules) {
                let items = try decoder.decode(
                    [ReplaceRule].self, from: Data(try await client.download(path: BackupCategory.replaceRules.fileName).utf8)
                )
                plan.replaceRules = items
                let localIds = Set(try await env.replaceRuleStore.all().map(\.id))
                previews.append(RestoreCategoryPreview(
                    category: .replaceRules, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.id), localIds: localIds, style: .upsert)
                ))
            }
            if categories.contains(.highlightRules) {
                let items = try decoder.decode(
                    [HighlightRule].self, from: Data(try await client.download(path: BackupCategory.highlightRules.fileName).utf8)
                )
                plan.highlightRules = items
                let localIds = Set(try await env.highlightRuleStore.all().map(\.id))
                previews.append(RestoreCategoryPreview(
                    category: .highlightRules, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.id), localIds: localIds, style: .upsert)
                ))
            }
            if categories.contains(.tagGroupRules) {
                let items = try decoder.decode(
                    [TagGroupRule].self, from: Data(try await client.download(path: BackupCategory.tagGroupRules.fileName).utf8)
                )
                plan.tagGroupRules = items
                let localIds = Set(try await env.tagGroupRuleStore.all().map(\.id))
                previews.append(RestoreCategoryPreview(
                    category: .tagGroupRules, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.id), localIds: localIds, style: .upsert)
                ))
            }
            if categories.contains(.txtSplitRules) {
                let items = try decoder.decode(
                    [TxtSplitRule].self, from: Data(try await client.download(path: BackupCategory.txtSplitRules.fileName).utf8)
                )
                plan.txtSplitRules = items
                let localIds = Set(try await env.txtSplitRuleStore.all().map(\.id))
                previews.append(RestoreCategoryPreview(
                    category: .txtSplitRules, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.id), localIds: localIds, style: .upsert)
                ))
            }
            if categories.contains(.rssSources) {
                let items = try decoder.decode(
                    [RssSource].self, from: Data(try await client.download(path: BackupCategory.rssSources.fileName).utf8)
                )
                plan.rssSources = items
                let localIds = Set(try await env.rssSourceStore.all().map(\.sourceUrl))
                previews.append(RestoreCategoryPreview(
                    category: .rssSources, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.sourceUrl), localIds: localIds, style: .upsert)
                ))
            }
            if categories.contains(.bookmarks) {
                let items = try decoder.decode(
                    [Bookmark].self, from: Data(try await client.download(path: BackupCategory.bookmarks.fileName).utf8)
                )
                plan.bookmarks = items
                let localIds = Set(try await env.bookmarkStore.all().map(\.id))
                previews.append(RestoreCategoryPreview(
                    category: .bookmarks, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.id), localIds: localIds, style: .appendDedup)
                ))
            }
            if categories.contains(.localBooks) {
                let items = try decoder.decode(
                    [LocalBook].self, from: Data(try await client.download(path: BackupCategory.localBooks.fileName).utf8)
                )
                plan.localBooks = items
                let localIds = Set(try await env.localBookStore.all().map(\.id))
                previews.append(RestoreCategoryPreview(
                    category: .localBooks, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.id), localIds: localIds, style: .appendDedup)
                ))
            }
            if categories.contains(.aiProviders) {
                let items = try decoder.decode(
                    [AIProvider].self, from: Data(try await client.download(path: BackupCategory.aiProviders.fileName).utf8)
                )
                plan.aiProviders = items
                let localIds = Set(try await env.aiProviderStore.all().map(\.id))
                previews.append(RestoreCategoryPreview(
                    category: .aiProviders, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.id), localIds: localIds, style: .upsert)
                ))
            }

            plan.previews = previews
            pendingRestore = plan
        } catch {
            statusMessage = "预览失败: \(error)"
        }
        isWorking = false
    }

    /// Builds every enabled category's data in one pass and writes it as a single JSON file to a
    /// temp location, then hands that off to the system share sheet (already used elsewhere in this
    /// app as `ShareSheet`) -- "保存到文件" App, AirDrop to another of the user's own devices,
    /// email-to-self, whatever the user's share sheet offers, all work without this needing to know
    /// about any of them specifically.
    private func exportToLocalFile() async {
        isWorking = true
        statusMessage = nil
        do {
            let categories = enabledCategories
            var bundle = LocalBackupBundle()
            if categories.contains(.bookSources) { bundle.bookSources = try await env.bookSourceStore.all() }
            if categories.contains(.shelf) { bundle.shelf = try await env.shelfStore.all() }
            if categories.contains(.replaceRules) { bundle.replaceRules = try await env.replaceRuleStore.all() }
            if categories.contains(.highlightRules) { bundle.highlightRules = try await env.highlightRuleStore.all() }
            if categories.contains(.tagGroupRules) { bundle.tagGroupRules = try await env.tagGroupRuleStore.all() }
            if categories.contains(.txtSplitRules) { bundle.txtSplitRules = try await env.txtSplitRuleStore.all() }
            if categories.contains(.rssSources) { bundle.rssSources = try await env.rssSourceStore.all() }
            if categories.contains(.bookmarks) { bundle.bookmarks = try await env.bookmarkStore.all() }
            if categories.contains(.localBooks) { bundle.localBooks = try await env.localBookStore.all() }
            if categories.contains(.aiProviders) { bundle.aiProviders = try await env.aiProviderStore.all() }

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(bundle)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let fileName = "YueDu备份-\(formatter.string(from: Date())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)

            localExportURL = url
            isShowingLocalExportSheet = true
            statusMessage = "已生成备份文件"
        } catch {
            statusMessage = "导出失败: \(error)"
        }
        isWorking = false
    }

    /// The local-file mirror of `downloadAndPreviewRestore` -- same per-category diff-then-preview
    /// shape, just sourced from one already-decoded `LocalBackupBundle` (the whole file was one
    /// `Data` read, not N separate downloads) instead of N separate WebDAV downloads. Feeds into the
    /// exact same `pendingRestore`/`RestorePreviewSheet`/`applyRestore` the WebDAV path uses --
    /// nothing about confirming or writing the restore differs based on where the plan came from.
    private func importFromLocalFile(_ result: Result<URL, Error>) async {
        isWorking = true
        statusMessage = nil
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let bundle = try decoder.decode(LocalBackupBundle.self, from: data)

            var plan = RestorePlan()
            var previews: [RestoreCategoryPreview] = []

            if let items = bundle.bookSources {
                plan.bookSources = items
                let localIds = Set(try await env.bookSourceStore.all().map(\.bookSourceUrl))
                previews.append(RestoreCategoryPreview(
                    category: .bookSources, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.bookSourceUrl), localIds: localIds, style: .upsert)
                ))
            }
            if let items = bundle.shelf {
                plan.shelf = items
                let localIds = Set(try await env.shelfStore.all().map(\.bookUrl))
                previews.append(RestoreCategoryPreview(
                    category: .shelf, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.bookUrl), localIds: localIds, style: .upsert)
                ))
            }
            if let items = bundle.replaceRules {
                plan.replaceRules = items
                let localIds = Set(try await env.replaceRuleStore.all().map(\.id))
                previews.append(RestoreCategoryPreview(
                    category: .replaceRules, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.id), localIds: localIds, style: .upsert)
                ))
            }
            if let items = bundle.highlightRules {
                plan.highlightRules = items
                let localIds = Set(try await env.highlightRuleStore.all().map(\.id))
                previews.append(RestoreCategoryPreview(
                    category: .highlightRules, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.id), localIds: localIds, style: .upsert)
                ))
            }
            if let items = bundle.tagGroupRules {
                plan.tagGroupRules = items
                let localIds = Set(try await env.tagGroupRuleStore.all().map(\.id))
                previews.append(RestoreCategoryPreview(
                    category: .tagGroupRules, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.id), localIds: localIds, style: .upsert)
                ))
            }
            if let items = bundle.txtSplitRules {
                plan.txtSplitRules = items
                let localIds = Set(try await env.txtSplitRuleStore.all().map(\.id))
                previews.append(RestoreCategoryPreview(
                    category: .txtSplitRules, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.id), localIds: localIds, style: .upsert)
                ))
            }
            if let items = bundle.rssSources {
                plan.rssSources = items
                let localIds = Set(try await env.rssSourceStore.all().map(\.sourceUrl))
                previews.append(RestoreCategoryPreview(
                    category: .rssSources, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.sourceUrl), localIds: localIds, style: .upsert)
                ))
            }
            if let items = bundle.bookmarks {
                plan.bookmarks = items
                let localIds = Set(try await env.bookmarkStore.all().map(\.id))
                previews.append(RestoreCategoryPreview(
                    category: .bookmarks, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.id), localIds: localIds, style: .appendDedup)
                ))
            }
            if let items = bundle.localBooks {
                plan.localBooks = items
                let localIds = Set(try await env.localBookStore.all().map(\.id))
                previews.append(RestoreCategoryPreview(
                    category: .localBooks, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.id), localIds: localIds, style: .appendDedup)
                ))
            }
            if let items = bundle.aiProviders {
                plan.aiProviders = items
                let localIds = Set(try await env.aiProviderStore.all().map(\.id))
                previews.append(RestoreCategoryPreview(
                    category: .aiProviders, remoteCount: items.count,
                    diff: RestorePreviewCalculator.diff(remoteIds: items.map(\.id), localIds: localIds, style: .upsert)
                ))
            }

            plan.previews = previews
            pendingRestore = plan
        } catch {
            statusMessage = "导入失败: \(error)"
        }
        isWorking = false
    }

    /// Actually writes a previously downloaded-and-previewed plan into the local stores. Reuses the
    /// same per-category merge behavior the old direct-restore code had (upsert for most categories;
    /// dedupe-by-id before appending for bookmarks/local books, since those stores' `add` always
    /// appends).
    private func applyRestore(_ plan: RestorePlan) async {
        isWorking = true
        statusMessage = nil
        var summary: [String] = []
        do {
            if let items = plan.bookSources {
                let (inserted, updated) = try await env.bookSourceStore.importSources(items)
                summary.append("书源新增 \(inserted)/更新 \(updated)")
            }
            if let items = plan.shelf {
                for item in items { try await env.shelfStore.addOrUpdate(item) }
                summary.append("书架 \(items.count)")
            }
            if let items = plan.replaceRules {
                for item in items { try await env.replaceRuleStore.add(item) }
                summary.append("净化规则 \(items.count)")
            }
            if let items = plan.highlightRules {
                for item in items { try await env.highlightRuleStore.add(item) }
                summary.append("高亮规则 \(items.count)")
            }
            if let items = plan.tagGroupRules {
                for item in items { try await env.tagGroupRuleStore.add(item) }
                summary.append("分组规则 \(items.count)")
            }
            if let items = plan.txtSplitRules {
                for item in items { try await env.txtSplitRuleStore.add(item) }
                summary.append("TXT 分章规则 \(items.count)")
            }
            if let items = plan.rssSources {
                for item in items { try await env.rssSourceStore.add(item) }
                summary.append("RSS 订阅源 \(items.count)")
            }
            if let items = plan.bookmarks {
                let existingIds = Set(try await env.bookmarkStore.all().map(\.id))
                var added = 0
                for item in items where !existingIds.contains(item.id) {
                    try await env.bookmarkStore.add(item)
                    added += 1
                }
                summary.append("书签新增 \(added)")
            }
            if let items = plan.localBooks {
                let existingIds = Set(try await env.localBookStore.all().map(\.id))
                var added = 0
                for item in items where !existingIds.contains(item.id) {
                    try await env.localBookStore.add(item)
                    added += 1
                }
                summary.append("本地书籍新增 \(added)")
            }
            if let items = plan.aiProviders {
                for item in items { try await env.aiProviderStore.add(item) }
                summary.append("AI 服务商 \(items.count)")
            }

            statusMessage = "恢复完成：" + summary.joined(separator: "，")
        } catch {
            statusMessage = "恢复失败: \(error)"
        }
        isWorking = false
    }
}

/// One category's decoded remote data plus its precomputed diff, waiting on user confirmation.
/// Holding the already-decoded arrays (rather than re-downloading on confirm) means the preview the
/// user reviewed is exactly what gets written -- no risk of the server-side data changing between
/// preview and confirm.
/// The local-file backup's on-disk shape -- deliberately the same field set as `RestorePlan` (minus
/// `id`/`previews`, which only make sense for the in-memory preview state), so `exportToLocalFile`/
/// `importFromLocalFile` can build/read it with the exact same per-category logic the WebDAV path
/// already uses. One combined JSON file, not a `.zip` the way Legado's local backup is -- there's no
/// binary/asset data in any of these categories (local book *content* stays in `LocalBook` as plain
/// text, no separate cover/font files to bundle), so a single JSON object is already the whole
/// backup, not an approximation of one.
private struct LocalBackupBundle: Codable {
    var bookSources: [BookSource]?
    var shelf: [ShelfBook]?
    var replaceRules: [ReplaceRule]?
    var highlightRules: [HighlightRule]?
    var tagGroupRules: [TagGroupRule]?
    var txtSplitRules: [TxtSplitRule]?
    var rssSources: [RssSource]?
    var bookmarks: [Bookmark]?
    var localBooks: [LocalBook]?
    var aiProviders: [AIProvider]?
}

private struct RestorePlan: Identifiable {
    let id = UUID()
    var bookSources: [BookSource]?
    var shelf: [ShelfBook]?
    var replaceRules: [ReplaceRule]?
    var highlightRules: [HighlightRule]?
    var tagGroupRules: [TagGroupRule]?
    var txtSplitRules: [TxtSplitRule]?
    var rssSources: [RssSource]?
    var bookmarks: [Bookmark]?
    var localBooks: [LocalBook]?
    var aiProviders: [AIProvider]?
    var previews: [RestoreCategoryPreview] = []
}

private struct RestoreCategoryPreview: Identifiable {
    let category: BackupCategory
    let remoteCount: Int
    let diff: RestoreDiff
    var id: String { category.rawValue }

    var summary: String {
        if diff.willUpdate > 0 {
            return "远端 \(remoteCount) 项 → 新增 \(diff.willInsert)，更新 \(diff.willUpdate)"
        } else if diff.willSkip > 0 {
            return "远端 \(remoteCount) 项 → 新增 \(diff.willInsert)，跳过 \(diff.willSkip) 项重复"
        } else if remoteCount == 0 {
            return "远端没有数据"
        } else {
            return "远端 \(remoteCount) 项 → 全部新增"
        }
    }
}

private struct RestorePreviewSheet: View {
    let plan: RestorePlan
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Form {
            Section {
                ForEach(plan.previews) { preview in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preview.category.displayName).font(.subheadline)
                        Text(preview.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("确认后会立即写入本机存储，覆盖同名/同 ID 的已有数据。")
            }
        }
        .navigationTitle("恢复预览")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("确认恢复", action: onConfirm)
            }
        }
    }
}
