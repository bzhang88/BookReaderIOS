import SwiftUI
import BookSourceModel
import WebBookOrchestrator

/// Carries the state needed to present `ChapterSourcePickerView` -- `Identifiable` so `ReaderView`
/// can drive it via `.sheet(item:)`. Kept as its own file (not inline in `ReaderView.swift`, already
/// split into `stage1`/`stage2` to stay under the real `xcodebuild` type-checker's complexity budget
/// -- see that file's own doc comment) so this addition can't push that budget over again.
struct ChapterSourcePickerContext: Identifiable {
    let id = UUID()
    let source: BookSource
    let chapters: [BookChapter]
    /// The chapter `switchChapterSource` already auto-matched by title (falling back to the same
    /// index) -- pre-highlighted so the common case is still just "tap the highlighted row," while
    /// still letting the user browse the real fetched table of contents and pick a different chapter
    /// when the auto-match guessed wrong (different chapter splitting/numbering between sources).
    let highlightedIndex: Int?
    let originalIndex: Int
}

/// Real gap found comparing against Legado's own `ChangeChapterSourceDialog.openToc`/`clickChapter`:
/// single-chapter 换源 used to silently commit whatever `switchChapterSource` auto-matched (by title,
/// or the same index as a last resort) with no way to see the alternate source's real table of
/// contents or override a wrong guess. This shows that real, freshly-fetched TOC and lets the user
/// tap any chapter to use its content instead.
struct ChapterSourcePickerView: View {
    let context: ChapterSourcePickerContext
    let onPick: (BookChapter) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isCommitting = false

    var body: some View {
        NavigationStack {
            List(context.chapters) { chapter in
                chapterRow(chapter)
            }
            .overlay {
                if isCommitting {
                    ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .navigationTitle(context.source.bookSourceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func chapterRow(_ chapter: BookChapter) -> some View {
        let isHighlighted = chapter.index == context.highlightedIndex
        Button {
            commit(chapter)
        } label: {
            HStack {
                Text(chapter.title)
                    .foregroundStyle(isHighlighted ? Color.accentColor : .primary)
                Spacer()
                if chapter.isVip && !chapter.isPay {
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.orange)
                }
                if isHighlighted {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
        }
        .disabled(isCommitting)
    }

    private func commit(_ chapter: BookChapter) {
        isCommitting = true
        Task {
            await onPick(chapter)
            isCommitting = false
            dismiss()
        }
    }
}
