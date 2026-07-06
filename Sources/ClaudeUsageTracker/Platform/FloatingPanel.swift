import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    private let settings: AppSettings

    init(store: UsageStore, settings: AppSettings, onOpenSettings: @escaping () -> Void) {
        self.settings = settings
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 240),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        isFloatingPanel = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = PanelView(store: store, settings: settings, onOpenSettings: onOpenSettings)
        let hosting = NSHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting

        applyAlwaysOnTop(settings.alwaysOnTop)
        applyOpacity(settings.panelOpacity)
        restoreOrigin()
    }

    func applyAlwaysOnTop(_ on: Bool) {
        level = on ? .floating : .normal
    }

    func applyOpacity(_ value: Double) {
        alphaValue = max(0.3, min(1.0, value))
    }

    private func restoreOrigin() {
        if settings.panelOriginX >= 0, settings.panelOriginY >= 0 {
            setFrameOrigin(NSPoint(x: settings.panelOriginX, y: settings.panelOriginY))
        } else if let screen = NSScreen.main {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.maxX - 300, y: f.maxY - 280))
        }
    }

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        settings.panelOriginX = point.x
        settings.panelOriginY = point.y
    }

    override var canBecomeKey: Bool { true }
}
