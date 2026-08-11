import XCTest
@testable import Persistence

final class LoginCookieStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookSourceKitTests-\(UUID().uuidString)")
            .appendingPathComponent("login_cookies.json")
    }

    private func sampleCookie(name: String = "session") -> SavedCookie {
        SavedCookie(name: name, value: "abc123", domain: "www.example.com", path: "/", isSecure: true, expiresAt: nil)
    }

    func testSetThenGetRoundTrips() async throws {
        let store = LoginCookieStore(fileURL: tempFileURL())
        try await store.setCookies([sampleCookie()], bookSourceUrl: "https://www.example.com")
        let cookies = try await store.cookies(bookSourceUrl: "https://www.example.com")
        XCTAssertEqual(cookies, [sampleCookie()])
    }

    func testUnknownSourceHasNoCookies() async throws {
        let store = LoginCookieStore(fileURL: tempFileURL())
        let cookies = try await store.cookies(bookSourceUrl: "https://nowhere.example.com")
        XCTAssertTrue(cookies.isEmpty)
    }

    func testSettingEmptyCookiesRemovesTheEntry() async throws {
        let store = LoginCookieStore(fileURL: tempFileURL())
        try await store.setCookies([sampleCookie()], bookSourceUrl: "https://www.example.com")
        try await store.setCookies([], bookSourceUrl: "https://www.example.com")
        let all = try await store.allCookies()
        XCTAssertTrue(all.isEmpty)
    }

    func testIsLoggedInReflectsWhetherCookiesArePresent() async throws {
        let store = LoginCookieStore(fileURL: tempFileURL())
        let url = "https://www.example.com"
        var loggedIn = try await store.isLoggedIn(bookSourceUrl: url)
        XCTAssertFalse(loggedIn)
        try await store.setCookies([sampleCookie()], bookSourceUrl: url)
        loggedIn = try await store.isLoggedIn(bookSourceUrl: url)
        XCTAssertTrue(loggedIn)
    }

    func testCookiesSurviveSimulatedAppRelaunch() async throws {
        let fileURL = tempFileURL()
        let session1 = LoginCookieStore(fileURL: fileURL)
        try await session1.setCookies([sampleCookie()], bookSourceUrl: "https://www.example.com")

        let session2 = LoginCookieStore(fileURL: fileURL)
        let cookies = try await session2.cookies(bookSourceUrl: "https://www.example.com")
        XCTAssertEqual(cookies, [sampleCookie()])
    }
}
