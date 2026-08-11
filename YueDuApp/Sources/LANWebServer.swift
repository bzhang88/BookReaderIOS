import Foundation
import BookSourceModel
import WebBookOrchestrator
import Persistence
import NetworkClient
import LANWebServerCore
#if canImport(Network)
import Network
#endif

/// Legado's "Web服务" feature (a browser on the same LAN can browse the shelf and read a book) --
/// on iOS this means a hand-rolled `NWListener` HTTP server, since there's no bundled server
/// framework to reach for. The request-line parsing and response-building are pure functions
/// (`LANWebServerCore`, real `swift test` coverage on Windows); everything below is the actual
/// socket plumbing, which needs `Network.framework` -- an Apple-only API this Windows dev machine
/// cannot compile, let alone run, so unlike every other feature this session, CI compiling
/// successfully here only proves the code is syntactically/type valid, not that the socket handling
/// is behaviorally correct. That needs a real device on a real LAN, which is the one verification
/// step this specific feature is still missing as of this commit.
///
/// Scope: browsing only (shelf list -> chapter list -> chapter text), no search, no writes. Each
/// page is one fully self-contained HTML response (inline styles, no separate asset requests), so
/// one connection only ever needs to carry exactly one request/response before closing -- no
/// keep-alive or concurrent-requests-per-connection handling to get right.
#if canImport(Network)
@MainActor
final class LANWebServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var port: UInt16 = 8080
    @Published private(set) var lastError: String?

    private var listener: NWListener?
    private let shelfStore: ShelfStore
    private let bookSourceStore: BookSourceStore
    private let chapterCacheStore: ChapterCacheStore
    private let httpClient: any HTTPClient

    /// Takes just the specific stores/client it needs rather than the whole `AppEnvironment` --
    /// avoids a circular reference (`AppEnvironment` constructs this during its own `init`, before
    /// it can hand out a reference to itself) and keeps this type's real dependencies explicit.
    init(shelfStore: ShelfStore, bookSourceStore: BookSourceStore, chapterCacheStore: ChapterCacheStore, httpClient: any HTTPClient) {
        self.shelfStore = shelfStore
        self.bookSourceStore = bookSourceStore
        self.chapterCacheStore = chapterCacheStore
        self.httpClient = httpClient
    }

    func start(port: UInt16 = 8080) {
        stop()
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            lastError = "无效的端口号"
            return
        }
        do {
            let newListener = try NWListener(using: .tcp, on: endpointPort)
            newListener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.lastError = nil
                    case .failed(let error):
                        self.isRunning = false
                        self.lastError = "\(error)"
                    case .cancelled:
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }
            newListener.start(queue: .main)
            listener = newListener
            self.port = port
        } catch {
            lastError = "\(error)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    /// The device's own LAN address, best-effort -- picks the first IPv4 address on `en0` (the
    /// traditional iOS Wi-Fi interface name). Purely informational (shown in Settings so the user
    /// knows what to type into a browser); a wrong or missing guess here doesn't affect whether the
    /// server itself actually works.
    static func bestGuessLocalIPAddress() -> String? {
        var address: String?
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let firstAddr = ifaddrPointer else { return nil }
        defer { freeifaddrs(ifaddrPointer) }

        for cursor in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = cursor.pointee
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard String(cString: interface.ifa_name) == "en0" else { continue }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST
            )
            address = String(cString: hostBuffer)
            break
        }
        return address
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    /// Reads until the blank line that ends an HTTP request's headers (or gives up past a byte cap,
    /// or the connection closes/errors) -- the body is never needed since this server only ever
    /// handles GET requests with no payload.
    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { @MainActor in
                var newBuffer = buffer
                if let data { newBuffer.append(data) }

                if let headerEnd = newBuffer.range(of: Data("\r\n\r\n".utf8)) {
                    let headerText = String(data: newBuffer[..<headerEnd.lowerBound], encoding: .utf8) ?? ""
                    await self.respond(to: headerText, on: connection)
                    return
                }
                if isComplete || error != nil || newBuffer.count > 16384 {
                    connection.cancel()
                    return
                }
                self.receive(on: connection, buffer: newBuffer)
            }
        }
    }

    private func respond(to rawRequestHeaders: String, on connection: NWConnection) async {
        guard let request = SimpleHTTPRequestParser.parse(rawRequestHeaders) else {
            send(SimpleHTTPResponseBuilder.buildHTML(statusCode: 400, html: page("请求格式有误")), on: connection)
            return
        }
        let html = await renderPage(for: request)
        send(SimpleHTTPResponseBuilder.buildHTML(html: html), on: connection)
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func renderPage(for request: SimpleHTTPRequest) async -> String {
        switch request.path {
        case "/":
            return await shelfPageHTML()
        case "/book":
            guard let bookUrl = request.query["u"] else { return page("缺少书籍参数") }
            return await bookPageHTML(bookUrl: bookUrl)
        case "/chapter":
            guard let bookUrl = request.query["u"], let indexText = request.query["i"], let index = Int(indexText) else {
                return page("缺少章节参数")
            }
            return await chapterPageHTML(bookUrl: bookUrl, index: index)
        default:
            return page("没有这个页面")
        }
    }

    // MARK: - Pages

    private func shelfPageHTML() async -> String {
        let books = (try? await shelfStore.all()) ?? []
        guard !books.isEmpty else {
            return page("书架是空的")
        }
        let rows = books.map { book in
            "<li><a href=\"/book?u=\(percentEncoded(book.bookUrl))\">\(escaped(book.name))</a>"
                + "<span class=\"muted\"> \(escaped(book.author ?? ""))</span></li>"
        }.joined()
        return page("书架", body: "<ul>\(rows)</ul>")
    }

    private func bookPageHTML(bookUrl: String) async -> String {
        guard let shelfBook = (try? await shelfStore.book(bookUrl: bookUrl)) ?? nil else {
            return page("找不到这本书")
        }
        guard let source = await resolvedSource(bookSourceUrl: shelfBook.bookSourceUrl) else {
            return page("找不到这本书对应的书源")
        }
        guard let chapters = try? await TocService.fetchChapterList(
            source: source, tocURL: shelfBook.tocUrl, httpClient: httpClient
        ), !chapters.isEmpty else {
            return page("没有找到章节")
        }
        let rows = chapters.map { chapter in
            "<li><a href=\"/chapter?u=\(percentEncoded(bookUrl))&i=\(chapter.index)\">\(escaped(chapter.title))</a></li>"
        }.joined()
        return page(shelfBook.name, body: "<ul>\(rows)</ul>")
    }

    private func chapterPageHTML(bookUrl: String, index: Int) async -> String {
        guard let shelfBook = (try? await shelfStore.book(bookUrl: bookUrl)) ?? nil else {
            return page("找不到这本书")
        }
        guard let source = await resolvedSource(bookSourceUrl: shelfBook.bookSourceUrl) else {
            return page("找不到这本书对应的书源")
        }
        let text: String
        if let cached = try? await chapterCacheStore.chapter(bookUrl: bookUrl, index: index) {
            text = cached.text
        } else if let chapters = try? await TocService.fetchChapterList(
            source: source, tocURL: shelfBook.tocUrl, httpClient: httpClient
        ), chapters.indices.contains(index),
           let content = try? await ContentService.fetchContent(source: source, chapter: chapters[index], httpClient: httpClient) {
            text = content.text
        } else {
            return page("章节加载失败")
        }
        let paragraphs = text.components(separatedBy: "\n")
            .map { "<p>\(escaped($0))</p>" }
            .joined()
        return page(shelfBook.name, body: paragraphs)
    }

    private func resolvedSource(bookSourceUrl: String) async -> BookSource? {
        let sources = (try? await bookSourceStore.all()) ?? []
        return sources.first { $0.bookSourceUrl == bookSourceUrl }
    }

    // MARK: - HTML helpers

    private func page(_ title: String, body: String = "") -> String {
        """
        <!DOCTYPE html>
        <html lang="zh-CN"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escaped(title))</title>
        <style>
        body { font-family: -apple-system, sans-serif; max-width: 700px; margin: 0 auto; padding: 16px; line-height: 1.7; }
        a { color: #2563eb; text-decoration: none; }
        ul { list-style: none; padding: 0; }
        li { padding: 10px 0; border-bottom: 1px solid #eee; }
        .muted { color: #888; font-size: 0.9em; }
        p { margin: 0.8em 0; }
        </style>
        </head><body>
        <p><a href="/">← 返回书架</a></p>
        <h2>\(escaped(title))</h2>
        \(body)
        </body></html>
        """
    }

    private func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func percentEncoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    }
}
#endif
