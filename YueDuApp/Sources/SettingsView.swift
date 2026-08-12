import SwiftUI

/// "我的" tab -- doubles as the settings hub, matching Legado's own bottom-nav "我的" tab (its
/// `MyFragment`, a flat `PreferenceScreen`). Section layout mirrors what was found reading
/// `Legado_Max`'s real `pref_main.xml`: a few rule-management screens ungrouped at the top
/// (书源管理 first, exactly like Legado puts book-source management as its very first row), then
/// titled "设置"/"其他" groups, then an untitled "关于" group at the bottom. Our own feature set
/// doesn't map 1:1 onto Legado's exact row list (extra items like 高亮规则/分组规则 that Legado
/// doesn't have) -- the *grouping pattern* is what's being matched, not a literal row-for-row copy.
struct SettingsView: View {
    @AppStorage(ReaderSettingsKey.appFontScale) private var appFontScale: AppFontScale = .standard
    @AppStorage(ReaderSettingsKey.appAppearanceMode) private var appAppearanceMode: AppAppearanceMode = .system
    @AppStorage(ReaderSettingsKey.appAccentColorHex) private var appAccentColorHex: String = ""

    var body: some View {
        NavigationStack {
            List {
                // 跟随系统/浅色/深色 for the *whole app*, not just the reader -- real usage feedback
                // was that the reader's own day/night theme could end up looking nothing like every
                // other screen, which read as jarring. Picking 深色/浅色 here forces every screen
                // (including a reader left on "跟随系统") to match; see `YueDuApp.swift`'s
                // `.preferredColorScheme` doc comment for the mechanism.
                Section {
                    Picker(selection: $appAppearanceMode) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    } label: {
                        Label("外观模式", systemImage: "circle.lefthalf.filled")
                    }
                    // Real usage feedback: 浅色/深色 alone still only felt like "2 fixed colors, not
                    // a color I actually chose." `.tint` is the real per-app "pick any color" lever
                    // (every standard control already respects it for its own accent) -- separate
                    // from light/dark, which iOS's system chrome genuinely only has 2 real states
                    // for, no continuous dial.
                    ColorPicker(selection: Binding(
                        get: { Color(hex: appAccentColorHex) ?? .accentColor },
                        set: { appAccentColorHex = $0.toHex() }
                    )) {
                        Label("主题强调色", systemImage: "paintpalette")
                    }
                    if !appAccentColorHex.isEmpty {
                        Button("恢复默认颜色", role: .destructive) { appAccentColorHex = "" }
                    }
                    Picker(selection: $appFontScale) {
                        ForEach(AppFontScale.allCases) { scale in
                            Text(scale.displayName).tag(scale)
                        }
                    } label: {
                        Label("App 字体大小", systemImage: "textformat.size")
                    }
                } header: {
                    Text("外观")
                }

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
                        WebSearchEngineListView()
                    } label: {
                        Label("搜索引擎", systemImage: "globe")
                    }
                    NavigationLink {
                        HttpTTSEngineListView()
                    } label: {
                        Label("自定义朗读引擎", systemImage: "waveform")
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
                    NavigationLink {
                        CoverGalleryManagementView()
                    } label: {
                        Label("封面相册", systemImage: "photo.on.rectangle")
                    }
                    NavigationLink {
                        DeveloperToolsView()
                    } label: {
                        Label("开发者工具箱", systemImage: "hammer")
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
