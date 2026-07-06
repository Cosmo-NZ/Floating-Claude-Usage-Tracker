import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings.shared
    private(set) var store: UsageStore!
    private var panel: FloatingPanel!
    let menuBar = MenuBarController()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.requestAuthorization()
        store = UsageStore(settings: settings)
        store.onThresholdCrossed = { kind, threshold in
            NotificationManager.notify(kind: kind, threshold: threshold)
        }

        panel = FloatingPanel(store: store, settings: settings, onOpenSettings: { [weak self] in
            self?.openSettings()
        })
        panel.orderFront(nil)

        if settings.showMenuBarIcon {
            menuBar.setVisible(true, store: store, onOpenSettings: { [weak self] in self?.openSettings() })
        }
        LoginItemManager.setEnabled(settings.launchAtLogin)

        store.start()
        observeAlwaysOnTop()
        observeSnapshot()
    }

    private func observeAlwaysOnTop() {
        withObservationTracking { _ = settings.alwaysOnTop } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.panel.applyAlwaysOnTop(self.settings.alwaysOnTop)
                self.observeAlwaysOnTop()
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
            onMenuBarChanged: { [weak self] on in
                guard let self else { return }
                self.menuBar.setVisible(on, store: self.store, onOpenSettings: { self.openSettings() })
            })
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
