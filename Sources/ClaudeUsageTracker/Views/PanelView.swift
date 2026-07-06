import SwiftUI

struct PanelView: View {
    @Bindable var store: UsageStore
    @Bindable var settings: AppSettings
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Claude Usage").font(.system(size: 13, weight: .bold))
                Spacer()
                Text("Always on top")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Toggle("", isOn: $settings.alwaysOnTop)
                    .toggleStyle(.switch).labelsHidden().scaleEffect(0.7)
                    .help("Keep the panel above all other windows")
            }
            UsageBar(kind: .fiveHour, usage: store.snapshot.fiveHour,
                     hasError: store.snapshot.sourceErrors[.subscription] != nil)
            UsageBar(kind: .sevenDay, usage: store.snapshot.sevenDay,
                     hasError: store.snapshot.sourceErrors[.subscription] != nil)
            if let opus = store.snapshot.sevenDayOpus {
                UsageBar(kind: .sevenDayOpus, usage: opus, hasError: false)
            }
            if settings.spendEnabled {
                HStack {
                    Text("API spend").font(.system(size: 12, weight: .semibold))
                    if store.snapshot.sourceErrors[.spend] != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow).font(.system(size: 10))
                    }
                    Spacer()
                    Text(store.snapshot.monthlySpendUSD.map { String(format: "$%.2f this month", $0) } ?? "—")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(store.snapshot.status.label).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if let updated = store.snapshot.lastUpdated {
                    Text(updated, style: .time).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Refresh now")
                Button { onOpenSettings() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless).help("Settings")
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var statusColor: Color {
        switch store.snapshot.status.color {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        case .gray: return .gray
        }
    }
}
