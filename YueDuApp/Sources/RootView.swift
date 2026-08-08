import SwiftUI

struct RootView: View {
    // Reads the standard NSUserDefaults "argument domain" (launch arguments like
    // `-selectedTabIndex 1`) so CI's screenshot workflow can launch straight into a specific tab
    // without needing XCUITest automation to tap through the UI -- normal app launches never pass
    // this argument, so this has no effect outside of CI.
    @State private var selectedTab = UserDefaults.standard.integer(forKey: "selectedTabIndex")

    var body: some View {
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
    }
}
