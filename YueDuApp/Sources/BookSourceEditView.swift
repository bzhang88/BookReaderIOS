import SwiftUI
import BookSourceModel
import Persistence

/// Raw JSON rule editor for a single book source -- direct field-by-field UI for every rule
/// (search/info/toc/content, each with a dozen-plus optional string fields) isn't worth building
/// before something simpler proves out the save/validate flow; editing the same JSON shape real
/// book-source files already use also means anything written here imports identically to a file
/// pulled from a real book-source collection.
struct BookSourceEditView: View {
    let source: BookSource?

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var jsonText: String
    @State private var errorMessage: String?

    init(source: BookSource?) {
        self.source = source
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let source, let data = try? encoder.encode(source), let text = String(data: data, encoding: .utf8) {
            _jsonText = State(initialValue: text)
        } else {
            _jsonText = State(initialValue: BookSourceEditView.blankTemplate)
        }
    }

    private static let blankTemplate = """
    {
      "bookSourceUrl" : "https://example.com",
      "bookSourceName" : "新书源",
      "bookSourceType" : 0,
      "enabled" : true,
      "searchUrl" : "",
      "ruleSearch" : {},
      "ruleBookInfo" : {},
      "ruleToc" : {},
      "ruleContent" : {}
    }
    """

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }
                TextEditor(text: $jsonText)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 8)
            }
            .navigationTitle(source == nil ? "新建书源" : "编辑书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
        }
    }

    private func save() {
        guard let data = jsonText.data(using: .utf8) else {
            errorMessage = "无法编码文本"
            return
        }
        do {
            let decoded = try JSONDecoder().decode(BookSource.self, from: data)
            Task {
                // Real bug found comparing against Legado: `importSources` upserts strictly by the
                // *new* bookSourceUrl, so editing an existing source and changing its URL here used
                // to leave the old entry behind as an orphaned duplicate instead of renaming it in
                // place. Legado's own BookSourceEditViewModel.save() explicitly deletes the old URL
                // first when it changed -- same fix here.
                if let source, source.bookSourceUrl != decoded.bookSourceUrl {
                    try? await env.bookSourceStore.remove(bookSourceUrl: source.bookSourceUrl)
                }
                try? await env.bookSourceStore.importSources([decoded])
                dismiss()
            }
        } catch {
            errorMessage = "JSON 解析失败: \(error)"
        }
    }
}
