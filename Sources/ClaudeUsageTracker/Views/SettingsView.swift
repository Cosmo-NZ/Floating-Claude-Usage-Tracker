import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var store: UsageStore
    var onLaunchAtLoginChanged: (Bool) -> Void
    var onMenuBarChanged: (Bool) -> Void

    enum Section: String, CaseIterable, Identifiable {
        case claude = "Claude.ai", api = "API Console", fable = "Fable",
             general = "General", appearance = "Appearance"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .claude: return "key.fill"
            case .api: return "dollarsign.circle"
            case .fable: return "sparkles"
            case .general: return "gearshape"
            case .appearance: return "paintbrush"
            }
        }
    }

    @State private var selection: Section = .claude
    @State private var showSignIn = false
    @State private var manualKey = ""
    @State private var manualAdminKey = ""
    @State private var adminKeySaved = KeychainStore.shared.get(.adminKey) != nil
    @State private var sessionConnected = KeychainStore.shared.get(.sessionKey) != nil

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .frame(minWidth: 180)
        } detail: {
            ScrollView { detail.padding(24).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .frame(width: 640, height: 420)
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .claude: claudePane
        case .api: apiPane
        case .fable: fablePane
        case .general: generalPane
        case .appearance: appearancePane
        }
    }

    private var claudePane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Personal Usage").font(.title2.bold())
            Text("Track your Claude.ai usage and sessions").foregroundStyle(.secondary)
            HStack {
                Circle().fill(sessionConnected ? .green : .gray).frame(width: 8, height: 8)
                Text(sessionConnected ? "Connected" : "Not connected")
                Spacer()
                if sessionConnected {
                    Button("Remove", role: .destructive) {
                        KeychainStore.shared.set(nil, for: .sessionKey)
                        sessionConnected = false
                        Task { await store.refresh() }
                    }
                }
            }
            Button { showSignIn = true } label: {
                Label("Sign in to Claude.ai", systemImage: "globe")
            }
            .buttonStyle(.borderedProminent)
            Divider()
            Text("Advanced: paste session key").font(.caption).foregroundStyle(.secondary)
            HStack {
                SecureField("sessionKey value", text: $manualKey)
                Button("Save") {
                    guard !manualKey.isEmpty else { return }
                    KeychainStore.shared.set(manualKey, for: .sessionKey)
                    manualKey = ""
                    sessionConnected = true
                    Task { await store.refresh() }
                }
            }
        }
        .sheet(isPresented: $showSignIn) {
            VStack(spacing: 0) {
                HStack {
                    Text("Sign in to Claude.ai").font(.headline)
                    Spacer()
                    Button("Cancel") { showSignIn = false }
                }.padding()
                SignInWebView { key in
                    KeychainStore.shared.set(key, for: .sessionKey)
                    sessionConnected = true
                    showSignIn = false
                    Task { await store.refresh() }
                }
            }.frame(width: 520, height: 600)
        }
    }

    private var apiPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API Console Spend").font(.title2.bold())
            Toggle("Track API spend", isOn: $settings.spendEnabled)
            if settings.spendEnabled {
                Text("Admin API key (sk-ant-admin…)").font(.caption).foregroundStyle(.secondary)
                HStack {
                    SecureField("sk-ant-admin…", text: $manualAdminKey)
                    Button("Save") {
                        guard !manualAdminKey.isEmpty else { return }
                        KeychainStore.shared.set(manualAdminKey, for: .adminKey)
                        manualAdminKey = ""
                        adminKeySaved = true
                        Task { await store.refresh() }
                    }
                }
                if adminKeySaved {
                    Label("Key saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
        }
    }

    private var fablePane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Fable").font(.title2.bold())
            Text("Track the per-model Fable weekly limit, as shown in the Claude app's usage area.")
                .foregroundStyle(.secondary)
            Toggle("Track Fable weekly usage", isOn: $settings.trackFable)
            Text("When on, a Weekly (Fable) row appears in the floating panel.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General").font(.title2.bold())
            VStack(alignment: .leading) {
                Text("Refresh interval: \(Int(settings.refreshInterval))s")
                Slider(value: $settings.refreshInterval, in: 10...300, step: 5) { editing in
                    if !editing { store.restartTimer() }
                }
                HStack { Text("10s").font(.caption2); Spacer(); Text("300s").font(.caption2) }
                    .foregroundStyle(.secondary)
            }
            Toggle("Threshold notifications (75 / 90 / 95%)", isOn: $settings.notificationsEnabled)
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
                .onChange(of: settings.launchAtLogin) { _, newValue in onLaunchAtLoginChanged(newValue) }
        }
    }

    private var appearancePane: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Appearance").font(.title2.bold())
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Always on top", isOn: $settings.alwaysOnTop)
                Text(settings.alwaysOnTop
                     ? "The panel stays visible above other windows."
                     : "Panel is hidden; click the menu bar icon to show/hide it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading) {
                Text("Panel opacity: \(Int(settings.panelOpacity * 100))%")
                Slider(value: $settings.panelOpacity, in: 0.3...1.0)
                HStack { Text("See-through").font(.caption2); Spacer(); Text("Solid").font(.caption2) }
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                    .onChange(of: settings.showMenuBarIcon) { _, newValue in onMenuBarChanged(newValue) }
                    .disabled(!settings.alwaysOnTop)
                if !settings.alwaysOnTop {
                    Text("Kept on while “Always on top” is off, so the panel stays reachable.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
