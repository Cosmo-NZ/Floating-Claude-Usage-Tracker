import XCTest
@testable import ClaudeUsageTracker

final class KeychainStoreTests: XCTestCase {
    func testRoundTripAndDelete() {
        KeychainStore.set("secret-123", for: .sessionKey)
        XCTAssertEqual(KeychainStore.get(.sessionKey), "secret-123")
        KeychainStore.set(nil, for: .sessionKey)
        XCTAssertNil(KeychainStore.get(.sessionKey))
    }
}
