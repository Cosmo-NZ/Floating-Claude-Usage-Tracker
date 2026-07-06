import Foundation

struct ConsoleSpendClient: SpendProviding {
    let adminKey: String

    func fetchMonthlySpendUSD() async throws -> Double {
        var components = URLComponents(string: "https://api.anthropic.com/v1/organizations/cost_report")!
        components.queryItems = [URLQueryItem(name: "starting_at", value: Self.monthStartISO(now: Date()))]
        let data = try await HTTP.get(components.url!, headers: [
            "x-api-key": adminKey,
            "anthropic-version": "2023-06-01",
        ], debugLabel: "cost_report")
        return try Self.parseSpend(data)
    }

    static func monthStartISO(now: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month], from: now)
        let start = cal.date(from: comps)!
        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(identifier: "UTC")
        return iso.string(from: start)
    }

    static func parseSpend(_ data: Data) throws -> Double {
        struct Result: Decodable { let amount: String? }
        struct Bucket: Decodable { let results: [Result]? }
        struct Response: Decodable { let data: [Bucket]? }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return (response.data ?? []).reduce(0.0) { sum, bucket in
            sum + (bucket.results ?? []).reduce(0.0) { $0 + (Double($1.amount ?? "0") ?? 0) }
        }
    }
}
