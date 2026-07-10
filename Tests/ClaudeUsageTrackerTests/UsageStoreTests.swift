import XCTest
@testable import ClaudeUsageTracker

@MainActor
final class UsageStoreTests: XCTestCase {
    struct FakeStatus: StatusProviding {
        let value: ServiceStatus
        func fetchStatus() async throws -> ServiceStatus { value }
    }
    struct FakeSubscription: SubscriptionProviding {
        let five: WindowUsage?
        func fetchUsage() async throws -> SubscriptionUsage {
            SubscriptionUsage(fiveHour: five, sevenDay: nil, sevenDayOpus: nil, weeklyFable: nil)
        }
    }
    struct FailingSpend: SpendProviding {
        func fetchMonthlySpendUSD() async throws -> Double { throw HTTPError(status: 500, body: "boom") }
    }
    struct FakeFactory: ClientFactory {
        let providers: UsageStore.ClientProviders
        func makeProviders(settings: AppSettings) -> UsageStore.ClientProviders { providers }
    }

    func testRefreshMergesResultsAndRecordsPerSourceErrors() async {
        let five = WindowUsage(utilization: 0.5, resetsAt: Date().addingTimeInterval(3600), windowLength: 5 * 3600)
        let factory = FakeFactory(providers: .init(
            status: FakeStatus(value: .operational),
            subscription: FakeSubscription(five: five),
            spend: FailingSpend()))
        let settings = AppSettings(suiteName: "test-\(UUID().uuidString)")
        settings.spendEnabled = true
        let store = UsageStore(settings: settings, clientFactory: factory)

        await store.refresh()

        XCTAssertEqual(store.snapshot.status, .operational)
        XCTAssertEqual(store.snapshot.fiveHour, five)
        XCTAssertNil(store.snapshot.monthlySpendUSD)
        XCTAssertNotNil(store.snapshot.sourceErrors[.spend])
        XCTAssertNotNil(store.snapshot.lastUpdated)
    }

    func testThresholdCallbackFires() async {
        let five = WindowUsage(utilization: 0.96, resetsAt: Date().addingTimeInterval(3600), windowLength: 5 * 3600)
        let factory = FakeFactory(providers: .init(
            status: nil, subscription: FakeSubscription(five: five), spend: nil))
        let settings = AppSettings(suiteName: "test-\(UUID().uuidString)")
        settings.notificationsEnabled = true
        let store = UsageStore(settings: settings, clientFactory: factory)
        var fired: [Double] = []
        store.onThresholdCrossed = { _, t in fired.append(t) }

        await store.refresh()

        XCTAssertEqual(fired.sorted(), [0.75, 0.90, 0.95])
    }
}
