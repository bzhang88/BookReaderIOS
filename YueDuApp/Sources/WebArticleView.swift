import SwiftUI
import WebKit

/// Minimal WKWebView wrapper for reading an RSS article's full page -- SwiftUI has no native
/// WebView on this deployment target (iOS 17), so this is the standard UIViewRepresentable bridge.
struct WebArticleView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}
