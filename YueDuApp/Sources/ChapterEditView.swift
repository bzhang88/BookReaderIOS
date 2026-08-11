import SwiftUI
import BookSourceModel
import WebBookOrchestrator
import Persistence
import NetworkClient

/// Direct in-place editing of the chapter currently on screen (fix a typo, remove a stray line the
/// purification rules didn't catch, etc.), with a real "还原原文" -- confirmed against Legado_Max's
/// `ContentEditDialog` that reverting means re-fetching from the source, not undoing to some
/// separately-stored original copy. This app doesn't need a second storage slot for "the original"
/// either: an edit is just a `chapterCacheStore.save(...)` overwrite, and reverting is just fetching
/// fresh from `ContentService` and overwriting the cache again with that -- no new schema.
struct ChapterEditView: View {
    let source: BookSource
    let chapter: BookChapter
    let bookUrl: String
    let currentText: String
    let onSaved: (String) -> Void

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var editedText: String
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(source: BookSource, chapter: BookChapter, bookUrl: String, currentText: String, onSaved: @escaping (String) -> Void) {
        self.source = source
        self.chapter = chapter
        self.bookUrl = bookUrl
        self.currentText = currentText
        self.onSaved = onSaved
        _editedText = State(initialValue: currentText)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }
                TextEditor(text: $editedText)
                    .font(.body)
                    .padding(4)
            }
            .navigationTitle(chapter.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if isWorking {
                        ProgressView()
                    }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button("还原原文") { Task { await revert() } }
                        .disabled(isWorking)
                    Button("保存") { Task { await save() } }
                        .disabled(isWorking || editedText.isEmpty)
                }
            }
        }
    }

    private func save() async {
        isWorking = true
        errorMessage = nil
        do {
            try await env.chapterCacheStore.save(bookUrl: bookUrl, index: chapter.index, content: ChapterContent(text: editedText))
            onSaved(editedText)
            dismiss()
        } catch {
            errorMessage = "保存失败: \(error)"
        }
        isWorking = false
    }

    /// Re-fetches the chapter straight from the source (bypassing any cache) and overwrites both
    /// the cache and this editor's text with that fresh copy -- the same "original" a first-ever
    /// read of this chapter would have shown, not a snapshot frozen at whenever editing began.
    private func revert() async {
        isWorking = true
        errorMessage = nil
        do {
            let fresh = try await ContentService.fetchContent(source: source, chapter: chapter, httpClient: env.httpClient)
            try await env.chapterCacheStore.save(bookUrl: bookUrl, index: chapter.index, content: fresh)
            editedText = fresh.text
            onSaved(fresh.text)
        } catch {
            errorMessage = "还原失败: \(error)"
        }
        isWorking = false
    }
}
