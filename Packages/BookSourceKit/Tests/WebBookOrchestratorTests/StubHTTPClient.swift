import Foundation
import NetworkClient

/// A deterministic, offline `HTTPClient` for orchestrator tests -- keyed by exact request URL.
actor StubHTTPClient: HTTPClient {
    private let responses: [String: String]
    private(set) var requestedURLs: [String] = []

    init(responses: [String: String]) {
        self.responses = responses
    }

    func fetch(_ request: HTTPRequest) async throws -> HTTPResponse {
        requestedURLs.append(request.url)
        guard let body = responses[request.url] else {
            throw HTTPClientError.invalidURL(request.url)
        }
        return HTTPResponse(finalURL: request.url, statusCode: 200, body: body)
    }
}
