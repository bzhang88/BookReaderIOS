import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            ShelfView()
                .tabItem { Label("书架", systemImage: "books.vertical") }
            SourceLibraryView()
                .tabItem { Label("书源库", systemImage: "tray.full") }
            RssListView()
                .tabItem { Label("订阅", systemImage: "dot.radiowaves.up.forward") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}
