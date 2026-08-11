import SwiftUI

/// "我的" tab -- doubles as the settings hub, matching Legado's own bottom-nav "我的" tab (its
/// `MyFragment`, a flat `PreferenceScreen`). Section layout mirrors what was found reading
/// `Legado_Max`'s real `pref_main.xml`: a few rule-management screens ungrouped at the top
/// (书源管理 first, exactly like Legado puts book-source management as its very first row), then
/// titled "设置"/"其他" groups, then an untitled "关于" group at the bottom. Our own feature set
/// doesn't map 1:1 onto Legado's exact row list (extra items like 高亮规则/分组规则 that Legado
/// doesn't have) -- the *grouping pattern* is what's being matched, not a literal row-for-row copy.
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SourceLibraryView()
                    } label: {
                        Label("书源管理", systemImage: "tray.full")
                    }
                    NavigationLink {
                        TxtSplitRuleListView()
                    } label: {
                        Label("TXT 分章规则", systemImage: "text.badge.plus")
                    }
                    NavigationLink {
                        ReplaceRuleListView()
                    } label: {
                        Label("替换净化", systemImage: "wand.and.stars")
                    }
                    NavigationLink {
                        DictRuleListView()
                    } label: {
                        Label("词典规则", systemImage: "character.book.closed")
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
                        LANWebServiceView()
                    } label: {
                        Label("Web 服务", systemImage: "network")
                    }
                }

                Section("设置") {
                    NavigationLink {
                        BackupSettingsView()
                    } label: {
                        Label("备份与恢复", systemImage: "icloud.and.arrow.up")
                    }
                    NavigationLink {
                        AIProviderListView()
                    } label: {
                        Label("AI 服务商", systemImage: "sparkles")
                    }
                    NavigationLink {
                        AppLockSettingsView()
                    } label: {
                        Label("本地密码锁", systemImage: "lock")
                    }
                }

                Section("其他") {
                    NavigationLink {
                        BookmarkListView()
                    } label: {
                        Label("书签", systemImage: "bookmark")
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
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("关于", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("我的")
        }
    }
}
