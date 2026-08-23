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
    @State private var isShowingClearCookiesConfirm = false

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
                    Button("清除 Cookie", role: .destructive) {
                        isShowingClearCookiesConfirm = true
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
        .confirmationDialog(
            "清除这个书源的 Cookie？", isPresented: $isShowingClearCookiesConfirm, titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) { Task { await clearCookies() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清除后需要重新登录/验证才能继续访问需要登录的内容。")
        }
    }

    private func reload() async {
        variableText = (try? await env.sourceVariableStore.variable(bookSourceUrl: source.bookSourceUrl)) ?? ""
        cookies = (try? await env.loginCookieStore.cookies(bookSourceUrl: source.bookSourceUrl)) ?? []
    }

    private func saveVariable() async {
        try? await env.sourceVariableStore.setVariable(variableText, bookSourceUrl: source.bookSourceUrl)
        statusMessage = "已保存"
    }

    /// Clears both halves of where a login's cookies actually live -- `loginCookieStore`
    /// (`setCookies([], ...)` already removes the persisted entry outright, same as `SourceLoginView`
    /// would if it captured zero cookies) and `HTTPCookieStorage.shared`, the live jar
    /// `URLSessionHTTPClient` actually reads from this session; clearing only the persisted half
    /// would leave this session still silently authenticated until the next relaunch. Domain-matching
    /// mirrors `SourceLoginView.saveCookiesAndDismiss`'s own convention exactly, for the same reason:
    /// a shared cookie jar can carry cookies from unrelated domains that must not be touched.
    private func clearCookies() async {
        try? await env.loginCookieStore.setCookies([], bookSourceUrl: source.bookSourceUrl)
        if let host = URL(string: source.bookSourceUrl)?.host, let liveCookies = HTTPCookieStorage.shared.cookies {
            for cookie in liveCookies {
                let cookieDomain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                if host == cookieDomain || host.hasSuffix("." + cookieDomain) {
                    HTTPCookieStorage.shared.deleteCookie(cookie)
                }
            }
        }
        cookies = []
        statusMessage = "已清除"
    }
}
