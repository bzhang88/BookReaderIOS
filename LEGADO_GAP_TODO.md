# Legado 对照清单 / TODO

对照 Legado_Max 真机源码重新审计后的完整功能差距清单（2026-08-22 由 9 个并行调研 agent 生成）。按严重程度分四档，完成一项就把前面的 `[ ]` 改成 `[x]`（具体改动看 git log，每项对应的 commit 里都有详细说明）。

网页版（含更好的排版和筛选）：https://claude.ai/code/artifact/996bf1ea-18a9-4554-8088-eb8e4ce5fdb5

---

## P0 · 安全 / 严重问题（4 项）

- [x] **[局域网 Web 服务] 密码留空时鉴权静默失效** —— UI 显示已开启鉴权，实际因空字符串被当 nil 处理而完全不设防。`LANWebServiceView.swift:87-91`, `LANWebServer.swift:56-58`, `LANWebAuth.swift:15-18`
- [x] **[换源] 换源前不检查书源类型（文本/音频/漫画）** —— 可能让文本阅读器渲染错误内容类型。`ChangeSourceView.swift:189-206`, `ReaderView.swift:1412-1481`, `ShelfView.swift:603-623`, `BookDetailView.swift:551-586`
- [x] **[书架] 批量删除没有二次确认** —— 误触无法挽回。`ShelfView.swift:265`
- [x] **[书源管理] 改书源网址后产生重复条目而不是替换旧的** —— `BookSourceEditView.swift:72-86`, `BookSourceStore.swift:27-46`

---

## P1 · 明确的逻辑 / 交互 Bug（18 项，纯 Swift，Windows 可修可测）

- [x] **[全局搜索] 取消的搜索任务仍会把"搜索中"状态设为 false** —— `GlobalSearchView.swift:314-330`
- [x] **[全局搜索] 默认排序按来源数量而非相关度** —— 不符合 Legado 真实排序语义。`GlobalSearchView.swift:30`, `GroupedSearchResult.swift:46-48`
- [x] **[全局搜索] "书架同名书籍"提示只在首次搜索前出现，之后永久消失** —— `GlobalSearchView.swift:47-49,307`
- [x] **[目录 TOC] 缓存图标逻辑和阅读器内目录抽屉相反，自相矛盾** —— `TocView.swift:84-88`, `ReaderTocDrawer.swift:160-164`
- [x] **[目录 TOC] "倒序"只是界面显示，不持久化** —— `TocView.swift:44,62,110-113`
- [x] **[目录 TOC] 点击"卷"标题会被当成章节直接打开阅读器** —— 真实行为 bug。`TocView.swift`, `ReaderTocDrawer.swift`, `ContentService.swift:34-36`
- [x] **[换源] "完全匹配"用严格字符串相等，会漏掉真正同一本书的源** —— `ChangeSourceView.swift:208-213`
- [x] **[换源] 阅读器内换源固定传空作者，弱化同名书过滤** —— `ReaderView.swift:791,800`
- [x] **[换源] 批量换源不让用户选目标源，可能分散换到不同源** —— `ShelfView.swift:631-668`
- [x] **[书架] "检查更新"扫描后不刷新"最新章节"文字** —— `ShelfView.swift:481-514`, `ShelfStore.swift:78-83`
- [x] **[书籍详情] 换源失败时静默吞错误，界面显示"新源名字+旧书籍信息"错配状态** —— `BookDetailView.swift:551-587`
- [x] **[书籍详情] 上述失败场景下"上次读到"这行显示错误数据** —— `BookDetailView.swift:273-274`
- [x] **[朗读 TTS] 不会跳过纯标点/空白段落** —— `ReadAloudController.swift:94-98`, `HttpReadAloudController.swift:99-103`
- [x] **[阅读器] 目录抽屉里"全文搜索"tab 没有正则开关，和独立搜索页面不一致** —— `ReaderTocDrawer.swift:213-256`, `ChapterContentSearchView.swift:22`
- [x] **[本地书籍] 默认分章正则丢失超过 40 字的副标题章节**（已实测复现）—— `TxtChapterSplitter.swift:22`
- [x] **[书源管理] 词典规则 showRule 留空应合法，却被禁止保存** —— `DictRuleListView.swift:142-143`, `DictLookupService.swift:16-30`
- [x] **[书源管理] 导入书源失败时输入框仍会自动关闭** —— `BookSourceURLImportView.swift:34-41`
- [x] **[备份/WebDAV] 路径含中文或空格导致请求失败**（未做 URL 编码，中文小说文件名几乎必触发）—— `WebDAVClient.swift:103-107`, `WebDAVBookImportView.swift:71-74`, `URLSessionHTTPClient.swift:13`

---

## P2 · 缺失功能（45+ 项，工作量中等，纯 Swift/SwiftUI，不依赖 Xcode）

