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
                NavigationLink {
                    AIProviderListView()
                } label: {
                    Label("AI 服务商", systemImage: "sparkles")
                }
                NavigationLink {
                    HighlightRuleListView()
                } label: {
                    Label("高亮规则", systemImage: "highlighter")
                }
                NavigationLink {
                    TagGroupRuleListView()
                } label: {
                    Label("分组规则", systemImage: "tag")
                }
                NavigationLink {
                    ReadingStatsView()
                } label: {
                    Label("阅读统计", systemImage: "chart.bar")
                }
                NavigationLink {
                    StorageManagementView()
                } label: {
                    Label("存储管理", systemImage: "externaldrive")
                }
                NavigationLink {
                    BookmarkListView()
                } label: {
                    Label("书签", systemImage: "bookmark")
                }
                NavigationLink {
                    AboutView()
                } label: {
                    Label("关于", systemImage: "info.circle")
                }
            }
            .navigationTitle("设置")
        }
    }
}
