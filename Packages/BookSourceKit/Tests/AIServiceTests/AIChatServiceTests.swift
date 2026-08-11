import XCTest
@testable import AIService
import BookSourceModel

final class AIChatServiceTests: XCTestCase {
    private func provider(baseURL: String = "https://api.example.com/v1") -> AIProvider {
        AIProvider(id: "p1", name: "Test Provider", baseURL: baseURL, modelName: "gpt-test")
    }

    func testSuccessfulCompletionReturnsMessageContent() async throws {
        let client = StubAIHTTPClient(body: #"{"choices":[{"message":{"role":"assistant","content":"这是摘要"}}]}"#)
        let result = try await AIChatService.complete(
            provider: provider(), apiKey: "sk-test", prompt: "总结一下", httpClient: client
        )
        XCTAssertEqual(result, "这是摘要")
    }

    func testSendsAuthorizationHeaderAndPostBody() async throws {
        let client = StubAIHTTPClient(body: #"{"choices":[{"message":{"content":"ok"}}]}"#)
        _ = try await AIChatService.complete(
            provider: provider(), apiKey: "sk-secret", prompt: "hello", httpClient: client
        )
        let request = await client.lastRequest
        XCTAssertEqual(request?.method, "POST")
        XCTAssertEqual(request?.headers["Authorization"], "Bearer sk-secret")
        XCTAssertEqual(request?.url, "https://api.example.com/v1/chat/completions")
        let bodyString = request?.body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        XCTAssertTrue(bodyString.contains("gpt-test"))
        XCTAssertTrue(bodyString.contains("hello"))
    }

    func testTrailingSlashAndExistingSuffixAreNormalized() {
        XCTAssertEqual(
            AIChatService.chatCompletionsURL(baseURL: "https://api.example.com/v1/"),
            "https://api.example.com/v1/chat/completions"
        )
        XCTAssertEqual(
            AIChatService.chatCompletionsURL(baseURL: "https://api.example.com/v1/chat/completions"),
            "https://api.example.com/v1/chat/completions"
        )
    }

    func testHTTPErrorSurfacesProviderErrorMessage() async throws {
        let client = StubAIHTTPClient(statusCode: 401, body: #"{"error":{"message":"invalid api key"}}"#)
        do {
            _ = try await AIChatService.complete(provider: provider(), apiKey: "bad", prompt: "hi", httpClient: client)
            XCTFail("expected an error")
        } catch let AIChatError.httpError(statusCode, message) {
            XCTAssertEqual(statusCode, 401)
            XCTAssertEqual(message, "invalid api key")
        }
    }

    func testHTTPErrorWithoutParsableBodyFallsBackToRawText() async throws {
        let client = StubAIHTTPClient(statusCode: 500, body: "internal server error")
        do {
            _ = try await AIChatService.complete(provider: provider(), apiKey: "k", prompt: "hi", httpClient: client)
            XCTFail("expected an error")
        } catch let AIChatError.httpError(statusCode, message) {
            XCTAssertEqual(statusCode, 500)
            XCTAssertEqual(message, "internal server error")
        }
    }

    func testMalformedSuccessBodyThrowsInvalidResponse() async throws {
        let client = StubAIHTTPClient(body: #"{"unexpected":"shape"}"#)
        do {
            _ = try await AIChatService.complete(provider: provider(), apiKey: "k", prompt: "hi", httpClient: client)
            XCTFail("expected an error")
        } catch AIChatError.invalidResponse {
            // expected
        }
    }
}
