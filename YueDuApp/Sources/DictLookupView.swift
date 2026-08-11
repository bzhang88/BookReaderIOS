import SwiftUI
import BookSourceModel
import WebBookOrchestrator

/// Word lookup, reachable from the reader toolbar. Real Legado triggers this from long-pressing a
/// word directly in the flowing text -- not done that way here: this app's reader renders
/// paragraphs as plain SwiftUI `Text`, which has no public hook (as of this app's iOS 17 deployment
/// target) to inject a custom "查词" action into `.textSelection(.enabled)`'s native selection
/// popup without rewriting paragraph rendering onto a `UITextView` bridge -- a much bigger, riskier
/// change than this increment's worth. This instead offers the same underlying value (look up a
/// word against a user-configured dictionary rule) through an explicit type-or-paste panel, which
/// works with the text-selection Copy action already available on selectable paragraphs.
struct DictLookupView: View {
    /// Pre-fills the query field when opened with a specific word already in mind (not currently
    /// wired to an in-place text selection anywhere -- see the type-level doc comment -- but keeps
    /// this view ready for that hookup later without changing its interface).
    var initialWord: String = ""

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var rules: [DictRule] = []
    @State private var selectedRuleID: String?
    @State private var word: String = ""
    @State private var isLoading = false
    @State private var result: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if rules.isEmpty {
                    ContentUnavailableView(
                        "还没有词典规则", systemImage: "character.book.closed",
                        description: Text("先在\u{201C}我的\u{201D}里添加一条词典规则")
                    )
                } else {
                    Section {
                        if rules.count > 1 {
                            Picker("词典", selection: $selectedRuleID) {
                                ForEach(rules) { rule in
                                    Text(rule.name).tag(Optional(rule.id))
                                }
                            }
                        }
                        HStack {
                            TextField("要查的词", text: $word)
                                .autocorrectionDisabled()
                            Button("查询") { Task { await lookup() } }
                                .disabled(word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                        }
                    }
                    Section("释义") {
                        if isLoading {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else if let result {
                            Text(result)
                        } else if let errorMessage {
                            Text(errorMessage).foregroundStyle(Color.red)
                        } else {
                            Text("输入词后点\u{201C}查询\u{201D}").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("查词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                word = initialWord
                await loadRules()
                if !initialWord.isEmpty {
                    await lookup()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func loadRules() async {
        let all = (try? await env.dictRuleStore.all()) ?? []
        rules = all.filter(\.enabled)
        selectedRuleID = rules.first?.id
    }

    private func lookup() async {
        guard let rule = rules.first(where: { $0.id == selectedRuleID }) else { return }
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        result = nil
        do {
            result = try await DictLookupService.lookup(rule: rule, word: trimmed, httpClient: env.httpClient)
        } catch {
            errorMessage = "查询失败: \(error)"
        }
        isLoading = false
    }
}
