import Foundation
import NetworkClient

/// Captures the exact request it received (so tests can assert on URL/headers/body) and returns a
/// fixed, configurable response -- `AIServiceTests`' own stub rather than reusing
/// `WebBookOrchestratorTests`' `StubHTTPClient`, since that one always answers 200 and doesn't
/// expose the request it was given, both of which these tests need (verifying the Authorization
/// header, and simulating a non-2xx provider error response).
actor StubAIHTTPClient: HTTPClient {
    private let statusCode: Int
    private let body: String
    private(set) var lastRequest: HTTPRequest?

    init(statusCode: Int = 200, body: String) {
        self.statusCode = statusCode
        self.body = body
    }

    func fetch(_ request: HTTPRequest) async throws -> HTTPResponse {
        lastRequest = request
        return HTTPResponse(finalURL: request.url, statusCode: statusCode, body: body)
    }
}
