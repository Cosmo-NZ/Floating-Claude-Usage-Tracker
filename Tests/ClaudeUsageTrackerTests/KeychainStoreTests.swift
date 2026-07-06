import XCTest
@testable import ClaudeUsageTracker

final class KeychainStoreTests: XCTestCase {
    func testRoundTripAndDelete() {
        // Isolated service so tests never touch the app's real credentials.
        let store = KeychainStore(service: "com.marccramer.ClaudeUsageTracker.tests-\(UUID().uuidString)")
        store.set("secret-123", for: .sessionKey)
        XCTAssertEqual(store.get(.sessionKey), "secret-123")
        store.set(nil, for: .sessionKey)
        XCTAssertNil(store.get(.sessionKey))
    }
}
