import SwiftUI

/// Entry point for a small "开发者工具箱" -- confirmed against `Legado_Max` that the real one is a
/// much bigger grab-bag (curl generator, ping, floating debug ball, module status panel, network
/// request history, ...). This deliberately only picks the 2-3 tools most useful while actually
/// authoring/debugging book-source rules -- a regex tester for `replaceRegex`/`##pattern##`
/// fields, a generic HTTP request debugger, and a JSON pretty-printer for eyeballing a JSON-mode
/// source's raw response before writing a JSONPath rule against it.
struct DeveloperToolsView: View {
    var body: some View {
        List {
            NavigationLink {
                RegexTesterView()
            } label: {
                Label("正则测试器", systemImage: "textformat.abc")
            }
            NavigationLink {
                HttpDebuggerView()
            } label: {
                Label("HTTP 调试器", systemImage: "network")
            }
            NavigationLink {
                JSONFormatterView()
            } label: {
                Label("JSON 格式化器", systemImage: "curlybraces")
            }
        }
        .navigationTitle("开发者工具箱")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { DeveloperToolsView() }
}
