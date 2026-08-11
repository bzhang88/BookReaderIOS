import SwiftUI
import WebKit
import BookSourceModel
import Persistence

/// Book-source login. Legado's real login flow branches into two very different UIs depending on
/// the source (a JS-driven dynamic form dialog, or a plain WebView) -- replicating the form variant
/// faithfully would mean modeling Legado's JS-callback-driven dynamic UI system (buttons that
/// re-evaluate JS to relabel themselves, live reflow, etc; see `RowUi`/`SourceLoginDialog.kt` in the
/// reference source), which is a much bigger integration than this increment's worth. This instead
/// always routes through a real WebView -- the user logs in on the site's own actual page (handles
/// captchas, 2FA, anything), and cookies are captured from it afterward. That covers the same
/// underlying need (get a session cookie the source's later requests can use) without needing to
/// understand or execute the source's specific login JS.
struct SourceLoginView: View {
    /// `.login` (the default) only opens when the source declares a real web login URL, matching
    /// the original login-only behavior. `.verify` is for sources that don't have a login flow at
    /// all but still gate plain requests (search, etc.) behind a CAPTCHA or Cloudflare-style
    /// challenge -- confirmed against Legado_Max's real `SourceVerificationHelp`/
    /// `VerificationCodeActivity` that this exists as its own concept, separate from login. Real
    /// Legado *detects* when a challenge is needed (a JS callback mid-request pops the CAPTCHA
    /// dialog); this app's rule engine doesn't execute that same `java.*` JS bridge, so automatic
    /// detection isn't feasible here -- instead this just always offers a manual "open the source's
    /// site in a WebView, solve whatever appears, capture the resulting cookies" entry point,
    /// reusing the exact same WebView+cookie-capture mechanics login already has, just pointed at
    /// the source's own `bookSourceUrl` instead of requiring a dedicated `loginUrl`.
    enum Mode {
        case login
        case verify
    }

    let source: BookSource
    var mode: Mode = .login

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var statusMessage: String?

    private var targetURL: URL? {
        switch mode {
        case .login:
            guard source.hasWebLoginURL, let loginUrl = source.loginUrl else { return nil }
            return URL(string: loginUrl)
        case .verify:
            return URL(string: source.bookSourceUrl)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let targetURL {
                    SourceLoginWebView(url: targetURL, userAgent: source.parsedHeaders()["User-Agent"])
                } else {
                    ContentUnavailableView(
                        mode == .login ? "该书源登录方式暂不支持" : "书源地址无效",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text(
                            mode == .login
                                ? "这个书源的登录需要执行脚本才能完成，本 App 目前只支持网页登录。"
                                : "这个书源的地址无法在网页里打开。"
                        )
                    )
                }
            }
            .navigationTitle(mode == .login ? "登录 \(source.bookSourceName)" : "验证 \(source.bookSourceName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                if targetURL != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSaving ? "保存中…" : "完成") {
                            Task { await saveCookiesAndDismiss() }
                        }
                        .disabled(isSaving)
                    }
                }
            }
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
        }
    }

    /// Reads every cookie currently in the WebView's own cookie jar, keeps only the ones whose
    /// domain actually matches this source (a shared `WKWebsiteDataStore.default()` can carry
    /// cookies from unrelated sites the user has logged into before), and hands them off two ways:
    /// persisted via `loginCookieStore` so the login survives a relaunch, and copied straight into
    /// `HTTPCookieStorage.shared` so this session's `URLSessionHTTPClient` calls pick them up
    /// immediately without waiting for the next app launch's re-injection pass.
    private func saveCookiesAndDismiss() async {
        isSaving = true
        defer { isSaving = false }
        let allCookies = await fetchAllWebViewCookies()
        let host = URL(string: source.bookSourceUrl)?.host
        let matched = allCookies.filter { cookie in
            guard let host else { return true }
            let cookieDomain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return host == cookieDomain || host.hasSuffix("." + cookieDomain)
        }
        guard !matched.isEmpty else {
            statusMessage = mode == .login
                ? "没有检测到登录 Cookie，请先在页面里完成登录"
                : "没有检测到新的 Cookie，请先在页面里完成验证（比如过一遍验证码）"
            return
        }
        for cookie in matched {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        let saved = matched.map { cookie in
            SavedCookie(
                name: cookie.name, value: cookie.value, domain: cookie.domain,
                path: cookie.path, isSecure: cookie.isSecure, expiresAt: cookie.expiresDate
            )
        }
        try? await env.loginCookieStore.setCookies(saved, bookSourceUrl: source.bookSourceUrl)
        dismiss()
    }

    private func fetchAllWebViewCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
}

private struct SourceLoginWebView: UIViewRepresentable {
    let url: URL
    let userAgent: String?

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.customUserAgent = userAgent
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
