import XCTest
@testable import ClaudeUsageTracker

final class SubscriptionUsageClientTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testParsesOrgID() throws {
        XCTAssertEqual(try SubscriptionUsageClient.parseOrgID(fixture("organizations")), "org-abc-123")
    }

    func testParsesUsageWindows() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let result = try SubscriptionUsageClient.parseUsage(fixture("usage"), now: now)
        XCTAssertEqual(result.five?.utilization ?? 0, 0.42, accuracy: 0.0001)
        XCTAssertEqual(result.five?.windowLength, 5 * 3600)
        XCTAssertEqual(result.seven?.utilization ?? 0, 0.63, accuracy: 0.0001)
        XCTAssertEqual(result.seven?.windowLength, 7 * 24 * 3600)
        XCTAssertEqual(result.opus?.utilization ?? 0, 0.12, accuracy: 0.0001)
        let expected = ISO8601DateFormatter().date(from: "2026-07-06T17:00:00Z")
        XCTAssertEqual(result.five?.resetsAt, expected)
    }

    func testMissingWindowsBecomeNil() throws {
        let result = try SubscriptionUsageClient.parseUsage(Data("{}".utf8), now: Date())
        XCTAssertNil(result.five)
        XCTAssertNil(result.seven)
        XCTAssertNil(result.opus)
    }
}
