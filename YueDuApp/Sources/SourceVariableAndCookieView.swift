import SwiftUI
import UIKit
import BookSourceModel
import Persistence

/// Two small per-source diagnostic/config tools bundled into one screen since both are read-mostly
/// and small enough not to need separate navigation destinations:
///
/// - **变量** -- confirmed against Legado_Max's real `BaseSource.setVariable`/`getVariable` that
///   this is a plain per-source string blob a book source's own JS can stash state in between
///   requests. This app's rule engine doesn't expose that JS bridge yet, so a value saved here
///   isn't consumed by anything -- this just gives it somewhere to live, honestly labeled as such,
///   rather than pretending it already does something.
/// - **Cookie 查看器** -- confirmed as a real, separate concept from login/verification
///   (`CookieViewerDialog`). Read-only view of whatever `SourceLoginView` (login or verify mode)
///   has captured for this source via `loginCookieStore`, with per-cookie copy.
struct SourceVariableAndCookieView: View {
    let source: BookSource

    @EnvironmentObject private var env: AppEnvironment
    @State private var variableText = ""
    @State private var cookies: [SavedCookie] = []
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section {
                TextEditor(text: $variableText)
                    .frame(minHeight: 100)
                    .font(.system(.body, design: .monospaced))
                Button("保存变量") { Task { await saveVariable() } }
            } header: {
                Text("源变量")
            } footer: {
                Text("书源自己的脚本可以读写这个值来保存状态，比如登录令牌。本 App 的规则引擎目前还没有接入这个读写接口，这里保存的内容暂时不会被实际使用。")
            }

            Section("Cookie") {
                if cookies.isEmpty {
                    Text("还没有捕获到 Cookie，可以先用\u{201C}登录\u{201D}或\u{201C}手动验证\u{201D}过一遍").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(cookies.enumerated()), id: \.offset) { _, cookie in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cookie.name).font(.subheadline).bold()
                            Text(cookie.value).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text(cookie.domain).font(.caption2).foregroundStyle(.tertiary)
                        }
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = "\(cookie.name)=\(cookie.value)"
                                statusMessage = "已复制"
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                            }
                        }
                    }
                    Button("复制全部") {
                        UIPasteboard.general.string = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                        statusMessage = "已复制"
                    }
                }
            }
        }
        .navigationTitle(source.bookSourceName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        variableText = (try? await env.sourceVariableStore.variable(bookSourceUrl: source.bookSourceUrl)) ?? ""
        cookies = (try? await env.loginCookieStore.cookies(bookSourceUrl: source.bookSourceUrl)) ?? []
    }

    private func saveVariable() async {
        try? await env.sourceVariableStore.setVariable(variableText, bookSourceUrl: source.bookSourceUrl)
        statusMessage = "已保存"
    }
}
