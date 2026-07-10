import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    struct ClientProviders {
        let status: StatusProviding?
        let subscription: SubscriptionProviding?
        let spend: SpendProviding?
    }

    private(set) var snapshot: UsageSnapshot = .empty
    @ObservationIgnored var onThresholdCrossed: ((WindowKind, Double) -> Void)?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let clientFactory: ClientFactory
    @ObservationIgnored private var tracker = ThresholdTracker()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastSpendFetch: Date?

    init(settings: AppSettings, clientFactory: ClientFactory = LiveClientFactory()) {
        self.settings = settings
        self.clientFactory = clientFactory
    }

    func start() {
        stop()
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: settings.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// Rebuild the timer after the user changes the interval.
    func restartTimer() { if timer != nil { start() } }

    func refresh() async {
        let providers = clientFactory.makeProviders(settings: settings)
        var next = snapshot
        next.sourceErrors = [:]

        if let status = providers.status {
            do { next.status = try await status.fetchStatus() }
            catch { next.sourceErrors[.status] = error.localizedDescription }
        }

        if let subscription = providers.subscription {
            do {
                let u = try await subscription.fetchUsage()
                next.fiveHour = u.fiveHour; next.sevenDay = u.sevenDay; next.sevenDayOpus = u.sevenDayOpus
                next.weeklyFable = settings.trackFable ? u.weeklyFable : nil
            } catch { next.sourceErrors[.subscription] = error.localizedDescription }
        }

        if settings.spendEnabled, let spend = providers.spend, shouldFetchSpend() {
            do { next.monthlySpendUSD = try await spend.fetchMonthlySpendUSD(); lastSpendFetch = Date() }
            catch { next.sourceErrors[.spend] = error.localizedDescription }
        }
        if !settings.spendEnabled { next.monthlySpendUSD = nil }

        next.lastUpdated = Date()
        snapshot = next

        if settings.notificationsEnabled {
            for kind in WindowKind.allCases {
                guard let usage = next.usage(for: kind) else { continue }
                for threshold in tracker.crossings(kind: kind, utilization: usage.utilization) {
                    onThresholdCrossed?(kind, threshold)
                }
            }
        }
    }

    private func shouldFetchSpend() -> Bool {
        guard let last = lastSpendFetch else { return true }
        return Date().timeIntervalSince(last) >= 120
    }
}

protocol ClientFactory: Sendable {
    @MainActor func makeProviders(settings: AppSettings) -> UsageStore.ClientProviders
}

struct LiveClientFactory: ClientFactory {
    @MainActor func makeProviders(settings: AppSettings) -> UsageStore.ClientProviders {
        let status = StatusClient()
        let subscription = KeychainStore.shared.get(.sessionKey).map { SubscriptionUsageClient(sessionKey: $0) }
        let spend = (settings.spendEnabled ? KeychainStore.shared.get(.adminKey) : nil).map { ConsoleSpendClient(adminKey: $0) }
        return .init(status: status, subscription: subscription, spend: spend)
    }
}
