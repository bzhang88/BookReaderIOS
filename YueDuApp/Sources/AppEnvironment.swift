import Foundation
import NetworkClient
import Persistence

/// Shared app-wide dependencies (persistence stores, network client), created once and injected
/// into the view hierarchy via `.environmentObject`.
@MainActor
final class AppEnvironment: ObservableObject {
    let bookSourceStore: BookSourceStore
    let shelfStore: ShelfStore
    let httpClient: any HTTPClient

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        bookSourceStore = BookSourceStore(fileURL: appSupport.appendingPathComponent("book_sources.json"))
        shelfStore = ShelfStore(fileURL: appSupport.appendingPathComponent("shelf.json"))
        httpClient = URLSessionHTTPClient()
    }
}
