import SwiftUI
import Persistence
import NetworkClient
import WebBookOrchestrator

/// Browses a WebDAV folder to pick a .txt file to import as a local book -- distinct from WebDAV
/// *backup* (`BackupSettingsView`), which syncs the app's own data; this pulls in book files the
/// user already has stored on their WebDAV server. Shares the same stored server URL/username
/// (`@AppStorage("webdav.baseURL")`/`"webdav.username"`) and Keychain-stored password as backup,
/// since it's realistically the same account either way. Recurses into itself (with a deeper
/// `path`) for subfolders rather than needing a separate navigation stack of distinct view types.
struct WebDAVBookImportView: View {
    var path: String = ""

    @EnvironmentObject private var env: AppEnvironment
    @AppStorage("webdav.baseURL") private var baseURL: String = ""
    @AppStorage("webdav.username") private var username: String = ""
    @State private var items: [WebDAVItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isImporting = false

    var body: some View {
        List {
            if baseURL.isEmpty {
                ContentUnavailableView(
                    "还没有配置 WebDAV", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("先在\u{201C}备份与同步\u{201D}里填好服务器地址")
                )
            } else if let errorMessage {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if items.isEmpty && !isLoading {
                ContentUnavailableView("文件夹是空的", systemImage: "folder")
            }
            ForEach(items) { item in
                itemRow(item)
            }
        }
        .overlay {
            if isLoading || isImporting {
                ProgressView()
            }
        }
        .navigationTitle(currentFolderName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    private var currentFolderName: String {
        path.isEmpty ? "WebDAV 书籍" : (path.split(separator: "/").last.map(String.init) ?? "WebDAV 书籍")
    }

    @ViewBuilder
    private func itemRow(_ item: WebDAVItem) -> some View {
        if item.isDirectory {
            NavigationLink {
                WebDAVBookImportView(path: childPath(item))
            } label: {
                Label(item.name, systemImage: "folder")
            }
        } else {
            Button {
                Task { await importFile(item) }
            } label: {
                Label(item.name, systemImage: "doc.text")
            }
            .disabled(isImporting || !item.name.lowercased().hasSuffix(".txt"))
        }
    }

    private func childPath(_ item: WebDAVItem) -> String {
        let trimmedBase = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmedBase.isEmpty ? item.name : "\(trimmedBase)/\(item.name)"
    }

    private func makeClient() -> WebDAVClient {
        let password = KeychainStore.get("webdav.password") ?? ""
        return WebDAVClient(
            httpClient: env.httpClient, config: WebDAVConfig(baseURL: baseURL, username: username, password: password)
        )
    }

    private func reload() async {
        guard !baseURL.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await makeClient().listDirectory(path: path)
            items = fetched.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        } catch {
            errorMessage = FriendlyError.message(for: error)
        }
        isLoading = false
    }

    /// Text only, not charset-autodetected the way local file import is -- `WebDAVClient.download`
    /// goes through the shared `HTTPClient` abstraction, whose response body is already decoded as
    /// a `String` (UTF-8) before this code ever sees the bytes, so a GBK-encoded remote .txt would
    /// come through mangled. Local file import doesn't have this limitation (it reads raw `Data`
    /// and runs `CharsetDetector` itself); fixing this for WebDAV too would mean teaching
    /// `HTTPClient` to also expose raw response bytes, a bigger change than this increment's scope.
    private func importFile(_ item: WebDAVItem) async {
        isImporting = true
        defer { isImporting = false }
        do {
            let text = try await makeClient().download(path: childPath(item))
            let title = item.name.lowercased().hasSuffix(".txt") ? String(item.name.dropLast(4)) : item.name
            let patterns = ((try? await env.txtSplitRuleStore.enabled()) ?? []).map(\.pattern)
            let split = TxtChapterSplitter.splitTryingRules(text, rules: patterns, fallbackTitle: title)
            guard !split.isEmpty else {
                errorMessage = "这个文件看起来是空的"
                return
            }
            let chapters = split.map { LocalChapter(title: $0.title, text: $0.text) }
            try await env.localBookStore.add(LocalBook(title: title, chapters: chapters))
        } catch {
            errorMessage = "导入失败: " + FriendlyError.message(for: error)
        }
    }
}
