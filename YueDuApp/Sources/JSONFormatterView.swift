import SwiftUI
import RuleEngine

struct JSONFormatterView: View {
    @State private var input = ""
    @State private var formatted: String?
    @State private var isInvalid = false

    var body: some View {
        Form {
            Section("原始 JSON") {
                TextEditor(text: $input)
                    .frame(minHeight: 140)
                    .font(.system(.caption, design: .monospaced))
                Button("格式化") { format() }
                    .disabled(input.isEmpty)
            }

            if isInvalid {
                Section {
                    Label("不是合法的 JSON", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            if let formatted {
                Section("格式化结果") {
                    Text(formatted)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("JSON 格式化器")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func format() {
        switch JSONPrettyPrinter.format(input) {
        case .success(let text):
            formatted = text
            isInvalid = false
        case .failure:
            formatted = nil
            isInvalid = true
        }
    }
}

#Preview {
    NavigationStack { JSONFormatterView() }
}
