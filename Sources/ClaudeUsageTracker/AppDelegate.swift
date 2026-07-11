import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings.shared
    private(set) var store: UsageStore!
    private var panel: FloatingPanel!
    let menuBar = MenuBarController()
    private var settingsWindow: NSWindow?
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.requestAuthorization()
        store = UsageStore(settings: settings)
        store.onThresholdCrossed = { kind, threshold in
            NotificationManager.notify(kind: kind, threshold: threshold)
        }

        panel = FloatingPanel(store: store, settings: settings, onOpenSettings: { [weak self] in
            self?.openSettings()
        })

        menuBar.onToggle = { [weak self] in self?.toggleFromMenuBar() }
        menuBar.onOpenSettings = { [weak self] in self?.openSettings() }

        // Floating → panel is always visible. Not floating → hidden until summoned from the icon.
        if settings.alwaysOnTop { panel.orderFront(nil) }
        updateMenuBarVisibility()

        if settings.launchAtLogin { LoginItemManager.setEnabled(true) }

        store.start()
        observeAlwaysOnTop()
        observeOpacity()
        observeSnapshot()
    }

    // MARK: - Menu-bar popover

    /// The icon toggles the panel only when it is NOT floating. When floating, the panel is
    /// always on screen, so a click just brings it forward.
    private func toggleFromMenuBar() {
        if settings.alwaysOnTop {
            panel.orderFront(nil)
            return
        }
        if panel.isVisible { hidePopover() } else { showPopover() }
    }

    private func showPopover() {
        positionPanelUnderIcon()
        panel.level = .floating          // sit above other windows while open
        panel.orderFrontRegardless()
        startOutsideClickMonitor()
    }

    private func hidePopover() {
        stopOutsideClickMonitor()
        panel.orderOut(nil)
    }

    private func positionPanelUnderIcon() {
        let size = panel.frame.size
        guard let icon = menuBar.iconScreenFrame,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(icon) }) ?? NSScreen.main else {
            return
        }
        panel.setPopoverOrigin(PanelPlacement.popoverOrigin(
            iconFrame: icon, panelSize: size, visibleFrame: screen.visibleFrame))
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        // Fires for clicks in OTHER apps / the desktop (not our own panel) → dismiss.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePopover()
        }
    }

    private func stopOutsideClickMonitor() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
    }

    // MARK: - Visibility rules

    /// The menu-bar icon is shown when the user enabled it, and always when not floating
    /// (so the panel can always be summoned).
    private func updateMenuBarVisibility() {
        let shouldShow = settings.showMenuBarIcon || !settings.alwaysOnTop
        menuBar.setVisible(shouldShow, store: store)
        if menuBar.isVisible { menuBar.update(with: store.snapshot) }
    }

    private func applyAlwaysOnTopState() {
        panel.applyAlwaysOnTop(settings.alwaysOnTop)
        if settings.alwaysOnTop {
            hidePopover()               // clear popover state
            panel.restoreSavedOrigin()  // back to the remembered floating spot
            panel.orderFront(nil)
        } else {
            panel.orderOut(nil)         // hide until summoned from the icon
        }
        updateMenuBarVisibility()
    }

    // MARK: - Observers

    private func observeAlwaysOnTop() {
        withObservationTracking { _ = settings.alwaysOnTop } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.applyAlwaysOnTopState()
                self.observeAlwaysOnTop()
            }
        }
    }

    private func observeOpacity() {
        withObservationTracking { _ = settings.panelOpacity } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.panel.applyOpacity(self.settings.panelOpacity)
                self.observeOpacity()
            }
        }
    }

    private func observeSnapshot() {
        withObservationTracking { _ = store.snapshot.fiveHour } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.menuBar.update(with: self.store.snapshot)
                self.observeSnapshot()
            }
        }
    }

    // MARK: - Settings window

    func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(
            settings: settings,
            store: store,
            onLaunchAtLoginChanged: { LoginItemManager.setEnabled($0) },
            onMenuBarChanged: { [weak self] _ in self?.updateMenuBarVisibility() })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Settings"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
}
