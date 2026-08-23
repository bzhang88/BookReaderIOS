import SwiftUI

/// Small sheet for the "从网址导入" flow -- lets the user paste a direct link to a book-source JSON
/// file instead of only being able to pick a file already downloaded to the device. Just collects
/// and validates the URL text; the actual fetch+decode+import happens in the caller (`onImport`),
/// which already owns the book-source store and existing file-import decoding logic.
///
/// `onImport` returns whether the import actually succeeded -- real bug found comparing against
/// Legado: this sheet used to always call `dismiss()` right after `onImport` returned, regardless
/// of whether it threw/failed internally, so a bad URL's error message ended up surfacing behind an
/// already-closed sheet instead of keeping the input visible.
struct BookSourceURLImportView: View {
    let onImport: (String) async -> Bool

    @State private var urlText = ""
    @State private var isImporting = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("书源 JSON 网址") {
                    TextField("https://...", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("从网址导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isImporting {
                        ProgressView()
                    } else {
                        Button("导入") {
                            let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                            Task {
                                isImporting = true
                                let succeeded = await onImport(trimmed)
                                isImporting = false
                                if succeeded {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
