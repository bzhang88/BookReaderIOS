import SwiftUI
import NetworkClient

/// Generic request/response inspector -- not tied to a book source's rules (that's
/// `SourceDebugView`), just a plain "type a URL, pick a method, see the raw response" tool for
/// poking at an API by hand while writing a new source.
struct HttpDebuggerView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var urlString = ""
    @State private var method = "GET"
    @State private var headersText = ""
    @State private var bodyText = ""
    @State private var isSending = false
    @State private var response: HTTPResponse?
    @State private var errorMessage: String?

    private let methods = ["GET", "POST", "PUT", "DELETE"]

    var body: some View {
        Form {
            Section("请求") {
                TextField("https://example.com/api", text: $urlString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Picker("方法", selection: $method) {
                    ForEach(methods, id: \.self) { Text($0).tag($0) }
                }
                VStack(alignment: .leading) {
                    Text("请求头（每行一个，格式 Key: Value）").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $headersText)
                        .frame(minHeight: 60)
                        .font(.system(.caption, design: .monospaced))
                }
                if method == "POST" || method == "PUT" {
                    VStack(alignment: .leading) {
                        Text("请求体").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $bodyText)
                            .frame(minHeight: 80)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView()
                    } else {
                        Text("发送请求")
                    }
                }
                .disabled(isSending || urlString.isEmpty)
            }

            if let errorMessage {
                Section("错误") {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
            }

            if let response {
                Section("响应") {
                    LabeledContent("状态码", value: "\(response.statusCode)")
                    LabeledContent("最终地址", value: response.finalURL)
                        .font(.caption)
                }
                if !response.headers.isEmpty {
                    Section("响应头") {
                        ForEach(Array(response.headers.keys.sorted()), id: \.self) { key in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key).font(.caption).bold()
                                Text(response.headers[key] ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("响应体") {
                    Text(response.body)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("HTTP 调试器")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func parsedHeaders() -> [String: String] {
        var headers: [String: String] = [:]
        for line in headersText.split(separator: "\n") {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            headers[key] = value
        }
        return headers
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        response = nil
        do {
            let body = (method == "POST" || method == "PUT") && !bodyText.isEmpty
                ? bodyText.data(using: .utf8) : nil
            let request = HTTPRequest(
                url: urlString, method: method, headers: parsedHeaders(), body: body
            )
            response = try await env.httpClient.fetch(request)
        } catch {
            errorMessage = "\(error)"
        }
        isSending = false
    }
}

#Preview {
    NavigationStack { HttpDebuggerView() }
        .environmentObject(AppEnvironment())
}
