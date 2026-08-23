import SwiftUI

/// Settings screen for `LANWebServer` -- start/stop toggle plus the address to type into a browser
/// on the same Wi-Fi network. See `LANWebServer`'s doc comment for the honesty note: this compiles
/// and type-checks via CI same as everything else, but the actual socket behavior can only be
/// confirmed by trying it from a real device on a real LAN, unlike this session's other features
/// where the UI Screenshot CI step already gave real behavioral confirmation.
struct LANWebServiceView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        #if canImport(Network)
        LANWebServiceForm(server: env.lanWebServer)
        #else
        ContentUnavailableView("此平台不支持", systemImage: "network.slash")
        #endif
    }
}

#if canImport(Network)
private struct LANWebServiceForm: View {
    @ObservedObject var server: LANWebServer
    @State private var portText = "8080"
    // Real usage feedback (from the same Legado-comparison pass that found this gap): anyone on the
    // same Wi-Fi/LAN could browse the full shelf and read complete book text with zero
    // authentication -- Legado's own real Web服务 has an optional token gate
    // (`AppConfig.webServiceAuthEnabled`/`webServiceToken`) for exactly this. Off by default (`""`),
    // matching this feature's pre-existing no-auth behavior -- enabling it is opt-in, not a
    // breaking change for anyone already using it on a network they trust.
    @AppStorage("lanWeb.requireAuth") private var requireAuth = false
    @AppStorage("lanWeb.accessToken") private var accessToken = ""

    var body: some View {
        Form {
            Section {
                Toggle("开启局域网服务", isOn: Binding(
                    get: { server.isRunning },
                    set: { isOn in isOn ? start() : server.stop() }
                ))
                if server.isRunning {
                    if let address = LANWebServer.bestGuessLocalIPAddress() {
                        LabeledContent("访问地址", value: "http://\(address):\(server.port)")
                    } else {
                        Text("无法确定本机局域网地址，请在系统设置的 Wi-Fi 详情里查看 IP，端口是 \(server.port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let lastError = server.lastError {
                    Text(lastError).font(.caption).foregroundStyle(Color.red)
                }
            } footer: {
                Text("开启后，同一个 Wi-Fi 下的电脑/手机浏览器打开上面的地址，可以浏览书架、查看目录、阅读已加入书架的书（只读，不能搜索/导入）。")
            }

            Section("端口") {
                TextField("端口号", text: $portText)
                    .keyboardType(.numberPad)
                    .disabled(server.isRunning)
            }

            Section {
                Toggle("需要访问密码", isOn: $requireAuth)
                    .disabled(server.isRunning)
                if requireAuth {
                    HStack {
                        TextField("访问密码", text: $accessToken)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .disabled(server.isRunning)
                        Button("随机生成") { accessToken = Self.randomToken() }
                            .disabled(server.isRunning)
                    }
                }
            } footer: {
                Text(
                    requireAuth
                        ? "开启后，浏览器第一次打开访问地址时需要先输入这个密码，同一个 Wi-Fi 下没有密码的人打不开。"
                        : "同一个 Wi-Fi 下的任何人都能直接打开访问地址浏览你的书架和正文，公共/合租网络建议开启密码。"
                )
            }
        }
        .navigationTitle("Web 服务")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Real bug found comparing against Legado: if "需要访问密码" is on but `accessToken` is blank
    /// (never typed anything, or cleared it), `requireAuth ? accessToken : nil` used to pass an
    /// empty string straight through -- `LANWebServer.start`/`LANWebAuth` both treat an empty token
    /// as "no auth configured" and silently serve every request unauthenticated, while the toggle
    /// still shows as on. Generating a real token here whenever the toggle is on (and persisting it
    /// back to `accessToken` so the UI shows what's actually enforced) means turning the switch on
    /// can never silently fail open.
    private func start() {
        let port = UInt16(portText) ?? 8080
        var token: String?
        if requireAuth {
            let trimmed = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            accessToken = trimmed.isEmpty ? Self.randomToken() : trimmed
            token = accessToken
        }
        server.start(port: port, requiredToken: token)
    }

    private static func randomToken() -> String {
        String((0..<8).map { _ in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! })
    }
}
#endif
