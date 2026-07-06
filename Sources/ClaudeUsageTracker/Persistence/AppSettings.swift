import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings(suiteName: "com.marccramer.ClaudeUsageTracker")

    @ObservationIgnored private let defaults: UserDefaults

    var refreshInterval: Double { didSet { defaults.set(refreshInterval, forKey: "refreshInterval") } }
    var spendEnabled: Bool { didSet { defaults.set(spendEnabled, forKey: "spendEnabled") } }
    var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: "notificationsEnabled") } }
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }
    var alwaysOnTop: Bool { didSet { defaults.set(alwaysOnTop, forKey: "alwaysOnTop") } }
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }
    var panelOriginX: Double { didSet { defaults.set(panelOriginX, forKey: "panelOriginX") } }
    var panelOriginY: Double { didSet { defaults.set(panelOriginY, forKey: "panelOriginY") } }

    init(suiteName: String) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.defaults = defaults
        defaults.register(defaults: [
            "refreshInterval": 30.0,
            "alwaysOnTop": true,
            "notificationsEnabled": true,
            "panelOriginX": -1.0,
            "panelOriginY": -1.0,
        ])
        refreshInterval = defaults.double(forKey: "refreshInterval")
        spendEnabled = defaults.bool(forKey: "spendEnabled")
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        alwaysOnTop = defaults.bool(forKey: "alwaysOnTop")
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
        panelOriginX = defaults.double(forKey: "panelOriginX")
        panelOriginY = defaults.double(forKey: "panelOriginY")
    }
}
