import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                    Text("拾光")
                        .font(.title2.bold())
                    Text("版本 \(version) (\(build))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .listRowBackground(Color.clear)

            Section("关于") {
                Text("一个从零开始写的书源阅读器，兼容 Legado 的书源规则格式。整个项目从 Windows 上开发、通过云端 macOS 编译，是一个学习 iOS 开发的个人项目。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}
