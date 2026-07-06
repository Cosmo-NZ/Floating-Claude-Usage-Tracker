import XCTest
@testable import ClaudeUsageTracker

final class StatusClientTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testParsesMinorAsDegraded() throws {
        let status = try StatusClient.parse(fixture("status"))
        XCTAssertEqual(status, .degraded)
    }

    func testMapsIndicators() throws {
        XCTAssertEqual(try StatusClient.parse(Data(#"{"status":{"indicator":"none"}}"#.utf8)), .operational)
        XCTAssertEqual(try StatusClient.parse(Data(#"{"status":{"indicator":"critical"}}"#.utf8)), .outage)
        XCTAssertEqual(try StatusClient.parse(Data(#"{"status":{"indicator":"maintenance"}}"#.utf8)), .degraded)
        XCTAssertEqual(try StatusClient.parse(Data(#"{"status":{"indicator":"weird"}}"#.utf8)), .unknown)
    }
}
