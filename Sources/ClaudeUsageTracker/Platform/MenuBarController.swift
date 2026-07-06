import AppKit

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private var onOpenSettings: (() -> Void)?

    func setVisible(_ on: Bool, store: UsageStore, onOpenSettings: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        if on {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.title = "◔ —"
            let menu = NSMenu()
            let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            settingsItem.target = self
            menu.addItem(settingsItem)
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            item.menu = menu
            statusItem = item
            update(with: store.snapshot)
        } else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
        }
    }

    func update(with snapshot: UsageSnapshot) {
        guard let button = statusItem?.button else { return }
        if let five = snapshot.fiveHour {
            button.title = "◔ \(Int(five.utilization * 100))%"
        } else {
            button.title = "◔ —"
        }
    }

    @objc private func openSettings() { onOpenSettings?() }
}
