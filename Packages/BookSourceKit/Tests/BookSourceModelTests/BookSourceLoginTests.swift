import XCTest
@testable import BookSourceModel

final class BookSourceLoginTests: XCTestCase {
    private func decode(_ json: String) throws -> BookSource {
        try JSONDecoder().decode(BookSource.self, from: Data(json.utf8))
    }

    func testDecodesLoginFields() throws {
        let json = """
        {
            "bookSourceUrl": "https://www.example.com",
            "bookSourceName": "示例源",
            "loginUrl": "https://www.example.com/login",
            "loginUi": "[{\\"name\\":\\"用户名\\",\\"type\\":\\"text\\"},{\\"name\\":\\"密码\\",\\"type\\":\\"password\\"}]"
        }
        """
        let source = try decode(json)
        XCTAssertEqual(source.loginUrl, "https://www.example.com/login")
        XCTAssertTrue(source.loginUi?.contains("密码") ?? false)
        XCTAssertTrue(source.hasWebLoginURL)
    }

    func testMissingLoginFieldsDefaultToNil() throws {
        let json = #"{"bookSourceUrl": "https://x.com", "bookSourceName": "X"}"#
        let source = try decode(json)
        XCTAssertNil(source.loginUrl)
        XCTAssertNil(source.loginUi)
        XCTAssertFalse(source.hasWebLoginURL)
    }

    func testJSDrivenLoginUrlIsNotAWebLoginURL() throws {
        let json = #"{"bookSourceUrl": "https://x.com", "bookSourceName": "X", "loginUrl": "@js:login();"}"#
        let source = try decode(json)
        XCTAssertFalse(source.hasWebLoginURL)
    }
}
