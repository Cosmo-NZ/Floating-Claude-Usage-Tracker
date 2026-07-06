import XCTest
@testable import ClaudeUsageTracker

final class ThresholdTrackerTests: XCTestCase {
    func testFiresOnUpwardCrossingOnce() {
        var t = ThresholdTracker()
        XCTAssertEqual(t.crossings(kind: .fiveHour, utilization: 0.50), [])
        XCTAssertEqual(t.crossings(kind: .fiveHour, utilization: 0.76), [0.75])
        XCTAssertEqual(t.crossings(kind: .fiveHour, utilization: 0.80), []) // no new threshold
        XCTAssertEqual(t.crossings(kind: .fiveHour, utilization: 0.96), [0.90, 0.95])
    }

    func testResetsWhenWindowDrops() {
        var t = ThresholdTracker()
        _ = t.crossings(kind: .fiveHour, utilization: 0.96)
        XCTAssertEqual(t.crossings(kind: .fiveHour, utilization: 0.10), []) // window reset
        XCTAssertEqual(t.crossings(kind: .fiveHour, utilization: 0.76), [0.75]) // fires again
    }

    func testWindowsAreIndependent() {
        var t = ThresholdTracker()
        XCTAssertEqual(t.crossings(kind: .fiveHour, utilization: 0.80), [0.75])
        XCTAssertEqual(t.crossings(kind: .sevenDay, utilization: 0.80), [0.75])
    }
}
