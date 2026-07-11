import AppKit

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private var contextMenu: NSMenu?

    /// Left-click on the icon (used to toggle the panel).
    var onToggle: (() -> Void)?
    /// "Settings…" chosen from the right-click menu.
    var onOpenSettings: (() -> Void)?

    var isVisible: Bool { statusItem != nil }

    /// Screen-space frame of the status icon, for positioning the panel beneath it.
    var iconScreenFrame: CGRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    func setVisible(_ on: Bool, store: UsageStore) {
        if on {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.title = "◔ —"
                button.target = self
                button.action = #selector(statusClicked)
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            let menu = NSMenu()
            let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            settingsItem.target = self
            menu.addItem(settingsItem)
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            contextMenu = menu
            statusItem = item
            update(with: store.snapshot)
        } else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
        }
    }

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) ?? false)
        if isRight {
            showMenu()
        } else {
            onToggle?()
        }
    }

    /// Show the context menu on demand (assign, click, then detach so left-clicks keep toggling).
    private func showMenu() {
        guard let item = statusItem, let button = item.button, let menu = contextMenu else { return }
        item.menu = menu
        button.performClick(nil)
        item.menu = nil
    }

    @objc private func openSettings() { onOpenSettings?() }

    func update(with snapshot: UsageSnapshot) {
        guard let button = statusItem?.button else { return }
        if let five = snapshot.fiveHour {
            button.title = "◔ \(Int(five.utilization * 100))%"
        } else {
            button.title = "◔ —"
        }
    }
}
