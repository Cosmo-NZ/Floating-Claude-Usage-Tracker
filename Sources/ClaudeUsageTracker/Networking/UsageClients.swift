import Foundation

protocol StatusProviding: Sendable { func fetchStatus() async throws -> ServiceStatus }
protocol SubscriptionProviding: Sendable {
    func fetchUsage() async throws -> SubscriptionUsage
}
protocol SpendProviding: Sendable { func fetchMonthlySpendUSD() async throws -> Double }

struct SubscriptionUsage: Equatable {
    var fiveHour: WindowUsage?
    var sevenDay: WindowUsage?
    var sevenDayOpus: WindowUsage?
    var weeklyFable: WindowUsage?
}

struct HTTPError: Error, LocalizedError {
    let status: Int
    let body: String
    var errorDescription: String? { "HTTP \(status)" }
}

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    static func get(_ url: URL, headers: [String: String] = [:], debugLabel: String) async throws -> Data {
        var request = URLRequest(url: url)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await session.data(for: request)
        if ProcessInfo.processInfo.environment["CUT_DEBUG"] == "1" {
            FileHandle.standardError.write(Data("[\(debugLabel)] \(String(data: data, encoding: .utf8) ?? "<binary>")\n".utf8))
        }
        guard let http = response as? HTTPURLResponse else { return data }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
