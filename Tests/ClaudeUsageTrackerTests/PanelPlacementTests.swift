import XCTest
import CoreGraphics
@testable import ClaudeUsageTracker

final class PanelPlacementTests: XCTestCase {
    let size = CGSize(width: 280, height: 240)
    // A single 1440p screen in bottom-left space, menu bar trimmed.
    let mainScreen = CGRect(x: 0, y: 0, width: 2560, height: 1400)

    func testSavedOriginOnScreenIsKept() {
        let saved = CGPoint(x: 2000, y: 1000)
        let result = PanelPlacement.resolvedOrigin(saved: saved, size: size, visibleFrames: [mainScreen])
        XCTAssertEqual(result, saved)
    }

    func testOffScreenSavedOriginFallsBack() {
        // Mirrors the real bug: an origin belonging to a display that is no longer present.
        let saved = CGPoint(x: 4820, y: 3000)
        let result = PanelPlacement.resolvedOrigin(saved: saved, size: size, visibleFrames: [mainScreen])
        XCTAssertNotEqual(result, saved)
        XCTAssertTrue(PanelPlacement.isVisible(origin: result, size: size, visibleFrames: [mainScreen]))
    }

    func testNilSavedFallsBackOnScreen() {
        let result = PanelPlacement.resolvedOrigin(saved: nil, size: size, visibleFrames: [mainScreen])
        XCTAssertTrue(PanelPlacement.isVisible(origin: result, size: size, visibleFrames: [mainScreen]))
    }

    func testBarelyVisibleSliverCountsAsOffScreen() {
        // Panel pushed above the top edge with only ~8px showing (the reported symptom).
        let saved = CGPoint(x: 2000, y: mainScreen.maxY - 8)
        XCTAssertFalse(PanelPlacement.isVisible(origin: saved, size: size, visibleFrames: [mainScreen]))
    }

    func testSecondScreenOriginIsKeptWhenThatScreenPresent() {
        let second = CGRect(x: 2560, y: 0, width: 2560, height: 1440)
        let saved = CGPoint(x: 4820, y: 1100)
        let result = PanelPlacement.resolvedOrigin(saved: saved, size: size, visibleFrames: [mainScreen, second])
        XCTAssertEqual(result, saved)
    }

    func testPopoverOriginSitsBelowIconAndCentered() {
        let icon = CGRect(x: 1200, y: 1380, width: 40, height: 22) // near top, bottom-left space
        let result = PanelPlacement.popoverOrigin(iconFrame: icon, panelSize: size, visibleFrame: mainScreen)
        // Centered horizontally under the icon.
        XCTAssertEqual(result.x, icon.midX - size.width / 2, accuracy: 0.001)
        // Panel top sits just below the icon (top = origin.y + height).
        XCTAssertEqual(result.y + size.height, icon.minY - 4, accuracy: 0.001)
    }

    func testPopoverOriginClampsToScreenAtRightEdge() {
        let icon = CGRect(x: 2540, y: 1380, width: 20, height: 22) // icon at far right
        let result = PanelPlacement.popoverOrigin(iconFrame: icon, panelSize: size, visibleFrame: mainScreen)
        XCTAssertLessThanOrEqual(result.x + size.width, mainScreen.maxX) // stays on screen
        XCTAssertEqual(result.x, mainScreen.maxX - size.width - 8, accuracy: 0.001)
    }
}
