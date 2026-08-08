import SwiftUI
import RuleEngine

struct ContentView: View {
    @State private var proofOfLifeText = "Running rule engine..."

    var body: some View {
        VStack(spacing: 16) {
            Text("阅读 YueDu")
                .font(.largeTitle.bold())
            Text("Phase 0: 工具链打通中")
                .foregroundStyle(.secondary)
            Divider()
            Text("RuleEngine 抽取结果:")
                .font(.headline)
            Text(proofOfLifeText)
                .font(.body.monospaced())
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .task {
            proofOfLifeText = await runProofOfLife()
        }
    }

    /// Runs a real (tiny) BookSourceKit rule extraction on-device -- proof that the package
    /// actually links and executes inside the app, not just in `swift test`.
    private func runProofOfLife() async -> String {
        let html = "<div class=\"greeting\">Hello from BookSourceKit!</div>"
        do {
            let content = try RuleContent.parse(body: html, baseURL: "https://example.com")
            let result = try RuleEngine.extractString("@css:.greeting@text", from: content)
            return result ?? "(空结果)"
        } catch {
            return "错误: \(error)"
        }
    }
}

#Preview {
    ContentView()
}
