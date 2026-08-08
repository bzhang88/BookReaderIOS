import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Real network implementation. `URLSession`'s async API lives in a separate
/// `FoundationNetworking` module on non-Apple platforms (Linux/Windows) — the `canImport` guard
/// is what lets this same file build for both the real iOS target and local Windows development.
public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func fetch(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let url = URL(string: request.url) else {
            throw HTTPClientError.invalidURL(request.url)
        }

        var urlRequest = URLRequest(url: url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.httpBody = request.body

        // `request.timeout` already bounds urlRequest.timeoutInterval; this manual race is a
        // backstop for when that mechanism doesn't fire (see RequestTimeout.swift), so it's given
        // slack above the "real" timeout rather than competing with it under normal conditions.
        let (data, response) = try await withRequestTimeout(seconds: request.timeout + 5) {
            try await URLSession.shared.data(for: urlRequest)
        }
        let httpResponse = response as? HTTPURLResponse
        let finalURL = response.url?.absoluteString ?? request.url

        let contentTypeHeader = httpResponse?.value(forHTTPHeaderField: "Content-Type")
        let charset = CharsetDetector.detect(contentTypeHeader: contentTypeHeader, rawBytes: data)
        let body = CharsetDetector.decode(data, charset: charset)

        return HTTPResponse(
            finalURL: finalURL,
            statusCode: httpResponse?.statusCode ?? 0,
            body: body
        )
    }
}
