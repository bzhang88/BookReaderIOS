import SwiftUI
import RuleEngine

struct RegexTesterView: View {
    /// Pre-fills the pattern field -- lets `ReplaceRuleEditView`'s "正则测试" link open straight
    /// into testing whatever regex is already typed there, instead of a blank tester the user has
    /// to retype into. Real usage feedback (a Legado-comparison pass): Legado's own replace-rule
    /// editor has this exact link (`menu_regex_test`); this standalone tester existed already but
    /// wasn't reachable from the one place it'd actually get used.
    var initialPattern: String = ""

    @State private var pattern: String
    @State private var text = ""
    @State private var caseInsensitive = false
    @State private var dotMatchesNewlines = false

    init(initialPattern: String = "") {
        self.initialPattern = initialPattern
        _pattern = State(initialValue: initialPattern)
    }

    private var result: Result<[RegexTester.Match], RegexTester.TestError>? {
        guard !pattern.isEmpty else { return nil }
        return RegexTester.test(
            pattern: pattern, text: text,
            caseInsensitive: caseInsensitive, dotMatchesNewlines: dotMatchesNewlines
        )
    }

    var body: some View {
        Form {
            Section("正则表达式") {
                TextField("例如 (\\d+)-(\\d+)", text: $pattern)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Toggle("忽略大小写", isOn: $caseInsensitive)
                Toggle(". 匹配换行符", isOn: $dotMatchesNewlines)
            }

            Section("测试文本") {
                TextEditor(text: $text)
                    .frame(minHeight: 120)
                    .font(.system(.body, design: .monospaced))
            }

            Section("匹配结果") {
                if let result {
                    switch result {
                    case .failure:
                        Label("正则表达式无效", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    case .success(let matches) where matches.isEmpty:
                        Text("没有匹配到任何内容").foregroundStyle(.secondary)
                    case .success(let matches):
                        Text("共 \(matches.count) 处匹配").font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(matches.enumerated()), id: \.offset) { index, match in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("#\(index + 1) \(match.matchedText)")
                                    .font(.system(.body, design: .monospaced))
                                if !match.groups.isEmpty {
                                    ForEach(Array(match.groups.enumerated()), id: \.offset) { groupIndex, group in
                                        Text("分组 \(groupIndex + 1): \(group ?? "(未匹配)")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text("输入正则表达式后开始匹配").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("正则测试器")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { RegexTesterView() }
}
