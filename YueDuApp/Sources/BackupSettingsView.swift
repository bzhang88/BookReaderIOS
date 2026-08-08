import SwiftUI
import BookSourceModel
import Persistence
import NetworkClient

/// Full backup/restore of book sources + shelf to/from a WebDAV server. Deliberately not a
/// continuous background sync -- explicit "备份"/"恢复" buttons the user triggers, which is easier
/// to reason about and test than trying to get automatic conflict resolution right in a first
/// version.
struct BackupSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @AppStorage("webdav.baseURL") private var baseURL: String = ""
    @AppStorage("webdav.username") private var username: String = ""
    @State private var password: String = KeychainStore.get("webdav.password") ?? ""
    @State private var statusMessage: String?
    @State private var isWorking = false

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

            Section {
                Button("立即备份") { Task { await backup() } }
                    .disabled(isWorking || baseURL.isEmpty)
                Button("从云端恢复") { Task { await restore() } }
                    .disabled(isWorking || baseURL.isEmpty)
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

    private func makeClient() -> WebDAVClient {
        WebDAVClient(
            httpClient: env.httpClient,
            config: WebDAVConfig(baseURL: baseURL, username: username, password: password)
        )
    }

    private func backup() async {
        isWorking = true
        statusMessage = nil
        do {
            let client = makeClient()
            try await client.makeDirectoryIfNeeded(path: "")

            let sources = try await env.bookSourceStore.all()
            let shelf = try await env.shelfStore.all()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            let sourcesJSON = String(data: try encoder.encode(sources), encoding: .utf8) ?? "[]"
            let shelfJSON = String(data: try encoder.encode(shelf), encoding: .utf8) ?? "[]"
            try await client.upload(path: "book_sources.json", content: sourcesJSON)
            try await client.upload(path: "shelf.json", content: shelfJSON)

            statusMessage = "备份完成：\(sources.count) 个书源，\(shelf.count) 本书架书籍"
        } catch {
            statusMessage = "备份失败: \(error)"
        }
        isWorking = false
    }

    private func restore() async {
        isWorking = true
        statusMessage = nil
        do {
            let client = makeClient()
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let sourcesJSON = try await client.download(path: "book_sources.json")
            let sources = try decoder.decode([BookSource].self, from: Data(sourcesJSON.utf8))
            let (inserted, updated) = try await env.bookSourceStore.importSources(sources)

            let shelfJSON = try await client.download(path: "shelf.json")
            let shelfBooks = try decoder.decode([ShelfBook].self, from: Data(shelfJSON.utf8))
            for book in shelfBooks {
                try await env.shelfStore.addOrUpdate(book)
            }

            statusMessage = "恢复完成：书源新增 \(inserted) 个/更新 \(updated) 个，书架 \(shelfBooks.count) 本"
        } catch {
            statusMessage = "恢复失败: \(error)"
        }
        isWorking = false
    }
}
