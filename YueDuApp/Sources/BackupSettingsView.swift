import SwiftUI
import BookSourceModel
import Persistence
import NetworkClient

/// Full backup/restore of selected data categories to/from a WebDAV server. Deliberately not a
/// continuous background sync -- explicit "备份"/"恢复" buttons the user triggers, which is easier
/// to reason about and test than trying to get automatic conflict resolution right in a first
/// version. Which categories get included is user-selectable (see `BackupCategory`) rather than
/// always being "everything" -- some data is large (local books' full text) and some just isn't
/// everyone's concern to sync (RSS subscriptions, AI provider list).
struct BackupSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @AppStorage("webdav.baseURL") private var baseURL: String = ""
    @AppStorage("webdav.username") private var username: String = ""
    @AppStorage("backup.enabledCategories") private var enabledCategoriesRaw: String = BackupCategory.allCases
        .filter(\.defaultEnabled).map(\.rawValue).joined(separator: ",")
    @State private var password: String = KeychainStore.get("webdav.password") ?? ""
    @State private var statusMessage: String?
    @State private var isWorking = false

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
                Button("从云端恢复") { Task { await restore() } }
                    .disabled(isWorking || baseURL.isEmpty || enabledCategories.isEmpty)
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

    private func restore() async {
        isWorking = true
        statusMessage = nil
        var summary: [String] = []
        do {
            let client = makeClient()
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let categories = enabledCategories

            if categories.contains(.bookSources) {
                let json = try await client.download(path: BackupCategory.bookSources.fileName)
                let items = try decoder.decode([BookSource].self, from: Data(json.utf8))
                let (inserted, updated) = try await env.bookSourceStore.importSources(items)
                summary.append("书源新增 \(inserted)/更新 \(updated)")
            }
            if categories.contains(.shelf) {
                let json = try await client.download(path: BackupCategory.shelf.fileName)
                let items = try decoder.decode([ShelfBook].self, from: Data(json.utf8))
                for item in items { try await env.shelfStore.addOrUpdate(item) }
                summary.append("书架 \(items.count)")
            }
            if categories.contains(.replaceRules) {
                let json = try await client.download(path: BackupCategory.replaceRules.fileName)
                let items = try decoder.decode([ReplaceRule].self, from: Data(json.utf8))
                for item in items { try await env.replaceRuleStore.add(item) }
                summary.append("净化规则 \(items.count)")
            }
            if categories.contains(.highlightRules) {
                let json = try await client.download(path: BackupCategory.highlightRules.fileName)
                let items = try decoder.decode([HighlightRule].self, from: Data(json.utf8))
                for item in items { try await env.highlightRuleStore.add(item) }
                summary.append("高亮规则 \(items.count)")
            }
            if categories.contains(.tagGroupRules) {
                let json = try await client.download(path: BackupCategory.tagGroupRules.fileName)
                let items = try decoder.decode([TagGroupRule].self, from: Data(json.utf8))
                for item in items { try await env.tagGroupRuleStore.add(item) }
                summary.append("分组规则 \(items.count)")
            }
            if categories.contains(.txtSplitRules) {
                let json = try await client.download(path: BackupCategory.txtSplitRules.fileName)
                let items = try decoder.decode([TxtSplitRule].self, from: Data(json.utf8))
                for item in items { try await env.txtSplitRuleStore.add(item) }
                summary.append("TXT 分章规则 \(items.count)")
            }
            if categories.contains(.rssSources) {
                let json = try await client.download(path: BackupCategory.rssSources.fileName)
                let items = try decoder.decode([RssSource].self, from: Data(json.utf8))
                for item in items { try await env.rssSourceStore.add(item) }
                summary.append("RSS 订阅源 \(items.count)")
            }
            if categories.contains(.bookmarks) {
                // BookmarkStore.add always appends (a bookmark isn't "the same slot" the way a rule
                // with a stable id is meant to be upserted into) -- dedupe by id here so restoring
                // twice doesn't double every bookmark.
                let json = try await client.download(path: BackupCategory.bookmarks.fileName)
                let items = try decoder.decode([Bookmark].self, from: Data(json.utf8))
                let existingIds = Set(try await env.bookmarkStore.all().map(\.id))
                var added = 0
                for item in items where !existingIds.contains(item.id) {
                    try await env.bookmarkStore.add(item)
                    added += 1
                }
                summary.append("书签新增 \(added)")
            }
            if categories.contains(.localBooks) {
                // Same reasoning as bookmarks: LocalBookStore.add always appends.
                let json = try await client.download(path: BackupCategory.localBooks.fileName)
                let items = try decoder.decode([LocalBook].self, from: Data(json.utf8))
                let existingIds = Set(try await env.localBookStore.all().map(\.id))
                var added = 0
                for item in items where !existingIds.contains(item.id) {
                    try await env.localBookStore.add(item)
                    added += 1
                }
                summary.append("本地书籍新增 \(added)")
            }
            if categories.contains(.aiProviders) {
                let json = try await client.download(path: BackupCategory.aiProviders.fileName)
                let items = try decoder.decode([AIProvider].self, from: Data(json.utf8))
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
