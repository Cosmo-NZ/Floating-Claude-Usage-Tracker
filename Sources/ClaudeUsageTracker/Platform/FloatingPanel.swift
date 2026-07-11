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

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func applyAlwaysOnTop(_ on: Bool) {
        level = on ? .floating : .normal
    }

    func applyOpacity(_ value: Double) {
        alphaValue = max(0.3, min(1.0, value))
    }

    /// Restore the persisted floating position, validated against current screens.
    func restoreSavedOrigin() { restoreOrigin() }

    private func restoreOrigin() {
        let saved: CGPoint? = (settings.panelOriginX >= 0 && settings.panelOriginY >= 0)
            ? CGPoint(x: settings.panelOriginX, y: settings.panelOriginY) : nil
        let frames = NSScreen.screens.map { $0.visibleFrame }
        setFrameOrigin(PanelPlacement.resolvedOrigin(saved: saved, size: frame.size, visibleFrames: frames))
    }

    /// Position the panel without persisting (used for the transient menu-bar popover, so it
    /// doesn't overwrite the remembered floating position).
    func setPopoverOrigin(_ point: CGPoint) {
        persistPosition = false
        setFrameOrigin(point)
        persistPosition = true
    }

    private var persistPosition = true

    /// Re-check placement when displays are added/removed/rearranged so the panel never
    /// gets stranded off-screen while running.
    @objc private func screensChanged() {
        let frames = NSScreen.screens.map { $0.visibleFrame }
        if !PanelPlacement.isVisible(origin: frame.origin, size: frame.size, visibleFrames: frames) {
            setFrameOrigin(PanelPlacement.fallbackOrigin(size: frame.size, visibleFrames: frames))
        }
    }

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        guard persistPosition else { return }
        settings.panelOriginX = point.x
        settings.panelOriginY = point.y
    }

    override var canBecomeKey: Bool { true }
}
