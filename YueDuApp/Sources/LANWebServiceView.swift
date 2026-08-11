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
        }
        .navigationTitle("Web 服务")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func start() {
        let port = UInt16(portText) ?? 8080
        server.start(port: port)
    }
}
#endif
