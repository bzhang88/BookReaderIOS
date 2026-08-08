import SwiftUI

/// Home for app-wide settings screens -- the roadmap adds more here over time (theming, AI
/// provider config, etc.), so this exists as a dedicated tab rather than bolting individual
/// settings screens onto whichever other tab happened to need one first.
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    BackupSettingsView()
                } label: {
                    Label("备份与同步", systemImage: "icloud.and.arrow.up")
                }
                NavigationLink {
                    ReplaceRuleListView()
                } label: {
                    Label("净化规则", systemImage: "wand.and.stars")
                }
            }
            .navigationTitle("设置")
        }
    }
}
