import SwiftUI
import BookSourceModel
import NetworkClient
import Persistence

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    // Reads the standard NSUserDefaults "argument domain" (launch arguments like
    // `-selectedTabIndex 1`) so CI's screenshot workflow can launch straight into a specific tab
    // without needing XCUITest automation to tap through the UI -- normal app launches never pass
    // this argument, so this has no effect outside of CI.
    @State private var selectedTab = UserDefaults.standard.integer(forKey: "selectedTabIndex")

    // Same mechanism, but for jumping straight into a screen that isn't a root tab at all (e.g. the
    // reader, which needs an actual book to display). `-uiTestingScreen localReader` bypasses the
    // TabView entirely and renders a hardcoded sample book -- lets the screenshot CI actually
    // capture what reading text looks like (font/theme/paragraph spacing/chapter nav), which no
    // screenshot this whole project has covered so far since every prior shot only reached a root
    // tab's list/empty state.
    private let uiTestingScreen = UserDefaults.standard.string(forKey: "uiTestingScreen")

    // CI's screenshot workflow always passes one of these launch arguments; a real user launch
    // never does. The app-lock gate below must not block CI (there's no way for it to type a
    // password), so it's skipped whenever either is present.
    private var isUITesting: Bool {
        uiTestingScreen != nil || UserDefaults.standard.object(forKey: "selectedTabIndex") != nil
    }

    @State private var isLocked = AppLockStore.isEnabled
    @Environment(\.scenePhase) private var scenePhase

    // "legado://import/bookSource?src=<url>" -- lets a shared link or QR code jump straight into
    // importing a book source instead of the user having to copy/paste the URL by hand into "从
    // 网址导入". Matches Legado's own real-world import-link convention (see project.yml's
    // CFBundleURLTypes comment) so links/QR codes made for actual Legado are compatible here too.
    @State private var pendingImportSourceURL: URL?
    @State private var importResultMessage: String?

    var body: some View {
        Group {
            if uiTestingScreen == "localReader" {
                NavigationStack {
                    LocalReaderView(book: Self.uiTestingSeedBook)
                }
            } else if isLocked && !isUITesting {
                AppLockView(onUnlock: { isLocked = false })
            } else {
                mainTabView
            }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .alert("导入书源？", isPresented: Binding(
            get: { pendingImportSourceURL != nil },
            set: { if !$0 { pendingImportSourceURL = nil } }
        )) {
            Button("导入") { Task { await confirmPendingImport() } }
            Button("取消", role: .cancel) { pendingImportSourceURL = nil }
        } message: {
            Text(pendingImportSourceURL?.absoluteString ?? "")
        }
        .alert("导入结果", isPresented: Binding(
            get: { importResultMessage != nil },
            set: { if !$0 { importResultMessage = nil } }
        )) {
            Button("好") { importResultMessage = nil }
        } message: {
            Text(importResultMessage ?? "")
        }
    }

    // Tab order/labels match Legado_Max's real stock-Legado-derived bottom nav (书架/发现/订阅/我的)
    // rather than this app's earlier ad-hoc arrangement -- confirmed against the actual Fragment/
    // menu XML in that local reference repo, not guessed from memory. "书源库" isn't a tab anymore;
    // it's reachable from "我的" (see SettingsView), matching how Legado's own book-source manager
    // is a settings entry, not a bottom-nav destination.
    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            ShelfView()
                .tabItem { Label("书架", systemImage: "books.vertical") }
                .tag(0)
            ExploreView()
                .tabItem { Label("发现", systemImage: "safari") }
                .tag(1)
            RssListView()
                .tabItem { Label("订阅", systemImage: "dot.radiowaves.up.forward") }
                .tag(2)
            SettingsView()
                .tabItem { Label("我的", systemImage: "person.circle") }
                .tag(3)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && AppLockStore.isEnabled {
                isLocked = true
            }
        }
    }

    /// Ignores incoming links entirely while locked -- importing something before the user has
    /// unlocked would defeat the point of having a lock at all, and there's no good place to queue
    /// the link for after unlock without a lot of extra state, so this keeps it simple: re-tap the
    /// link once you're in.
    private func handleIncomingURL(_ url: URL) {
        guard !isLocked else { return }
        guard url.scheme?.lowercased() == "legado", url.host == "import" else { return }
        guard url.path.lowercased() == "/booksource" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let src = components.queryItems?.first(where: { $0.name == "src" })?.value,
              let srcURL = URL(string: src) else { return }
        pendingImportSourceURL = srcURL
    }

    private func confirmPendingImport() async {
        guard let sourceURL = pendingImportSourceURL else { return }
        pendingImportSourceURL = nil
        do {
            let response = try await env.httpClient.fetch(HTTPRequest(url: sourceURL.absoluteString))
            guard let data = response.body.data(using: .utf8) else {
                importResultMessage = "下载内容无法解析为文本"
                return
            }
            let sources = try BookSourceImportDecoder.decode(from: data)
            let (inserted, updated) = try await env.bookSourceStore.importSources(sources)
            importResultMessage = "导入完成：新增 \(inserted) 个，更新 \(updated) 个"
        } catch {
            importResultMessage = "导入失败: \(error)"
        }
    }

    private static let uiTestingSeedBook = LocalBook(
        title: "示例小说",
        chapters: [
            LocalChapter(
                title: "第一章 开始",
                text: "这是第一章的正文内容，用来验证阅读器的字号、行间距和主题配色是否正常显示。\n这是第二段，段落之间应该有一定的间距。\n第三段继续测试换行是否正常，以及中文文字的渲染效果。"
            ),
            LocalChapter(
                title: "第二章 风起",
                text: "这是第二章的正文内容，用来验证翻页后标题栏和正文内容都能正确更新。"
            )
        ]
    )
}
