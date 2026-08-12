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

    // "legado://import/<kind>?src=<url>" -- lets a shared link or QR code jump straight into
    // importing something instead of the user having to copy/paste the URL by hand. Matches
    // Legado's own real-world import-link convention (see project.yml's CFBundleURLTypes comment
    // and `FileAssociationActivity.kt`'s real dispatch, confirmed against the actual source rather
    // than guessed) so links/QR codes made for actual Legado are compatible here too, for whichever
    // of the 7 types this app actually has somewhere to import into (see `LegadoImportKind`).
    private struct PendingImport {
        var kind: LegadoImportKind
        var url: URL
    }
    @State private var pendingImport: PendingImport?
    @State private var importResultMessage: String?

    var body: some View {
        Group {
            if uiTestingScreen == "localReader" {
                NavigationStack {
                    LocalReaderView(book: Self.uiTestingSeedBook)
                }
            } else if uiTestingScreen == "localReaderToc" {
                NavigationStack {
                    LocalReaderView(book: Self.uiTestingSeedBook, startWithTocOpen: true)
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
        .alert(pendingImportAlertTitle, isPresented: Binding(
            get: { pendingImport != nil },
            set: { if !$0 { pendingImport = nil } }
        )) {
            if pendingImport?.kind.isSupported == true {
                Button("导入") { Task { await confirmPendingImport() } }
                Button("取消", role: .cancel) { pendingImport = nil }
            } else {
                Button("好") { pendingImport = nil }
            }
        } message: {
            if let pendingImport {
                Text(pendingImport.kind.isSupported
                    ? pendingImport.url.absoluteString
                    : "本 App 暂不支持导入\(pendingImport.kind.displayName)")
            }
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
    // Icon-only tab items (no text label) -- confirmed against Legado_Max's real `activity_main.xml`,
    // which sets `app:labelVisibilityMode="unlabeled"` on its bottom nav. A `.tabItem` whose content
    // is a bare `Image` (no `Text`/`Label`) is SwiftUI's own idiom for suppressing the title, so this
    // doesn't need a `UITabBarAppearance` proxy hack -- just not wrapping the icon in `Label(_:
    // systemImage:)` (which always renders icon+text) like the previous version did.
    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            ShelfView()
                .tabItem { Image(systemName: "books.vertical") }
                .tag(0)
            ExploreView()
                .tabItem { Image(systemName: "safari") }
                .tag(1)
            RssListView()
                .tabItem { Image(systemName: "dot.radiowaves.up.forward") }
                .tag(2)
            SettingsView()
                .tabItem { Image(systemName: "person.circle") }
                .tag(3)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && AppLockStore.isEnabled {
                isLocked = true
            }
        }
    }

    private var pendingImportAlertTitle: String {
        guard let kind = pendingImport?.kind else { return "" }
        return kind.isSupported ? "导入\(kind.displayName)？" : "无法导入"
    }

    /// Ignores incoming links entirely while locked -- importing something before the user has
    /// unlocked would defeat the point of having a lock at all, and there's no good place to queue
    /// the link for after unlock without a lot of extra state, so this keeps it simple: re-tap the
    /// link once you're in.
    private func handleIncomingURL(_ url: URL) {
        guard !isLocked else { return }
        guard url.scheme?.lowercased() == "legado", url.host == "import" else { return }
        guard let kind = LegadoImportKind(path: url.path) else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let src = components.queryItems?.first(where: { $0.name == "src" })?.value,
              let srcURL = URL(string: src) else { return }
        pendingImport = PendingImport(kind: kind, url: srcURL)
    }

    private func confirmPendingImport() async {
        guard let pending = pendingImport, pending.kind.isSupported else { return }
        pendingImport = nil
        do {
            let response = try await env.httpClient.fetch(HTTPRequest(url: pending.url.absoluteString))
            guard let data = response.body.data(using: .utf8) else {
                importResultMessage = "下载内容无法解析为文本"
                return
            }
            importResultMessage = try await importPayload(kind: pending.kind, data: data)
        } catch {
            importResultMessage = "导入失败: \(error)"
        }
    }

    /// One case per `legado://import/<kind>` path segment this app recognizes -- routing +
    /// decode + store target for each. `bookSource`/`dictRule`/`rssSource` decode straight into
    /// this app's own models since their real Legado field names already match (confirmed against
    /// source, not assumed); `replaceRule`/`txtRule` go through a small field-mapping struct (see
    /// `LegadoImportMapping.swift`) since a few field *names* differ even though the underlying
    /// concept is the same.
    private func importPayload(kind: LegadoImportKind, data: Data) async throws -> String {
        switch kind {
        case .bookSource:
            let sources = try BookSourceImportDecoder.decode(from: data)
            let (inserted, updated) = try await env.bookSourceStore.importSources(sources)
            return "导入完成：新增 \(inserted) 个，更新 \(updated) 个"
        case .rssSource:
            let sources = try LegadoImportDecoding.decodeArrayOrSingle(RssSource.self, from: data)
            for source in sources { try await env.rssSourceStore.add(source) }
            return "导入完成：\(sources.count) 个订阅源"
        case .dictRule:
            let rules = try LegadoImportDecoding.decodeArrayOrSingle(DictRule.self, from: data)
            for rule in rules { try await env.dictRuleStore.add(rule) }
            return "导入完成：\(rules.count) 条词典规则"
        case .replaceRule:
            let imported = try LegadoImportDecoding.decodeArrayOrSingle(LegadoReplaceRuleImport.self, from: data)
            for rule in imported { try await env.replaceRuleStore.add(rule.toReplaceRule()) }
            return "导入完成：\(imported.count) 条替换净化规则"
        case .txtRule:
            let imported = try LegadoImportDecoding.decodeArrayOrSingle(LegadoTxtTocRuleImport.self, from: data)
            for rule in imported { try await env.txtSplitRuleStore.add(rule.toTxtSplitRule()) }
            return "导入完成：\(imported.count) 条 TXT 分章规则"
        case .httpTts, .theme:
            // Unreachable -- `confirmPendingImport` only calls this for `kind.isSupported` types.
            return ""
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
