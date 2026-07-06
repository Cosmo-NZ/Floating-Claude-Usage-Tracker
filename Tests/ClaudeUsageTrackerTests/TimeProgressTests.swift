import XCTest
@testable import ClaudeUsageTracker

final class TimeProgressTests: XCTestCase {
    func testElapsedFractionMidway() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval(2.5 * 3600) // 2.5h left of a 5h window
        let f = TimeProgress.elapsedFraction(resetsAt: resetsAt, windowLength: 5 * 3600, now: now)
        XCTAssertEqual(f, 0.5, accuracy: 0.0001)
    }

    func testElapsedFractionClampsAboveOne() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval(-3600) // reset already passed
        let f = TimeProgress.elapsedFraction(resetsAt: resetsAt, windowLength: 5 * 3600, now: now)
        XCTAssertEqual(f, 1.0, accuracy: 0.0001)
    }

    func testElapsedFractionClampsBelowZero() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval(6 * 3600) // more than a full window away
        let f = TimeProgress.elapsedFraction(resetsAt: resetsAt, windowLength: 5 * 3600, now: now)
        XCTAssertEqual(f, 0.0, accuracy: 0.0001)
    }

    func testElapsedStringHoursAndMinutes() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval(1.8 * 3600) // 3h 12m elapsed of 5h
        let s = TimeProgress.elapsedString(resetsAt: resetsAt, windowLength: 5 * 3600, now: now)
        XCTAssertEqual(s, "3h 12m elapsed")
    }

    func testElapsedStringDaysAndHours() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval((7 - 3.25) * 24 * 3600) // 3d 6h elapsed of 7d
        let s = TimeProgress.elapsedString(resetsAt: resetsAt, windowLength: 7 * 24 * 3600, now: now)
        XCTAssertEqual(s, "3d 6h elapsed")
    }

    func testWindowKindLengths() {
        XCTAssertEqual(WindowKind.fiveHour.length, 5 * 3600)
        XCTAssertEqual(WindowKind.sevenDay.length, 7 * 24 * 3600)
    }
}
