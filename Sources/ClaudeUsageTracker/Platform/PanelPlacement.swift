import Foundation
import CoreGraphics

/// Pure placement logic: keep the floating panel on a visible screen even when the saved
/// position points off-screen (e.g. a display was rearranged/disconnected, or it was dragged
/// past an edge). All coordinates are in AppKit's bottom-left global space.
enum PanelPlacement {
    /// A saved origin counts as usable only if a meaningful slice of the panel overlaps some
    /// screen's visible area — enough to see and grab it.
    static func isVisible(origin: CGPoint, size: CGSize, visibleFrames: [CGRect],
                          minVisible: CGSize = CGSize(width: 80, height: 40)) -> Bool {
        let rect = CGRect(origin: origin, size: size)
        for frame in visibleFrames {
            let inter = frame.intersection(rect)
            if inter.width >= minVisible.width && inter.height >= minVisible.height { return true }
        }
        return false
    }

    /// Top-right of the first (main) visible frame, with a small margin.
    static func fallbackOrigin(size: CGSize, visibleFrames: [CGRect]) -> CGPoint {
        guard let frame = visibleFrames.first else { return .zero }
        return CGPoint(x: frame.maxX - size.width - 20, y: frame.maxY - size.height - 20)
    }

    /// The saved origin if still visible, otherwise the fallback.
    static func resolvedOrigin(saved: CGPoint?, size: CGSize, visibleFrames: [CGRect]) -> CGPoint {
        if let saved, isVisible(origin: saved, size: size, visibleFrames: visibleFrames) {
            return saved
        }
        return fallbackOrigin(size: size, visibleFrames: visibleFrames)
    }

    /// Bottom-left origin that places the panel just below a menu-bar icon, horizontally
    /// centered under it and clamped inside the screen's visible area. (Bottom-left space.)
    static func popoverOrigin(iconFrame: CGRect, panelSize: CGSize, visibleFrame: CGRect,
                              gap: CGFloat = 4, margin: CGFloat = 8) -> CGPoint {
        var x = iconFrame.midX - panelSize.width / 2
        x = min(max(x, visibleFrame.minX + margin), visibleFrame.maxX - panelSize.width - margin)
        let y = iconFrame.minY - panelSize.height - gap
        return CGPoint(x: x, y: y)
    }
}
