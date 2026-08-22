import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import Persistence
import NetworkClient

/// Portable "书单" (reading list) import/export -- lets a list of book titles move between
/// devices/installs without a full WebDAV backup, matching Legado_Max's own "导入书单"/"导出书单"
/// menu items exactly (same `[{"name":...,"author":...,"intro":...}]` JSON shape, same "paste a
/// URL or paste JSON directly" input). Import re-resolves each title against *this* device's own
/// configured sources (via `ShelfListImporter`) rather than assuming the exporting side's exact
/// source URLs exist here too -- the whole point of a portable list is that it survives moving to
/// a device with a different set of book sources.
struct ShelfListImportExportView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var inputText = ""
    @State private var isImporting = false
    @State private var importSummary: String?
    @State private var exportItems: [Any] = []
    @State private var isShowingExportSheet = false
    @State private var isExporting = false

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await exportShelf() }
                } label: {
                    if isExporting {
                        ProgressView()
                    } else {
                        Text("导出书架为书单")
                    }
                }
                .disabled(isExporting)
            } header: {
                Text("导出")
            } footer: {
                Text("导出当前书架的书名/作者/简介列表，可以分享给别人或在另一台设备导入——不包含具体书源和阅读进度。")
            }

            Section {
                TextField("书单地址（URL）或粘贴 JSON 内容", text: $inputText, axis: .vertical)
                    .lineLimit(4...10)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button {
                    Task { await importList() }
                } label: {
                    if isImporting {
                        ProgressView()
                    } else {
                        Text("开始导入")
                    }
                }
                .disabled(isImporting || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("导入")
            } footer: {
                Text("支持粘贴一个书单地址，或者直接粘贴 JSON 内容（格式：[{\"name\":\"书名\",\"author\":\"作者\"}]）。会在已启用的书源里搜索匹配，找不到精确匹配的书会在结果里列出来，已经在书架里的书会被跳过。")
            }
        }
        .navigationTitle("书单导入/导出")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingExportSheet) {
            ShareSheet(items: exportItems)
        }
        .alert("导入结果", isPresented: Binding(
            get: { importSummary != nil }, set: { if !$0 { importSummary = nil } }
        )) {
            Button("好") { importSummary = nil }
        } message: {
            Text(importSummary ?? "")
        }
    }

    private func exportShelf() async {
        isExporting = true
        defer { isExporting = false }
        let books = (try? await env.shelfStore.all()) ?? []
        guard !books.isEmpty else { return }
        let entries = books.map { ShelfListEntry(name: $0.name, author: $0.author, intro: $0.intro) }
        let json = ShelfListFormat.encode(entries)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("书单-\(books.count)本.json")
        guard (try? json.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        exportItems = [url]
        isShowingExportSheet = true
    }

    private func importList() async {
        isImporting = true
        defer { isImporting = false }
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let text: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            guard let response = try? await env.httpClient.fetch(HTTPRequest(url: trimmed)) else {
                importSummary = "书单地址请求失败"
                return
            }
            text = response.body
        } else {
            text = trimmed
        }
        guard let entries = ShelfListFormat.decode(text) else {
            importSummary = "格式不对，请确认是书单 JSON 内容或者一个有效地址"
            return
        }
        guard !entries.isEmpty else {
            importSummary = "书单是空的"
            return
        }

        let existingBooks = (try? await env.shelfStore.all()) ?? []
        let existingKeys = Set(existingBooks.map { existenceKey(name: $0.name, author: $0.author) })
        let newEntries = entries.filter { !existingKeys.contains(existenceKey(name: $0.name, author: $0.author)) }
        let skippedAsExisting = entries.count - newEntries.count

        let sources = (try? await env.bookSourceStore.enabled()) ?? []
        let httpClient = env.httpClient
        let (matches, unmatched) = await ShelfListImporter.resolve(entries: newEntries, sources: sources, httpClient: httpClient)

        var addedCount = 0
        for match in matches {
            let bookInfo = try? await BookInfoService.fetchBookInfo(
                source: match.source, bookURL: match.result.bookUrl, httpClient: httpClient
            )
            let newBook = ShelfBook(
                bookSourceUrl: match.source.bookSourceUrl,
                bookUrl: match.result.bookUrl,
                name: bookInfo?.name ?? match.result.name,
                author: bookInfo?.author ?? match.result.author,
                coverUrl: bookInfo?.coverUrl ?? match.result.coverUrl,
                intro: bookInfo?.intro ?? match.result.intro,
                tocUrl: bookInfo?.tocUrl ?? match.result.bookUrl,
                lastChapterTitle: bookInfo?.lastChapter ?? match.result.lastChapter
            )
            try? await env.shelfStore.addOrUpdate(newBook)
            addedCount += 1
        }

        var summary = "已添加 \(addedCount) 本"
        if skippedAsExisting > 0 { summary += "，\(skippedAsExisting) 本已在书架里" }
        if !unmatched.isEmpty {
            let names = unmatched.prefix(5).map(\.name).joined(separator: "、")
            summary += "，\(unmatched.count) 本没有找到匹配书源：\(names)" + (unmatched.count > 5 ? "…" : "")
        }
        importSummary = summary
        inputText = ""
    }

    private func existenceKey(name: String, author: String?) -> String {
        "\(name)|\(author ?? "")"
    }
}