### 书架
- [x] 批量启用/禁用自动更新
- [x] 全选/反选（选择模式下）
- [x] 批量清除已选书籍的缓存
- [ ] 多分组归属（目前一本书只能属于一个分组）—— `ShelfBook.swift:18`, `ShelfStore.swift:40-48`
- [ ] 书架显示设置（分组筛选标签页等）
- [ ] 检查更新时逐本显示进度指示
- [ ] 通过粘贴网址直接添加书籍
- [x] 书单导入支持本地文件选择 —— `ShelfListImportExportView.swift:42-61`

### 书籍详情
- [ ] 可编辑书名/作者/简介覆盖值
- [x] 移出书架前二次确认
- [x] 无论是否在架都显示"最新章节"
- [x] 点击来源名跳转编辑该书源
- [x] 点击书名/作者/分类跳转搜索
- [ ] 分享/复制书籍链接、目录链接
- [ ] 置顶书籍

### 目录 TOC
- [ ] 书签 tab（含搜索/筛选/导出）
- [ ] 卷/分卷折叠展示，带当前卷高亮
- [ ] 拆分长章节开关
- [ ] 章节字数显示（数据层也没提取）—— `BookChapter.swift:3-30`
- [x] VIP/付费章节锁图标（数据已取未渲染）—— `BookChapter.swift:8-9`, `TocService.swift:100-101`
- [ ] 标题净化规则应用开关
- [x] 跳到顶部/底部
- [x] 当前章节位置读数

### 阅读器 / 朗读 / 高亮
- [x] 朗读（TTS）睡眠定时器（有声书已有，可照搬）—— `AudiobookPlayerController.swift:81-103`
- [x] 书签列表搜索
- [ ] 高亮规则分组管理 + 作用范围（标题/正文）
- [x] 有声书锁屏控制中心加上一曲/下一曲/拖动进度 —— `AudiobookPlayerController.swift:154-174`
- [ ] 有声书跳过片头片尾设置
- [ ] 有声书循环/随机播放模式
- [ ] 漫画阅读进度恢复（目前总回到第一页）—— `MangaReaderView.swift:136-138`

### 换源
- [ ] 兼容性徽章接入换源界面 —— `ChangeSourceView.swift:86-90,180-184`
- [ ] 章节换源展示真实目录、手动选择
- [ ] 搜索并发限制 —— `MultiSourceSearchService.swift:26-48`

### 书源管理 / 发现
- [ ] 书源列表搜索/筛选框
- [ ] 排序选项
- [ ] 发现页"全部加入书架"和跳页
- [ ] 书源检测补上域名可达性和发现页检测
- [ ] 调试页支持单阶段调试
- [ ] 清除单个书源的 Cookie

### RSS
- [ ] 模型偏单薄：抓取规则、登录、分类、收藏、已读状态 —— `RssSource.swift:5-19`, `RssFeedService.swift:6-9`

### 备份 / 恢复
- [ ] 补上词典规则、自定义搜索引擎、自定义朗读引擎、封面相册、书架分组这 5 类数据 —— `BackupCategory.swift:8-9`

### 本地书籍导入
- [ ] EPUB / PDF 导入（目前完全没有，建议优先）—— `LocalBookListView.swift:94`
- [ ] UTF-16 编码自动检测 —— `CharsetDetector.swift:46-54`
- [ ] 重复导入检测 —— `LocalBookListView.swift:150-174`
- [ ] 多文件批量导入 —— `LocalBookListView.swift:94`
- [ ] 导入结果预览界面

---

## P3 · 工作量较大 / 建议先用 CI 验证 / 需要真机（6 项）

- [ ] **[净化规则] 正则超时保护（ReDoS 防护）** —— 设计需谨慎。`ReplaceRuleApplier.swift`
- [ ] **[本地书籍] 本地书库每次翻页都整份重写 JSON** —— 性能问题，随书库增长越来越慢。`LocalBookStore.swift:14-38`, `LocalReaderView.swift:449,694`
- [ ] **[应用锁] 切后台生成多任务预览截图的时间窗口疑似有泄露风险** —— 需要真机验证。`RootView.swift:116-119`
- [ ] **[封面相册] 跟 Legado 真正的封面相册功能差距较大**（多组管理+ZIP导入导出+默认图池）—— `CoverGalleryManagementView.swift`
- [ ] **[书源管理] 批量导入缺少预览/勾选界面** —— `SourceLibraryView.swift:337-370`, `SourceSubscriptionListView.swift:150-163`
- [ ] **[换源] 体验锦上添花项**（进度带书源名/结果缓存/停止按钮/评分排序）—— 低优先级

---

## 明确不在范围内（从会话开始就排除，Windows 无 Xcode/真机无法验证）

- JS 规则引擎（`@js:`/`<js>`）执行
- 非文本类书源（音频以外的）
- RSS 模型重建的完整规则引擎抓取部分（上面 P2 里的"模型偏单薄"是数据模型层面，可以做；真正的抓取规则执行引擎不做）
- 真正的文本框选（UITextView 长按选中部分文字）
- 惯性滑动物理重写
- 自定义字体导入
- 对用户 463 个书源文件的全量联网体检
