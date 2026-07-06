import XCTest
@testable import ClaudeUsageTracker

final class ConsoleSpendClientTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testSumsAllAmounts() throws {
        let total = try ConsoleSpendClient.parseSpend(fixture("cost_report"))
        XCTAssertEqual(total, 42.18, accuracy: 0.001)
    }

    func testEmptyDataIsZero() throws {
        XCTAssertEqual(try ConsoleSpendClient.parseSpend(Data(#"{"data":[]}"#.utf8)), 0.0, accuracy: 0.001)
    }

    func testMonthStartIsFirstOfMonthUTC() {
        let now = ISO8601DateFormatter().date(from: "2026-07-06T14:00:00Z")!
        XCTAssertTrue(ConsoleSpendClient.monthStartISO(now: now).hasPrefix("2026-07-01"))
    }
}
