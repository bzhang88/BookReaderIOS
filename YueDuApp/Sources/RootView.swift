import SwiftUI
import Persistence

struct RootView: View {
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

    var body: some View {
        if uiTestingScreen == "localReader" {
            NavigationStack {
                LocalReaderView(book: Self.uiTestingSeedBook)
            }
        } else if isLocked && !isUITesting {
            AppLockView(onUnlock: { isLocked = false })
        } else {
            TabView(selection: $selectedTab) {
                ShelfView()
                    .tabItem { Label("书架", systemImage: "books.vertical") }
                    .tag(0)
                SourceLibraryView()
                    .tabItem { Label("书源库", systemImage: "tray.full") }
                    .tag(1)
                RssListView()
                    .tabItem { Label("订阅", systemImage: "dot.radiowaves.up.forward") }
                    .tag(2)
                SettingsView()
                    .tabItem { Label("设置", systemImage: "gearshape") }
                    .tag(3)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background && AppLockStore.isEnabled {
                    isLocked = true
                }
            }
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
