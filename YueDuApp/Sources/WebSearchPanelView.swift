import SwiftUI
import WebKit
import BookSourceModel

/// A selected-word (or manually typed) web search panel, embedded in a WebView with back/forward
/// navigation and a switchable search engine -- confirmed against Legado_Max's real
/// `ReadWebSearchPanel.kt`. Reached the same way `DictLookupView` is -- see its doc comment for both
/// entry points (reader toolbar with no prefill, or `ReaderView`'s long-press paragraph menu with
/// `initialQuery` set to the pressed paragraph's text).
struct WebSearchPanelView: View {
    var initialQuery: String = ""

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var engines: [WebSearchEngine] = WebSearchEngine.defaults
    @State private var selectedEngineID: String = WebSearchEngine.defaults.first?.id ?? ""
    @StateObject private var navigator = WebViewNavigator()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Picker("引擎", selection: $selectedEngineID) {
                        ForEach(engines) { engine in
                            Text(engine.name).tag(engine.id)
                        }
                    }
                    .pickerStyle(.menu)
                    TextField("搜索内容", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { search() }
                    Button("搜索") { search() }
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(8)
                Divider()
                NavigableWebView(navigator: navigator)
            }
            .navigationTitle("网页搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        navigator.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!navigator.canGoBack)
                    Button {
                        navigator.goForward()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!navigator.canGoForward)
                    NavigationLink {
                        WebSearchEngineListView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .task {
                query = initialQuery
                let custom = (try? await env.webSearchEngineStore.all()) ?? []
                engines = WebSearchEngine.defaults + custom
                if !initialQuery.isEmpty {
                    search()
                }
            }
        }
        .presentationDetents([.large])
    }

    private func search() {
        guard let engine = engines.first(where: { $0.id == selectedEngineID }),
              let url = engine.url(forQuery: query) else { return }
        navigator.load(url)
    }
}

/// Bridges a live `WKWebView` instance out to SwiftUI so back/forward buttons outside the
/// `UIViewRepresentable` can drive it -- `WKWebView` itself already tracks `canGoBack`/
/// `canGoForward`, this just republishes those via `@Published` so button `.disabled(...)` states
/// update as navigation happens.
@MainActor
final class WebViewNavigator: NSObject, ObservableObject, WKNavigationDelegate {
    @Published fileprivate(set) var canGoBack = false
    @Published fileprivate(set) var canGoForward = false

    fileprivate weak var webView: WKWebView?

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func load(_ url: URL) { webView?.load(URLRequest(url: url)) }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}

private struct NavigableWebView: UIViewRepresentable {
    @ObservedObject var navigator: WebViewNavigator

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = navigator
        navigator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
